// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {BerryJuicerVault} from "../contracts/BerryJuicerVault.sol";

/// @notice Deploys BerryJuicerVault against an already-deployed strategy.
/// @dev The proprietary strategy is deployed separately and out of this repo. Supply its
///      address, the fee recipient, and the protocol fee (bps) via environment variables.
///
///      Usage:
///        forge script script/Deploy.s.sol \
///          --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --verify
contract Deploy is Script {
    function run() external returns (BerryJuicerVault vault) {
        address strategy = vm.envAddress("JUICER_STRATEGY");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        uint256 feeBps = vm.envOr("PROTOCOL_FEE_BPS", uint256(2000)); // default 20%

        vm.startBroadcast();
        vault = new BerryJuicerVault(strategy, feeRecipient, feeBps);
        vm.stopBroadcast();
    }
}
