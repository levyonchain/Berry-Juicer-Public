// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title YieldSplit
/// @notice Pure helpers for splitting accrued yield between a creator and the protocol.
/// @dev This is deliberately simple and open. The split is a published parameter of the
///      protocol, not part of the proprietary strategy, so the math lives here in the clear.
///      Basis points are used throughout (10_000 = 100%).
library YieldSplit {
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @notice Maximum protocol fee the vault will ever accept, as a safety bound (50%).
    uint256 internal constant MAX_PROTOCOL_FEE_BPS = 5_000;

    error FeeTooHigh(uint256 feeBps);

    /// @notice Split `total` yield into the protocol's cut and the creator's remainder.
    /// @param total           The total accrued yield to split.
    /// @param protocolFeeBps  The protocol's share in basis points.
    /// @return protocolShare  Amount owed to the protocol.
    /// @return creatorShare   Amount owed to the creator.
    function split(uint256 total, uint256 protocolFeeBps)
        internal
        pure
        returns (uint256 protocolShare, uint256 creatorShare)
    {
        if (protocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert FeeTooHigh(protocolFeeBps);

        // Round the protocol's share down so the creator is never shorted by rounding.
        protocolShare = (total * protocolFeeBps) / BPS_DENOMINATOR;
        creatorShare = total - protocolShare;
    }
}
