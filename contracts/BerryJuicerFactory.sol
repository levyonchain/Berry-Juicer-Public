// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {BerryJuicerVault} from "./BerryJuicerVault.sol";

interface IERC20Pull {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title BerryJuicerFactory
/// @notice Deploys one isolated {BerryJuicerVault} per deposit, as an EIP-1167 minimal-proxy clone.
/// @dev Each position gets its own clone, so funds are never pooled across creators. The factory
///      holds the shared configuration (strategy, inference router, fee recipient, operator, and
///      default creator share) and stamps it onto each clone at creation.
///
///      The creator (msg.sender) triggers and pays for vault creation. The factory pulls the
///      deposit from the creator and forwards it straight into the new clone, then initializes it;
///      the factory never retains creator funds beyond the span of the call.
///
///      The `operator` is the master-handler wallet (e.g. a policy-scoped Privy server wallet) that
///      triggers harvests across vaults. It is recorded on each clone for reference; harvest itself
///      is permissionless and always routes proceeds to the creator and protocol, so the operator
///      cannot divert funds, it can only poke.
contract BerryJuicerFactory {
    address public immutable vaultImplementation;

    address public owner;
    address public operator;
    address public swapRouter;
    address public usdc;
    address public feeRecipient;
    address public inferenceRouter;
    // B-ISOLATED: creator -> dedicated inference USDC wallet. Set by owner/operator BEFORE the
    // creator's createVault, so the new vault inits with the isolated payout target. 0 = router.
    mapping(address => address) public inferencePayoutOf;
    event InferencePayoutSet(address indexed creator, address indexed wallet);
    address public strategy;
    uint256 public creatorShareBps;

    uint256 public vaultCount;
    mapping(uint256 => address) public vaultById;
    mapping(address => bool) public isVault;
    mapping(address => address[]) internal _vaultsOf;

    event VaultCreated(
        address indexed creator, address indexed vault, address token, uint256 amount, uint256 id
    );
    event ConfigUpdated();

    error NotOwner();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(
        address vaultImplementation_,
        address strategy_,
        address inferenceRouter_,
        address feeRecipient_,
        address operator_,
        uint256 creatorShareBps_,
        address swapRouter_,
        address usdc_
    ) {
        if (vaultImplementation_ == address(0) || strategy_ == address(0)) {
            revert ZeroAddress();
        }
        vaultImplementation = vaultImplementation_;
        strategy = strategy_;
        inferenceRouter = inferenceRouter_;
        feeRecipient = feeRecipient_;
        operator = operator_;
        creatorShareBps = creatorShareBps_;
        swapRouter = swapRouter_;
        usdc = usdc_;
        owner = msg.sender;
    }

    /// @notice Create an isolated Juicer position vault and deposit `amount` of `token` into it.
    /// @dev The caller must have approved this factory for `amount` of `token`. The caller pays gas.
    function createVault(address token, uint256 amount) external returns (address vault) {
        vault = _clone(vaultImplementation);

        uint256 id = ++vaultCount;
        vaultById[id] = vault;
        isVault[vault] = true;
        _vaultsOf[msg.sender].push(vault);

        // move the creator's supply directly into the new vault, then initialize it
        IERC20Pull(token).transferFrom(msg.sender, vault, amount);
        BerryJuicerVault(vault)
            .initialize(
                msg.sender,
                token,
                amount,
                strategy,
                inferenceRouter,
                feeRecipient,
                operator,
                creatorShareBps,
                swapRouter,
                usdc,
                inferencePayoutOf[msg.sender]
            );

        emit VaultCreated(msg.sender, vault, token, amount, id);
    }

    /// @notice All vaults created by `creator`.
    function vaultsOf(address creator) external view returns (address[] memory) {
        return _vaultsOf[creator];
    }

    // --- admin (config only; cannot touch deployed vaults' funds) ----------

    /// @notice B-ISOLATED: register a creator's dedicated inference wallet (owner or operator).
    function setInferencePayout(address creator, address wallet) external {
        require(msg.sender == owner || msg.sender == operator, "not authorized");
        inferencePayoutOf[creator] = wallet;
        emit InferencePayoutSet(creator, wallet);
    }

    function setConfig(address strategy_, address inferenceRouter_, address feeRecipient_, address operator_)
        external
        onlyOwner
    {
        if (strategy_ == address(0)) revert ZeroAddress();
        strategy = strategy_;
        inferenceRouter = inferenceRouter_;
        feeRecipient = feeRecipient_;
        operator = operator_;
        emit ConfigUpdated();
    }

    function setCreatorShare(uint256 newCreatorShareBps) external onlyOwner {
        creatorShareBps = newCreatorShareBps;
        emit ConfigUpdated();
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    /// @dev Minimal EIP-1167 clone. Cheap deploy; each clone has isolated storage and balance.
    function _clone(address impl) internal returns (address instance) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, impl))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create(0, ptr, 0x37)
        }
        require(instance != address(0), "clone failed");
    }
}
