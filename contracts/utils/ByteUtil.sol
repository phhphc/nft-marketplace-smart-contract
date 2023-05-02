// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

function toByte32(address a) pure returns (bytes32 b) {
    b = bytes32(uint256(uint160(a)));
}
