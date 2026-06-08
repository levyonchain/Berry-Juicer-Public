// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title IJuicerStrategy
/// @notice The boundary between an open per-position vault and the closed-source position strategy.
/// @dev Public interface, proprietary implementation. The strategy owns the single-sided position
///      math: how a range is chosen on Uniswap V4, how liquidity is placed and rebalanced, and how
///      fees are accounted. Crucially, funds custody lives in the calling vault, not here: each
///      vault is its own position and its own balance, so positions are isolated from one another.
///      The strategy acts on a vault's position; it is not a shared pot of everyone's funds.
interface IJuicerStrategy {
    /// @notice Open the calling vault's single-sided position for `token` with `amount`.
    /// @return key An opaque identifier for the opened position.
    function open(address token, uint256 amount) external returns (bytes32 key);

    /// @notice Realize accrued fees for a position into the calling vault, returning the amount
    ///         (in quote-asset terms) now available to the vault.
    function collect(bytes32 key) external returns (uint256 quoteAmount);

    /// @notice Close a position, returning the principal amounts (token and quote) the vault should
    ///         return to its creator.
    function close(bytes32 key) external returns (uint256 tokenAmount, uint256 quoteAmount);

    /// @notice View accrued, unrealized fees for a position, in quote-asset terms.
    function accrued(bytes32 key) external view returns (uint256 quoteAmount);

    /// @notice The quote asset (e.g. WETH or USDC) this strategy denominates fees in.
    function quoteAsset() external view returns (address);
}
