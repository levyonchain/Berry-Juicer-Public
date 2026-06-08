// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IJuicerStrategy} from "../../contracts/interfaces/IJuicerStrategy.sol";
import {IInferenceRouter} from "../../contracts/interfaces/IInferenceRouter.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice A deliberately trivial strategy that satisfies {IJuicerStrategy} for testing only.
/// @dev This is NOT the Berry Juicer position strategy. The real strategy (single-sided V4
///      position selection, ranging, and rebalancing) is proprietary and not in this repo.
///      This stub simply records deposits and lets a test mint synthetic "fees" so the open
///      vault and periphery can be exercised end to end.
contract ReferenceStrategy is IJuicerStrategy {
    address public immutable quote;
    mapping(bytes32 => uint256) public depositOf;
    mapping(bytes32 => address) public tokenOf;
    mapping(bytes32 => uint256) public feesOf;
    uint256 internal nonce;

    constructor(address quote_) {
        quote = quote_;
    }

    function open(address token, uint256 amount) external returns (bytes32 key) {
        key = keccak256(abi.encodePacked(msg.sender, token, amount, nonce++));
        depositOf[key] = amount;
        tokenOf[key] = token;
    }

    /// @dev Test helper: simulate fee accrual for a position.
    function simulateFees(bytes32 key, uint256 amount) external {
        feesOf[key] += amount;
        MockERC20(quote).mint(address(this), amount);
    }

    function collect(bytes32 key) external returns (uint256 quoteAmount) {
        quoteAmount = feesOf[key];
        feesOf[key] = 0;
        if (quoteAmount > 0) MockERC20(quote).transfer(msg.sender, quoteAmount);
    }

    function close(bytes32 key) external returns (uint256 tokenAmount, uint256 quoteAmount) {
        tokenAmount = depositOf[key];
        depositOf[key] = 0;
        quoteAmount = feesOf[key];
        feesOf[key] = 0;
        // return the deployed principal (and any uncollected quote) to the caller (the vault)
        if (tokenAmount > 0) MockERC20(tokenOf[key]).transfer(msg.sender, tokenAmount);
        if (quoteAmount > 0) MockERC20(quote).transfer(msg.sender, quoteAmount);
    }

    function accrued(bytes32 key) external view returns (uint256) {
        return feesOf[key];
    }

    function quoteAsset() external view returns (address) {
        return quote;
    }
}

/// @notice A no-op inference router for tests: 1 quote unit -> 1 credit.
contract ReferenceInferenceRouter is IInferenceRouter {
    bool public active = true;
    mapping(address => uint256) public creditsOf;

    function setActive(bool a) external {
        active = a;
    }

    function fulfill(address recipient, address, uint256 quoteAmount) external returns (uint256 credits) {
        credits = quoteAmount; // 1:1 for tests
        creditsOf[recipient] += credits;
        emit InferenceFulfilled(recipient, quoteAmount, credits);
    }

    function quoteCredits(address, uint256 quoteAmount) external pure returns (uint256) {
        return quoteAmount;
    }

    function isActive() external view returns (bool) {
        return active;
    }
}
