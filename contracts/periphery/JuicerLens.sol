// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IBerryJuicer} from "../interfaces/IBerryJuicer.sol";
import {YieldSplit} from "../libraries/YieldSplit.sol";

interface IJuicerFactoryView {
    function vaultsOf(address creator) external view returns (address[] memory);
}

/// @title JuicerLens
/// @notice Read-only convenience layer over Berry Juicer position vaults. Bundles the calls an
///         agent or frontend usually wants into a single round trip. Holds no funds, no permissions.
/// @dev Periphery, fully open. Composes public view functions and the open {YieldSplit} math; never
///      touches the proprietary strategy.
contract JuicerLens {
    struct PositionView {
        address vault;
        address creator;
        address token;
        uint256 amount;
        bool open;
        uint256 pendingFees;
        uint256 creatorValue; // to be credited as inference for the creator
        uint256 protocolMargin; // retained by the protocol
    }

    /// @notice Snapshot a single position vault, including the projected fee split.
    function getPosition(address vault) public view returns (PositionView memory view_) {
        IBerryJuicer j = IBerryJuicer(vault);
        (address token, uint256 amount, bool open) = j.position();
        uint256 fees = j.pendingFees();
        (uint256 creatorValue, uint256 protocolMargin) = YieldSplit.split(fees, j.creatorShareBps());

        view_ = PositionView({
            vault: vault,
            creator: j.creator(),
            token: token,
            amount: amount,
            open: open,
            pendingFees: fees,
            creatorValue: creatorValue,
            protocolMargin: protocolMargin
        });
    }

    /// @notice Snapshot several vaults at once. Convenient for agents polling many positions.
    function getPositions(address[] calldata vaults) external view returns (PositionView[] memory views) {
        views = new PositionView[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            views[i] = getPosition(vaults[i]);
        }
    }

    /// @notice Snapshot every vault a creator owns, via the factory's index.
    function getCreatorPositions(address factory, address creator)
        external
        view
        returns (PositionView[] memory views)
    {
        address[] memory vaults = IJuicerFactoryView(factory).vaultsOf(creator);
        views = new PositionView[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            views[i] = getPosition(vaults[i]);
        }
    }
}
