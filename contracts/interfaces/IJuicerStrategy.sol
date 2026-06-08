// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title IJuicerStrategy
/// @notice The boundary between the open Juicer vault and the closed-source position strategy.
/// @dev This interface is public so integrators understand the seam, but the implementation is
///      proprietary. The strategy owns the single-sided position math: how a range is chosen,
///      how liquidity is placed on Uniswap V4, when and how it is rebalanced, and how fees are
///      accounted. The vault holds funds and enforces access control; it delegates position
///      mechanics to a strategy implementing this interface.
///
///      Keeping the strategy behind an interface lets the vault, periphery, and SDK be fully
///      open without disclosing the part of the system that is genuinely novel.
interface IJuicerStrategy {
    /// @notice Open a single-sided position for `token` with `amount`.
    /// @return key An opaque strategy-side identifier for the opened position.
    function open(address token, uint256 amount) external returns (bytes32 key);

    /// @notice Collect accrued fees for a position, returning the amount in quote-asset terms.
    function collect(bytes32 key) external returns (uint256 quoteAmount);

    /// @notice Close a position, returning remaining token and quote balances to the caller.
    function close(bytes32 key) external returns (uint256 tokenAmount, uint256 quoteAmount);

    /// @notice View accrued, uncollected fees for a position, in quote-asset terms.
    function accrued(bytes32 key) external view returns (uint256 quoteAmount);

    /// @notice The quote asset (e.g. WETH or USDC) this strategy denominates fees in.
    function quoteAsset() external view returns (address);
}
