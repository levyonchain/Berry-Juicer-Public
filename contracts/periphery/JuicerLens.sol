// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IBerryJuicer} from "../interfaces/IBerryJuicer.sol";
import {YieldSplit} from "../libraries/YieldSplit.sol";

/// @title JuicerLens
/// @notice Read-only convenience layer over {IBerryJuicer}. Bundles the calls an agent or
///         frontend usually wants into a single round trip. Holds no funds and no permissions.
/// @dev Periphery, fully open. Nothing here touches the proprietary strategy; it only composes
///      public view functions and the open {YieldSplit} math.
contract JuicerLens {
    IBerryJuicer public immutable juicer;

    constructor(address juicer_) {
        juicer = IBerryJuicer(juicer_);
    }

    /// @notice A flattened snapshot of a position, suitable for direct rendering.
    struct PositionView {
        address creator;
        address token;
        uint256 amount;
        IBerryJuicer.YieldMode mode;
        uint256 pendingTotal; // total accrued yield (quote terms)
        uint256 pendingCreator; // creator's share after the protocol fee
        uint256 pendingProtocol; // protocol's share
    }

    /// @notice Read a full position snapshot in one call, including the projected yield split.
    function getPosition(uint256 positionId) external view returns (PositionView memory view_) {
        (address creator, address token, uint256 amount, IBerryJuicer.YieldMode mode) =
            juicer.positionInfo(positionId);

        uint256 pending = juicer.pendingYield(positionId);
        (uint256 protocolShare, uint256 creatorShare) = YieldSplit.split(pending, juicer.protocolFeeBps());

        view_ = PositionView({
            creator: creator,
            token: token,
            amount: amount,
            mode: mode,
            pendingTotal: pending,
            pendingCreator: creatorShare,
            pendingProtocol: protocolShare
        });
    }

    /// @notice Batch-read several positions at once. Convenient for agents polling many vaults.
    function getPositions(uint256[] calldata positionIds)
        external
        view
        returns (PositionView[] memory views)
    {
        views = new PositionView[](positionIds.length);
        for (uint256 i = 0; i < positionIds.length; i++) {
            views[i] = this.getPosition(positionIds[i]);
        }
    }
}
