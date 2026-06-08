// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title IBerryJuicer
/// @notice Public interface for a Berry Juicer vault.
/// @dev A Juicer vault accepts a single token deposit from a creator and deploys it as a
///      single-sided concentrated liquidity position. The position earns swap fees, which are
///      split between the creator and the protocol. The creator may take their share as the
///      pool's quote asset or, where enabled, as inference credits.
///
///      The concrete position math and rebalancing logic live in a closed-source strategy that
///      implements {IJuicerStrategy}. This interface is the stable, public surface that wallets,
///      agents, and integrators build against; it intentionally exposes no detail about how a
///      range is chosen or maintained.
interface IBerryJuicer {
    /// @notice How a creator elects to receive their share of yield.
    enum YieldMode {
        Quote, // paid in the pool's quote asset (e.g. WETH, USDC)
        Inference // routed to inference credits via a partner program
    }

    /// @notice Emitted when a creator opens a position.
    event Deposited(address indexed creator, address indexed token, uint256 amount, YieldMode mode);

    /// @notice Emitted when accrued yield is distributed for a position.
    event YieldDistributed(address indexed creator, uint256 creatorShare, uint256 protocolShare);

    /// @notice Emitted when a creator changes how their yield is paid out.
    event YieldModeChanged(address indexed creator, YieldMode mode);

    /// @notice Emitted when a creator withdraws their position.
    event Withdrawn(address indexed creator, uint256 tokenReturned, uint256 quoteReturned);

    /// @notice Open a Juicer position by depositing `amount` of `token`.
    /// @param token  The ERC-20 whose supply is being deployed.
    /// @param amount The amount of `token` to deposit. Pulled from the caller; requires approval.
    /// @param mode   How the caller wishes to receive yield.
    /// @return positionId An opaque handle for the created position.
    function deposit(address token, uint256 amount, YieldMode mode) external returns (uint256 positionId);

    /// @notice Withdraw a position in full, returning remaining token balance, quote, and fees.
    /// @dev Permitted at any time. Only the position's creator may call.
    function withdraw(uint256 positionId) external;

    /// @notice Change the yield payout mode for an existing position.
    function setYieldMode(uint256 positionId, YieldMode mode) external;

    /// @notice The protocol's share of yield, in basis points (e.g. 2000 = 20%).
    function protocolFeeBps() external view returns (uint256);

    /// @notice Current accrued, undistributed yield for a position, in quote-asset terms.
    function pendingYield(uint256 positionId) external view returns (uint256);

    /// @notice Read a position's static parameters.
    /// @return creator The owner of the position.
    /// @return token   The deposited token.
    /// @return amount  The originally deposited amount.
    /// @return mode    The current yield mode.
    function positionInfo(uint256 positionId)
        external
        view
        returns (address creator, address token, uint256 amount, YieldMode mode);
}
