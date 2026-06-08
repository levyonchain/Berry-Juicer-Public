// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BerryJuicerVault} from "../contracts/BerryJuicerVault.sol";
import {IBerryJuicer} from "../contracts/interfaces/IBerryJuicer.sol";
import {YieldSplit} from "../contracts/libraries/YieldSplit.sol";
import {JuicerLens} from "../contracts/periphery/JuicerLens.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ReferenceStrategy, ReferenceInferenceRouter} from "./mocks/ReferenceStrategy.sol";

contract BerryJuicerVaultTest is Test {
    BerryJuicerVault internal vault;
    ReferenceStrategy internal strategy;
    ReferenceInferenceRouter internal router;
    JuicerLens internal lens;

    MockERC20 internal token; // the creator's supply
    MockERC20 internal quote; // pool quote asset (e.g. WETH)

    address internal creator = address(0xC0FFEE);
    address internal feeRecipient = address(0xFEE);
    address internal outsider = address(0xBAD);

    uint256 internal constant FEE_BPS = 2_000; // 20% protocol fee

    function setUp() public {
        token = new MockERC20("Project", "PRJ");
        quote = new MockERC20("Wrapped Ether", "WETH");

        strategy = new ReferenceStrategy(address(quote));
        vault = new BerryJuicerVault(address(strategy), feeRecipient, FEE_BPS);
        router = new ReferenceInferenceRouter();
        lens = new JuicerLens(address(vault));

        token.mint(creator, 1_000_000e18);
        vm.prank(creator);
        token.approve(address(vault), type(uint256).max);
    }

    function _open() internal returns (uint256 id) {
        vm.prank(creator);
        id = vault.deposit(address(token), 100_000e18, IBerryJuicer.YieldMode.Quote);
    }

    function test_Deposit_RecordsPosition() public {
        uint256 id = _open();
        (address c, address t, uint256 amt, IBerryJuicer.YieldMode mode) = vault.positionInfo(id);
        assertEq(c, creator);
        assertEq(t, address(token));
        assertEq(amt, 100_000e18);
        assertEq(uint256(mode), uint256(IBerryJuicer.YieldMode.Quote));
    }

    function test_Distribute_SplitsYield80_20() public {
        uint256 id = _open();

        // simulate 10 WETH of accrued fees
        strategy.simulateFees(_key(id), 10e18);

        vault.distribute(id); // permissionless trigger

        // 20% to protocol, 80% to creator
        assertEq(quote.balanceOf(feeRecipient), 2e18);
        assertEq(quote.balanceOf(creator), 8e18);
    }

    function test_InferenceMode_RoutesToRouter() public {
        vm.prank(creator);
        uint256 id = vault.deposit(address(token), 100_000e18, IBerryJuicer.YieldMode.Inference);

        vault.setInferenceRouter(address(router)); // owner = this test contract
        strategy.simulateFees(_key(id), 10e18);

        vault.distribute(id);

        // creator gets credits, not quote; protocol still gets its cut in quote
        assertEq(router.creditsOf(creator), 8e18);
        assertEq(quote.balanceOf(feeRecipient), 2e18);
        assertEq(quote.balanceOf(creator), 0);
    }

    function test_InferenceMode_RevertsWhenRouterInactive() public {
        vm.prank(creator);
        uint256 id = vault.deposit(address(token), 100_000e18, IBerryJuicer.YieldMode.Inference);

        vault.setInferenceRouter(address(router));
        router.setActive(false);
        strategy.simulateFees(_key(id), 5e18);

        vm.expectRevert(BerryJuicerVault.InferenceUnavailable.selector);
        vault.distribute(id);
    }

    function test_Withdraw_ReturnsPrincipalAndClosesPosition() public {
        uint256 id = _open();
        strategy.simulateFees(_key(id), 4e18);

        vm.prank(creator);
        vault.withdraw(id);

        // principal returned, yield settled (80% of 4 = 3.2)
        assertEq(token.balanceOf(creator), 1_000_000e18); // 900k left + 100k returned
        assertEq(quote.balanceOf(creator), 3.2e18);
    }

    function test_Withdraw_OnlyCreator() public {
        uint256 id = _open();
        vm.prank(outsider);
        vm.expectRevert(BerryJuicerVault.NotCreator.selector);
        vault.withdraw(id);
    }

    function test_SetYieldMode_OnlyCreator() public {
        uint256 id = _open();
        vm.prank(outsider);
        vm.expectRevert(BerryJuicerVault.NotCreator.selector);
        vault.setYieldMode(id, IBerryJuicer.YieldMode.Inference);
    }

    function test_Lens_ProjectsSplit() public {
        uint256 id = _open();
        strategy.simulateFees(_key(id), 10e18);

        JuicerLens.PositionView memory v = lens.getPosition(id);
        assertEq(v.pendingTotal, 10e18);
        assertEq(v.pendingProtocol, 2e18);
        assertEq(v.pendingCreator, 8e18);
    }

    function testFuzz_YieldSplitNeverShortsCreator(uint128 total, uint16 feeBps) public pure {
        vm.assume(feeBps <= YieldSplit.MAX_PROTOCOL_FEE_BPS);
        (uint256 protocolShare, uint256 creatorShare) = YieldSplit.split(total, feeBps);
        assertEq(protocolShare + creatorShare, total); // no value created or lost
        assertLe(protocolShare, total);
    }

    function test_YieldSplit_RevertsAboveMax() public {
        // Set the fee above the library's max, then trigger a split via distribute().
        // The revert originates inside YieldSplit at an external call boundary.
        uint256 id = _open();
        vault.setFee(6000, feeRecipient); // > MAX_PROTOCOL_FEE_BPS (5000)
        strategy.simulateFees(_key(id), 1e18);

        vm.expectRevert(abi.encodeWithSelector(YieldSplit.FeeTooHigh.selector, uint256(6000)));
        vault.distribute(id);
    }

    // ReferenceStrategy keys positions deterministically; recompute for assertions.
    function _key(
        uint256 /*id*/
    )
        internal
        view
        returns (bytes32)
    {
        // the strategy assigns keys by an internal nonce starting at 0; in these single-position
        // tests the first opened position has nonce 0.
        return keccak256(abi.encodePacked(address(vault), address(token), uint256(100_000e18), uint256(0)));
    }
}
