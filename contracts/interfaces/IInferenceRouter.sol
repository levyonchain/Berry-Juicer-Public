// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title IInferenceRouter
/// @notice Converts a creator's quote-asset yield into inference credits via a partner program.
/// @dev The router is the seam between Berry and whichever inference partner is active. The
///      vault sends quote-asset yield here when a creator has selected {YieldMode.Inference};
///      the router is responsible for acquiring credits and crediting the recipient. The
///      concrete partner integration is configured per deployment and may change over time
///      without touching the vault.
interface IInferenceRouter {
    /// @notice Emitted when quote-asset yield is converted into inference credits.
    event InferenceFulfilled(address indexed recipient, uint256 quoteIn, uint256 creditsOut);

    /// @notice Route `quoteAmount` of `quoteAsset` into inference credits for `recipient`.
    /// @return credits The number of inference credits granted.
    function fulfill(address recipient, address quoteAsset, uint256 quoteAmount)
        external
        returns (uint256 credits);

    /// @notice Quote how many credits `quoteAmount` would yield, without executing.
    function quoteCredits(address quoteAsset, uint256 quoteAmount) external view returns (uint256 credits);

    /// @notice Whether the inference path is currently available (a partner is configured/live).
    function isActive() external view returns (bool);
}
