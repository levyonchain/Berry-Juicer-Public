// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IBerryJuicer} from "./interfaces/IBerryJuicer.sol";
import {IJuicerStrategy} from "./interfaces/IJuicerStrategy.sol";
import {IInferenceRouter} from "./interfaces/IInferenceRouter.sol";
import {YieldSplit} from "./libraries/YieldSplit.sol";

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

/// @title BerryJuicerVault
/// @notice A single Berry Juicer position. One vault per deposit, deployed as a minimal-proxy
///         clone by {BerryJuicerFactory}. Each clone is its own custody and accounting boundary:
///         it holds only its own creator's principal and fees, so positions are isolated from one
///         another and there is no shared pool of funds to drain.
/// @dev Clone-safe: state is set in {initialize}, not a constructor, and there are no per-instance
///      immutables. The proprietary position math lives behind {IJuicerStrategy}; this vault only
///      orchestrates custody, the fee split, and payout routing.
contract BerryJuicerVault is IBerryJuicer {
    IJuicerStrategy public strategy;
    IInferenceRouter public inferenceRouter;
    address public quote;

    address public override creator;
    address public operator; // master handler; informational + may trigger harvests
    address public feeRecipient;
    uint256 public override creatorShareBps;

    address public token;
    uint256 public amount;
    bytes32 public strategyKey;
    bool public isOpen;

    bool private _initialized;
    uint256 private _lock = 1;

    error AlreadyInitialized();
    error NotCreator();
    error PositionClosed();
    error InferenceUnavailable();
    error Reentrant();

    modifier nonReentrant() {
        if (_lock != 1) revert Reentrant();
        _lock = 2;
        _;
        _lock = 1;
    }

    /// @notice Initialize a freshly-cloned vault. Assumes the factory has already transferred
    ///         `amount_` of `token_` into this contract. Opens the position via the strategy.
    /// @dev Callable once. The factory is the only intended caller.
    function initialize(
        address creator_,
        address token_,
        uint256 amount_,
        address strategy_,
        address inferenceRouter_,
        address feeRecipient_,
        address operator_,
        uint256 creatorShareBps_
    ) external {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;
        _lock = 1; // clones do not run field initializers, so set the guard here

        creator = creator_;
        token = token_;
        amount = amount_;
        strategy = IJuicerStrategy(strategy_);
        inferenceRouter = IInferenceRouter(inferenceRouter_);
        quote = IJuicerStrategy(strategy_).quoteAsset();
        feeRecipient = feeRecipient_;
        operator = operator_;
        creatorShareBps = creatorShareBps_;

        // the deposited supply already sits in this vault; deploy it as the position
        strategyKey = strategy.open(token_, amount_);
        isOpen = true;
    }

    /// @inheritdoc IBerryJuicer
    function harvest() public nonReentrant {
        if (!isOpen) revert PositionClosed();

        uint256 fees = strategy.collect(strategyKey);
        if (fees == 0) return;

        (uint256 creatorValue, uint256 protocolMargin) = YieldSplit.split(fees, creatorShareBps);

        if (address(inferenceRouter) == address(0) || !inferenceRouter.isActive()) {
            revert InferenceUnavailable();
        }

        if (protocolMargin > 0) IERC20Minimal(quote).transfer(feeRecipient, protocolMargin);
        if (creatorValue > 0) {
            IERC20Minimal(quote).transfer(address(inferenceRouter), creatorValue);
            inferenceRouter.creditInference(creator, quote, creatorValue);
        }

        emit Harvested(creator, fees, creatorValue, protocolMargin);
    }

    /// @inheritdoc IBerryJuicer
    function withdraw() external nonReentrant {
        if (msg.sender != creator) revert NotCreator();
        if (!isOpen) revert PositionClosed();

        // settle outstanding fees before closing
        uint256 fees = strategy.collect(strategyKey);
        if (fees > 0) {
            (uint256 creatorValue, uint256 protocolMargin) = YieldSplit.split(fees, creatorShareBps);
            if (protocolMargin > 0) IERC20Minimal(quote).transfer(feeRecipient, protocolMargin);
            if (creatorValue > 0) {
                if (address(inferenceRouter) != address(0) && inferenceRouter.isActive()) {
                    IERC20Minimal(quote).transfer(address(inferenceRouter), creatorValue);
                    inferenceRouter.creditInference(creator, quote, creatorValue);
                } else {
                    // safety fallback: never trap the creator's value. If inference is
                    // unavailable at exit, return the creator's fee share as quote.
                    IERC20Minimal(quote).transfer(creator, creatorValue);
                }
            }
            emit Harvested(creator, fees, creatorValue, protocolMargin);
        }

        // return principal: the creator's deposited supply and any quote it converted into
        (uint256 tokenReturned, uint256 quoteReturned) = strategy.close(strategyKey);
        isOpen = false;

        if (tokenReturned > 0) IERC20Minimal(token).transfer(creator, tokenReturned);
        if (quoteReturned > 0) IERC20Minimal(quote).transfer(creator, quoteReturned);

        emit Withdrawn(creator, tokenReturned, quoteReturned);
    }

    /// @inheritdoc IBerryJuicer
    function position() external view returns (address token_, uint256 amount_, bool open_) {
        return (token, amount, isOpen);
    }

    /// @inheritdoc IBerryJuicer
    function pendingFees() external view returns (uint256) {
        return strategy.accrued(strategyKey);
    }
}
