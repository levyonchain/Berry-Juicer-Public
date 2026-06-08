// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IJuicerStrategy} from "../../contracts/interfaces/IJuicerStrategy.sol";
import {IInferenceRouter} from "../../contracts/interfaces/IInferenceRouter.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice A trivial strategy satisfying {IJuicerStrategy} for testing only. NOT the real Berry
///         Juicer strategy. It is a pure bookkeeper: custody stays in the calling vault. Fees are
///         simulated by minting quote directly into the vault that opened the position, modelling
///         that a position's funds live in its own vault, never in a shared pot.
contract ReferenceStrategy is IJuicerStrategy {
    address public immutable quote;
    mapping(bytes32 => uint256) public principalOf;
    mapping(bytes32 => uint256) public accruedOf;
    mapping(bytes32 => address) public vaultOf;
    uint256 internal nonce;

    constructor(address quote_) {
        quote = quote_;
    }

    function open(address token, uint256 amount) external returns (bytes32 key) {
        key = keccak256(abi.encodePacked(msg.sender, token, amount, nonce++));
        principalOf[key] = amount;
        vaultOf[key] = msg.sender; // the vault keeps custody of the principal token
    }

    /// @dev Test helper: simulate fee accrual by minting quote into the owning vault.
    function simulateFees(bytes32 key, uint256 amount) external {
        accruedOf[key] += amount;
        MockERC20(quote).mint(vaultOf[key], amount);
    }

    function collect(bytes32 key) external returns (uint256 quoteAmount) {
        quoteAmount = accruedOf[key]; // funds already sit in the vault
        accruedOf[key] = 0;
    }

    function close(bytes32 key) external returns (uint256 tokenAmount, uint256 quoteAmount) {
        tokenAmount = principalOf[key]; // principal token already sits in the vault
        principalOf[key] = 0;
        quoteAmount = 0;
    }

    function accrued(bytes32 key) external view returns (uint256) {
        return accruedOf[key];
    }

    function quoteAsset() external view returns (address) {
        return quote;
    }
}

/// @notice A no-op inference router for tests. Records credited value (off-chain fulfillment is
///         modelled as a simple running tally here).
contract ReferenceInferenceRouter is IInferenceRouter {
    bool public active = true;
    mapping(address => uint256) public creditsOf;

    function setActive(bool a) external {
        active = a;
    }

    function creditInference(address recipient, address quoteAsset, uint256 quoteValue) external {
        creditsOf[recipient] += quoteValue;
        emit InferenceCredited(recipient, quoteAsset, quoteValue);
    }

    function isActive() external view returns (bool) {
        return active;
    }
}
