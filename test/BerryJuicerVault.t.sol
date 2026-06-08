// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BerryJuicerFactory} from "../contracts/BerryJuicerFactory.sol";
import {BerryJuicerVault} from "../contracts/BerryJuicerVault.sol";
import {IBerryJuicer} from "../contracts/interfaces/IBerryJuicer.sol";
import {YieldSplit} from "../contracts/libraries/YieldSplit.sol";
import {JuicerLens} from "../contracts/periphery/JuicerLens.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ReferenceStrategy, ReferenceInferenceRouter} from "./mocks/ReferenceStrategy.sol";

contract BerryJuicerTest is Test {
    BerryJuicerFactory internal factory;
    BerryJuicerVault internal implementation;
    ReferenceStrategy internal strategy;
    ReferenceInferenceRouter internal router;
    JuicerLens internal lens;

    MockERC20 internal token;
    MockERC20 internal quote;

    address internal creator = address(0xC0FFEE);
    address internal feeRecipient = address(0xFEE);
    address internal operator = address(0x09E12A);
    address internal outsider = address(0xBAD);

    uint256 internal constant CREATOR_SHARE_BPS = 8_000; // 80% to creator as inference

    function setUp() public {
        token = new MockERC20("Project", "PRJ");
        quote = new MockERC20("Wrapped Ether", "WETH");

        strategy = new ReferenceStrategy(address(quote));
        router = new ReferenceInferenceRouter();
        implementation = new BerryJuicerVault();
        factory = new BerryJuicerFactory(
            address(implementation),
            address(strategy),
            address(router),
            feeRecipient,
            operator,
            CREATOR_SHARE_BPS
        );
        lens = new JuicerLens();

        token.mint(creator, 1_000_000e18);
        vm.prank(creator);
        token.approve(address(factory), type(uint256).max);
    }

    function _create() internal returns (BerryJuicerVault vault) {
        vm.prank(creator);
        address v = factory.createVault(address(token), 100_000e18);
        vault = BerryJuicerVault(v);
    }

    function _keyAt(address vault, uint256 nonce) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(vault, address(token), uint256(100_000e18), nonce));
    }

    function test_Factory_DeploysIsolatedVault() public {
        BerryJuicerVault vault = _create();
        assertEq(vault.creator(), creator);
        (address t, uint256 amt, bool open) = vault.position();
        assertEq(t, address(token));
        assertEq(amt, 100_000e18);
        assertTrue(open);
        // principal custody is in the vault itself, not the factory or a shared pot
        assertEq(token.balanceOf(address(vault)), 100_000e18);
        assertEq(token.balanceOf(address(factory)), 0);
    }

    function test_TwoVaults_AreSeparateContracts() public {
        BerryJuicerVault a = _create();
        BerryJuicerVault b = _create();
        assertTrue(address(a) != address(b));
        address[] memory mine = factory.vaultsOf(creator);
        assertEq(mine.length, 2);
    }

    function test_Harvest_FeesToProtocol_CreatorGetsInference() public {
        BerryJuicerVault vault = _create();
        strategy.simulateFees(_keyAt(address(vault), 0), 10e18);

        vault.harvest(); // permissionless

        assertEq(router.creditsOf(creator), 8e18); // 80% credited as inference
        assertEq(quote.balanceOf(feeRecipient), 2e18); // 20% margin
        assertEq(quote.balanceOf(creator), 0); // never quote for the fee share
    }

    function test_Harvest_RevertsWhenRouterInactive() public {
        BerryJuicerVault vault = _create();
        router.setActive(false);
        strategy.simulateFees(_keyAt(address(vault), 0), 5e18);

        vm.expectRevert(BerryJuicerVault.InferenceUnavailable.selector);
        vault.harvest();
    }

    function test_Withdraw_ReturnsPrincipal_SettlesAsInference() public {
        BerryJuicerVault vault = _create();
        strategy.simulateFees(_keyAt(address(vault), 0), 4e18);

        vm.prank(creator);
        vault.withdraw();

        assertEq(token.balanceOf(creator), 1_000_000e18); // principal back
        assertEq(router.creditsOf(creator), 3.2e18); // 80% of 4
        assertEq(quote.balanceOf(feeRecipient), 0.8e18); // 20% margin
    }

    function test_Withdraw_FallsBackToQuoteWhenRouterDown() public {
        BerryJuicerVault vault = _create();
        strategy.simulateFees(_keyAt(address(vault), 0), 4e18);
        router.setActive(false);

        vm.prank(creator);
        vault.withdraw(); // must not revert; funds must not be trapped

        assertEq(token.balanceOf(creator), 1_000_000e18);
        assertEq(quote.balanceOf(creator), 3.2e18); // fee share returned as quote fallback
        assertEq(quote.balanceOf(feeRecipient), 0.8e18);
    }

    function test_Withdraw_OnlyCreator() public {
        BerryJuicerVault vault = _create();
        vm.prank(outsider);
        vm.expectRevert(BerryJuicerVault.NotCreator.selector);
        vault.withdraw();
    }

    function test_Vault_CannotReinitialize() public {
        BerryJuicerVault vault = _create();
        vm.expectRevert(BerryJuicerVault.AlreadyInitialized.selector);
        vault.initialize(
            outsider,
            address(token),
            1,
            address(strategy),
            address(router),
            feeRecipient,
            operator,
            CREATOR_SHARE_BPS
        );
    }

    function test_Lens_ProjectsSplit() public {
        BerryJuicerVault vault = _create();
        strategy.simulateFees(_keyAt(address(vault), 0), 10e18);

        JuicerLens.PositionView memory v = lens.getPosition(address(vault));
        assertEq(v.pendingFees, 10e18);
        assertEq(v.creatorValue, 8e18);
        assertEq(v.protocolMargin, 2e18);
        assertEq(v.creator, creator);
    }

    function testFuzz_SplitConservesValueAndRespectsFloor(uint128 total, uint16 shareBps) public pure {
        vm.assume(shareBps >= YieldSplit.MIN_CREATOR_SHARE_BPS && shareBps <= 10_000);
        (uint256 creatorValue, uint256 protocolMargin) = YieldSplit.split(total, shareBps);
        assertEq(creatorValue + protocolMargin, total);
        assertGe(creatorValue, protocolMargin);
    }

    function test_Split_RevertsBelowFloor() public {
        // Deploy a factory configured below the creator-share floor, then trigger a split via
        // harvest(). The revert originates in YieldSplit at an external call boundary.
        BerryJuicerFactory badFactory = new BerryJuicerFactory(
            address(implementation), address(strategy), address(router), feeRecipient, operator, 4000
        );
        vm.prank(creator);
        token.approve(address(badFactory), type(uint256).max);
        vm.prank(creator);
        address v = badFactory.createVault(address(token), 100_000e18);

        strategy.simulateFees(_keyAt(v, 0), 1e18);

        vm.expectRevert(abi.encodeWithSelector(YieldSplit.InvalidCreatorShare.selector, uint256(4000)));
        BerryJuicerVault(v).harvest();
    }
}
