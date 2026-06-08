// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {BerryJuicerVault} from "../contracts/BerryJuicerVault.sol";
import {BerryJuicerFactory} from "../contracts/BerryJuicerFactory.sol";

/// @notice Deploys the vault implementation and the factory that clones it per position.
/// @dev The proprietary strategy and the inference router are deployed separately (out of this
///      repo) and passed in via environment variables. The operator is the master-handler wallet
///      (e.g. a policy-scoped Privy server wallet).
///
///      Usage:
///        forge script script/Deploy.s.sol \
///          --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --verify
contract Deploy is Script {
    function run() external returns (BerryJuicerFactory factory, BerryJuicerVault implementation) {
        address strategy = vm.envAddress("JUICER_STRATEGY");
        address inferenceRouter = vm.envAddress("INFERENCE_ROUTER");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        address operator = vm.envAddress("OPERATOR");
        uint256 creatorShareBps = vm.envOr("CREATOR_SHARE_BPS", uint256(8000)); // default 80%

        vm.startBroadcast();
        implementation = new BerryJuicerVault();
        factory = new BerryJuicerFactory(
            address(implementation), strategy, inferenceRouter, feeRecipient, operator, creatorShareBps
        );
        vm.stopBroadcast();
    }
}
