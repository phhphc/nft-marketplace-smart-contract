// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {MarketplaceEvents} from "../interfaces/MarketplaceEvents.sol";
import {MarketplaceBase} from "./MarketplaceBase.sol";
import {OneWord} from "./MarketplaceConstants.sol";

contract CounterManager is MarketplaceBase, MarketplaceEvents {
    // Only orders signed using an offerer's current counter are fulfillable.
    mapping(address => uint256) private _counters;

    /**
     * @dev Internal function to cancel all orders from a given offerer in bulk
     *      by incrementing a counter by a large, quasi-random interval. Note
     *      that only the offerer may increment the counter. Note that the
     *      counter is incremented by a large, quasi-random interval, which
     *      makes it infeasible to "activate" signed orders by incrementing the
     *      counter.  This activation functionality can be achieved instead with
     *      restricted orders or contract orders.
     *
     * @return newCounter The new counter.
     */
    function _incrementCounter() internal returns (uint256 newCounter) {
        // Utilize assembly to access counters storage mapping directly. Skip
        // overflow check as counter cannot be incremented that far.
        assembly {
            // Use second half of previous block hash as a quasi-random number.
            let quasiRandomNumber := shr(0x80, blockhash(sub(number(), 1)))

            // Write the caller to scratch space.
            mstore(0, caller())

            // Write the storage slot for _counters to scratch space.
            mstore(OneWord, _counters.slot)

            // Derive the storage pointer for the counter value.
            let storagePointer := keccak256(0, 0x40)

            // Derive new counter value using random number and original value.
            newCounter := add(quasiRandomNumber, sload(storagePointer))

            // Store the updated counter value.
            sstore(storagePointer, newCounter)
        }

        // Emit an event containing the new counter.
        emit CounterIncremented(newCounter, msg.sender);
    }

    /**
     * @dev Internal view function to retrieve the current counter for a given
     *      offerer.
     *
     * @param offerer The offerer in question.
     *
     * @return currentCounter The current counter.
     */
    function _getCounter(address offerer) internal view returns (uint256 currentCounter) {
        // Return the counter for the supplied offerer.
        currentCounter = _counters[offerer];
    }
}
