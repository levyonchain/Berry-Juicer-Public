// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IBerryJuicer} from "./interfaces/IBerryJuicer.sol";
import {IJuicerStrategy} from "./interfaces/IJuicerStrategy.sol";
import {IInferenceRouter} from "./interfaces/IInferenceRouter.sol";
import {YieldSplit} from "./libraries/YieldSplit.sol";

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

/// @dev Uniswap SwapRouter02 (no deadline field on this router's struct).
interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
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
    // B-ISOLATED: per-vault destination for THIS creator's harvested USDC share. When non-zero,
    // the creator's USDC goes here (their own dedicated inference wallet); when zero, it falls
    // back to the shared inferenceRouter (original behaviour). Isolation boundary: no pooling.
    address public inferencePayoutAddress;
    address public quote; // strategy quote asset (WETH) — what fees are collected in
    address public usdc; // settlement asset — what yield is converted to and credited in
    address public swapRouter; // Uniswap SwapRouter02
    uint24 public constant SWAP_FEE_TIER = 500; // USDC/WETH 0.05% — deepest pool on Base

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
    error NotOperator();
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
        uint256 creatorShareBps_,
        address swapRouter_,
        address usdc_,
        address inferencePayoutAddress_
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
        swapRouter = swapRouter_;
        usdc = usdc_;
        inferencePayoutAddress = inferencePayoutAddress_;

        // the deposited supply already sits in this vault; the strategy pulls it via
        // transferFrom, so grant a one-time exact-amount allowance, then open the position.
        IERC20Minimal(token_).approve(strategy_, amount_);
        strategyKey = strategy.open(token_, amount_);
        isOpen = true;
    }

    /// @inheritdoc IBerryJuicer
    /// @notice Collects LP fees (WETH), converts them to USDC in the same transaction, and
    ///         splits the USDC: protocol margin to the fee recipient, creator share to the
    ///         inference router (credited on-chain). Callable by the operator (the scheduled
    ///         harvest handler) or the vault's own creator.
    /// @param minUsdcOut Slippage floor for the WETH->USDC conversion, quoted off-chain by the
    ///        caller immediately before the call. Reverts if the swap returns less.
    function harvest(uint256 minUsdcOut) public nonReentrant returns (uint256 usdcOut) {
        if (msg.sender != operator && msg.sender != creator) revert NotOperator();
        if (!isOpen) revert PositionClosed();

        uint256 fees = strategy.collect(strategyKey);
        if (fees == 0) return 0;

        if (address(inferenceRouter) == address(0) || !inferenceRouter.isActive()) {
            revert InferenceUnavailable();
        }

        // convert WETH fees to USDC through the deepest pool on Base
        IERC20Minimal(quote).approve(swapRouter, fees);
        usdcOut = ISwapRouter02(swapRouter).exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: quote,
                tokenOut: usdc,
                fee: SWAP_FEE_TIER,
                recipient: address(this),
                amountIn: fees,
                amountOutMinimum: minUsdcOut,
                sqrtPriceLimitX96: 0
            })
        );

        (uint256 creatorValue, uint256 protocolMargin) = YieldSplit.split(usdcOut, creatorShareBps);

        if (protocolMargin > 0) IERC20Minimal(usdc).transfer(feeRecipient, protocolMargin);
        if (creatorValue > 0) {
            if (inferencePayoutAddress == address(0)) {
                // SHARED (legacy) path: USDC to the router, which tallies creditedOf.
                IERC20Minimal(usdc).transfer(address(inferenceRouter), creatorValue);
                inferenceRouter.creditInference(creator, usdc, creatorValue);
            } else {
                // B-ISOLATED path: USDC goes straight to the creator's OWN inference wallet.
                // The shared router is deliberately NOT touched — isolated creators share nothing
                // with it, and it would reject this vault anyway (it is not in the old registry).
                // Per-creator spend accounting lives off-chain against this wallet's USDC.
                IERC20Minimal(usdc).transfer(inferencePayoutAddress, creatorValue);
            }
        }

        emit Harvested(creator, usdcOut, creatorValue, protocolMargin);
    }

    /// @inheritdoc IBerryJuicer
    function withdraw() external nonReentrant {
        if (msg.sender != creator) revert NotCreator();
        if (!isOpen) revert PositionClosed();

        // settle outstanding fees before closing. The exit path deliberately performs NO swap
        // and touches NO external venue: the final fee crumbs are split in quote (WETH) and the
        // creator's share is paid to them directly. Exits never depend on a DEX or the router.
        uint256 fees = strategy.collect(strategyKey);
        if (fees > 0) {
            (uint256 creatorValue, uint256 protocolMargin) = YieldSplit.split(fees, creatorShareBps);
            if (protocolMargin > 0) IERC20Minimal(quote).transfer(feeRecipient, protocolMargin);
            if (creatorValue > 0) IERC20Minimal(quote).transfer(creator, creatorValue);
            emit Harvested(creator, fees, creatorValue, protocolMargin);
        }

        // return principal: the creator's deposited supply and any quote it converted into
        strategy.close(strategyKey);
        isOpen = false;

        // sweep FULL balances (not just close()'s reported deltas) so fee dust that landed in
        // this vault during collects is returned too — nothing is ever stranded in the clone.
        uint256 tokenBal = IERC20Minimal(token).balanceOf(address(this));
        uint256 quoteBal = IERC20Minimal(quote).balanceOf(address(this));
        if (tokenBal > 0) IERC20Minimal(token).transfer(creator, tokenBal);
        if (quoteBal > 0) IERC20Minimal(quote).transfer(creator, quoteBal);

        emit Withdrawn(creator, tokenBal, quoteBal);
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
