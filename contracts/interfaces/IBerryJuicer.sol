// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title IBerryJuicer
/// @notice Public interface for a single Berry Juicer position vault.
/// @dev Each vault is one position, deployed per deposit by the factory, so positions are
///      isolated: a vault custodies only its own creator's principal and fees.
///
///      Payout model: all collected fees are split. The creator's share is credited as AI
///      inference (routed via {IInferenceRouter}, fulfilled off-chain through partner programs);
///      the protocol retains the remainder as margin. The deposited supply is the creator's
///      principal and is returned in full on withdraw. The creator does not receive the quote
///      asset for their fee share (except as a safety fallback if inference is unavailable at exit).
interface IBerryJuicer {
    /// @notice Emitted when fees are harvested and the creator is credited inference.
    event Harvested(
        address indexed creator, uint256 feesCollected, uint256 creatorValue, uint256 protocolMargin
    );

    /// @notice Emitted when the creator withdraws, closing the position.
    event Withdrawn(address indexed creator, uint256 tokenReturned, uint256 quoteReturned);

    /// @notice Harvest accrued fees: credit the creator inference for their share, protocol its margin.
    /// @dev Permissionless; proceeds always route to the creator and protocol, so anyone (typically
    ///      the operator/automation) may trigger it without being able to divert funds.
    function harvest() external;

    /// @notice Withdraw the position in full. Only the creator. Settles fees, then returns principal.
    function withdraw() external;

    /// @notice The creator of this position.
    function creator() external view returns (address);

    /// @notice The deposited token and original amount.
    function position() external view returns (address token, uint256 amount, bool open);

    /// @notice The creator's share of fees (credited as inference), in basis points.
    function creatorShareBps() external view returns (uint256);

    /// @notice Accrued, unharvested fees, in quote-asset terms.
    function pendingFees() external view returns (uint256);
}
