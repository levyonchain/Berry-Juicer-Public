// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IBerryJuicer} from "./interfaces/IBerryJuicer.sol";
import {IJuicerStrategy} from "./interfaces/IJuicerStrategy.sol";
import {IInferenceRouter} from "./interfaces/IInferenceRouter.sol";
import {YieldSplit} from "./libraries/YieldSplit.sol";

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title BerryJuicerVault
/// @notice The open orchestration layer of Berry Juicer. Custodies creator deposits, enforces
///         access control, splits yield, and routes payouts. It delegates all position mechanics
///         to a strategy implementing {IJuicerStrategy} (proprietary, not in this repo).
/// @dev Intentionally open. Nothing here reveals how positions are ranged or rebalanced; the
///      vault only knows "open / collect / close" against the strategy seam. Funds custody and
///      authorization live here so they can be reviewed publicly.
contract BerryJuicerVault is IBerryJuicer {
    IJuicerStrategy public immutable strategy;
    IInferenceRouter public inferenceRouter;
    address public immutable quote;

    uint256 public protocolFeeBps;
    address public feeRecipient;
    address public owner;

    struct Position {
        address creator;
        address token;
        uint256 amount;
        YieldMode mode;
        bytes32 strategyKey;
        bool open;
    }

    mapping(uint256 => Position) internal positions;
    uint256 public nextPositionId = 1;

    // simple non-reentrant guard
    uint256 private _lock = 1;

    error NotOwner();
    error NotCreator();
    error PositionClosed();
    error InferenceUnavailable();
    error Reentrant();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier nonReentrant() {
        if (_lock != 1) revert Reentrant();
        _lock = 2;
        _;
        _lock = 1;
    }

    constructor(address strategy_, address feeRecipient_, uint256 protocolFeeBps_) {
        strategy = IJuicerStrategy(strategy_);
        quote = IJuicerStrategy(strategy_).quoteAsset();
        feeRecipient = feeRecipient_;
        protocolFeeBps = protocolFeeBps_;
        owner = msg.sender;
    }

    // --- creator actions ---------------------------------------------------

    /// @inheritdoc IBerryJuicer
    function deposit(address token, uint256 amount, YieldMode mode)
        external
        nonReentrant
        returns (uint256 positionId)
    {
        // pull the creator's supply, then hand it to the strategy to deploy
        IERC20Minimal(token).transferFrom(msg.sender, address(strategy), amount);
        bytes32 key = strategy.open(token, amount);

        positionId = nextPositionId++;
        positions[positionId] = Position({
            creator: msg.sender, token: token, amount: amount, mode: mode, strategyKey: key, open: true
        });

        emit Deposited(msg.sender, token, amount, mode);
    }

    /// @inheritdoc IBerryJuicer
    function setYieldMode(uint256 positionId, YieldMode mode) external {
        Position storage p = positions[positionId];
        if (msg.sender != p.creator) revert NotCreator();
        if (!p.open) revert PositionClosed();
        p.mode = mode;
        emit YieldModeChanged(msg.sender, mode);
    }

    /// @notice Collect and distribute accrued yield for a position to its creator.
    /// @dev Permissionless to call; proceeds always go to the position's creator, so anyone
    ///      (including an automation bot) may trigger a distribution without being able to divert it.
    function distribute(uint256 positionId) public nonReentrant {
        Position storage p = positions[positionId];
        if (!p.open) revert PositionClosed();

        uint256 collected = strategy.collect(p.strategyKey);
        if (collected == 0) return;

        (uint256 protocolShare, uint256 creatorShare) = YieldSplit.split(collected, protocolFeeBps);

        if (protocolShare > 0) IERC20Minimal(quote).transfer(feeRecipient, protocolShare);
        _payCreator(p, creatorShare);

        emit YieldDistributed(p.creator, creatorShare, protocolShare);
    }

    /// @inheritdoc IBerryJuicer
    function withdraw(uint256 positionId) external nonReentrant {
        Position storage p = positions[positionId];
        if (msg.sender != p.creator) revert NotCreator();
        if (!p.open) revert PositionClosed();

        // settle any outstanding yield first, then close the underlying position
        uint256 collected = strategy.collect(p.strategyKey);
        if (collected > 0) {
            (uint256 protocolShare, uint256 creatorShare) = YieldSplit.split(collected, protocolFeeBps);
            if (protocolShare > 0) IERC20Minimal(quote).transfer(feeRecipient, protocolShare);
            _payCreator(p, creatorShare);
        }

        (uint256 tokenReturned, uint256 quoteReturned) = strategy.close(p.strategyKey);
        p.open = false;

        if (tokenReturned > 0) IERC20Minimal(p.token).transfer(p.creator, tokenReturned);
        if (quoteReturned > 0) IERC20Minimal(quote).transfer(p.creator, quoteReturned);

        emit Withdrawn(p.creator, tokenReturned, quoteReturned);
    }

    // --- payout routing ----------------------------------------------------

    function _payCreator(Position storage p, uint256 amount) internal {
        if (amount == 0) return;

        if (p.mode == YieldMode.Inference) {
            // route through the configured inference partner; fall back is to revert,
            // so a creator never silently loses their yield if the path is down
            if (address(inferenceRouter) == address(0) || !inferenceRouter.isActive()) {
                revert InferenceUnavailable();
            }
            IERC20Minimal(quote).transfer(address(inferenceRouter), amount);
            inferenceRouter.fulfill(p.creator, quote, amount);
        } else {
            IERC20Minimal(quote).transfer(p.creator, amount);
        }
    }

    // --- views -------------------------------------------------------------

    /// @inheritdoc IBerryJuicer
    function pendingYield(uint256 positionId) external view returns (uint256) {
        return strategy.accrued(positions[positionId].strategyKey);
    }

    /// @inheritdoc IBerryJuicer
    function positionInfo(uint256 positionId)
        external
        view
        returns (address creator, address token, uint256 amount, YieldMode mode)
    {
        Position storage p = positions[positionId];
        return (p.creator, p.token, p.amount, p.mode);
    }

    // --- admin (config only; no power over creator funds) ------------------

    function setInferenceRouter(address router) external onlyOwner {
        inferenceRouter = IInferenceRouter(router);
    }

    function setFee(uint256 newFeeBps, address newRecipient) external onlyOwner {
        // bounded by YieldSplit.MAX_PROTOCOL_FEE_BPS at split time
        protocolFeeBps = newFeeBps;
        feeRecipient = newRecipient;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
