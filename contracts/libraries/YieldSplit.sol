// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title YieldSplit
/// @notice Pure helper for splitting harvested fees between the creator's share (credited as
///         inference) and the protocol's margin.
/// @dev Open by design: the split is a published protocol parameter, not part of the proprietary
///      strategy. Basis points throughout (10_000 = 100%). Rounding dust favors the creator.
library YieldSplit {
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @notice The creator must always receive at least this share, as a trust floor.
    uint256 internal constant MIN_CREATOR_SHARE_BPS = 5_000; // 50%

    error InvalidCreatorShare(uint256 bps);

    /// @notice Split `total` fees into the creator's value and the protocol's margin.
    /// @param total            Total fees collected (quote-asset terms).
    /// @param creatorShareBps  The creator's share in basis points (e.g. 8000 = 80%).
    /// @return creatorValue    Quote-asset value to route to inference for the creator.
    /// @return protocolMargin  Quote-asset amount retained by the protocol.
    function split(uint256 total, uint256 creatorShareBps)
        internal
        pure
        returns (uint256 creatorValue, uint256 protocolMargin)
    {
        if (creatorShareBps < MIN_CREATOR_SHARE_BPS || creatorShareBps > BPS_DENOMINATOR) {
            revert InvalidCreatorShare(creatorShareBps);
        }

        // Compute the protocol margin by rounding down, so the creator receives any dust.
        uint256 marginBps = BPS_DENOMINATOR - creatorShareBps;
        protocolMargin = (total * marginBps) / BPS_DENOMINATOR;
        creatorValue = total - protocolMargin;
    }
}
