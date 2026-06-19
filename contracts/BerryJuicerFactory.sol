// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {BerryJuicerVault} from "./BerryJuicerVault.sol";

interface IERC20Pull {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
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
    error ZeroAmount();
    error TransferFailed();

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
    ///      The vault is initialized with the *delta actually received* (not the requested amount),
    ///      so fee-on-transfer / rebasing tokens cannot leave the vault claiming more than it holds.
    function createVault(address token, uint256 amount) external returns (address vault) {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        vault = _clone(vaultImplementation);

        uint256 id = ++vaultCount;
        vaultById[id] = vault;
        isVault[vault] = true;
        _vaultsOf[msg.sender].push(vault);

        // Pull the creator's supply directly into the new vault, measure the delta, then initialize.
        // Using the balance delta as the canonical amount makes the vault honest about its holdings
        // for fee-on-transfer or rebasing tokens. The SafeERC20-style call below also tolerates the
        // USDT-style ERC20s that return no data on success.
        uint256 beforeBal = IERC20Pull(token).balanceOf(vault);
        _safeTransferFrom(token, msg.sender, vault, amount);
        uint256 received = IERC20Pull(token).balanceOf(vault) - beforeBal;
        if (received == 0) revert TransferFailed();

        BerryJuicerVault(vault)
            .initialize(
                msg.sender,
                token,
                received,
                strategy,
                inferenceRouter,
                feeRecipient,
                operator,
                creatorShareBps,
                swapRouter,
                usdc,
                inferencePayoutOf[msg.sender]
            );

        emit VaultCreated(msg.sender, vault, token, received, id);
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

    /// @dev SafeERC20-style transferFrom: tolerates ERC20s that return no value on success
    ///      (e.g. USDT) and reverts on tokens that return false. The post-call balance check
    ///      in `createVault` is what makes fee-on-transfer / rebasing tokens safe; this helper
    ///      only guarantees the call did not silently fail.
    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Pull.transferFrom.selector, from, to, value)
        );
        if (!success) revert TransferFailed();
        // Empty return data is fine (USDT-style). Non-empty data must decode to true.
        if (data.length > 0 && !abi.decode(data, (bool))) revert TransferFailed();
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
