// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title IInferenceRouter
/// @notice The on-chain seam between a vault and the off-chain inference fulfillment system.
/// @dev When a vault harvests fees, it forwards the creator's share (in the quote asset) here and
///      records that the creator is owed inference of that value. This contract does NOT itself
///      deliver inference, AI inference is not an on-chain asset. Fulfillment happens off-chain:
///      Berry's backend watches the emitted entitlements, takes the forwarded quote, and provisions
///      inference to the creator through partner programs. Because inference is sourced at a
///      discount, the creator's credited value typically buys more compute than its face value.
///
///      The router is configured per deployment and the active partner integration may change over
///      time without touching the vaults.
interface IInferenceRouter {
    /// @notice Emitted when a creator is credited inference value (fulfilled off-chain).
    event InferenceCredited(address indexed recipient, address indexed quoteAsset, uint256 quoteValue);

    /// @notice Record that `recipient` is owed inference worth `quoteValue`, having received that
    ///         value in `quoteAsset`. Fulfillment is performed off-chain against this entitlement.
    function creditInference(address recipient, address quoteAsset, uint256 quoteValue) external;

    /// @notice Whether the inference path is currently available (a partner is configured/live).
    function isActive() external view returns (bool);
}
