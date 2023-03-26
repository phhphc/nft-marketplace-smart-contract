// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./lib/Trader.sol";

contract Marketplace is Trader {
    /**
     * @dev Internal pure function to retrieve and return the name of this
     *      contract.
     *
     * @return The name of this contract.
     */
    function _name() internal pure override returns (string memory) {
        // Return the name of the contract.
        assembly {
            mstore(0x20, 0x20)
            mstore(0x4b, 0x0b4d61726b6574706c616365)
            return(0x20, 0x60)
        }
    }

    /**
     * @dev Internal pure function to retrieve the name of this contract as a
     *      string that will be used to derive the name hash in the constructor.
     *
     * @return The name of this contract as a string.
     */
    function _nameString() internal pure override returns (string memory) {
        // Return the name of the contract.
        return "Marketplace";
    }

    fallback() external payable {
        revert("error");
    }

    receive() external payable {
        revert("error");
    }
}
