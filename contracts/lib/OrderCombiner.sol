// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    Order,
    OrderType,
    OrderParameters,
    OfferItem,
    ConsiderationItem,
    ReceivedItem,
    ItemType,
    SpentItem
} from "./TraderStructs.sol";
import {Executor} from "./Executor.sol";
import {OrderValidator} from "./OrderValidator.sol";
import {AmountDeriver} from "./AmountDeriver.sol";

import {
    ReceivedItem_amount_offset,
    ReceivedItem_recipient_offset,
    ConsiderationItem_recipient_offset,
    Order_head_size,
    Order_signature_offset
} from "./ConsiderationConstants.sol";

import {
    _revertInvalidNativeOfferItem,
    _revertInsufficientNativeTokensSupplied
} from "./ConsiderationErrors.sol";

import {
    CalldataStart,
    malloc,
    CalldataPointer,
    MemoryPointer
} from "../helpers/PointerLibraries.sol";

import {console} from "hardhat/console.sol";

contract OrderCombiner is Executor, OrderValidator, AmountDeriver {
    /**
     * @dev Internal function to validate an order and update its status, adjust
     *      prices based on current time and transfer relevant tokens.
     *
     * @param order               The order to fulfill.
     * @param recipient           The intended recipient for all received items.
     *
     * @return A boolean indicating whether the order has been fulfilled.
     */
    function _validateAndFulfillOrder(
        Order memory order,
        address recipient
    ) internal returns (bool) {
        console.log("offerer:", order.parameters.offerer);
        console.log("zone:", order.parameters.zone);
        console.log("consideration recipient:", order.parameters.consideration[0].recipient);

        // Validate order, update status, and determine fraction to fill.
        bytes32 orderHash = _validateOrderAndUpdateStatus(order, true);

        // // Create an array with length 1 containing the order.
        // order[] memory orders = new order[](1);

        // // Populate the order as the first and only element of the new array.
        // orders[0] = order;

        // // Apply criteria resolvers using generated orders and details arrays.
        // _applyCriteriaResolvers(orders, criteriaResolvers);

        // // Retrieve the order parameters after applying criteria resolvers.
        // OrderParameters memory orderParameters = orders[0].parameters;

        OrderParameters memory orderParameters = order.parameters;

        // Perform each item transfer with the appropriate amount.
        _transferEach(orderParameters, recipient);

        // Declare empty bytes32 array and populate with the order hash.
        bytes32[] memory orderHashes = new bytes32[](1);
        orderHashes[0] = orderHash;

        // Ensure restricted orders have a valid submitter or pass a zone check.
        // _assertRestrictedorderValidity(
        //     orders[0],
        //     orderHashes,
        //     orderHash
        // );

        // Emit an event signifying that the order has been fulfilled.
        _emitOrderFulfilledEvent(
            orderHash,
            orderParameters.offerer,
            orderParameters.zone,
            recipient,
            orderParameters.offer,
            orderParameters.consideration
        );

        // Clear the reentrancy guard.
        // _clearReentrancyGuard();

        return true;
    }

    /**
     * @dev Internal function to transfer each item contained in a given single
     *      order fulfillment after applying a respective fraction to the amount
     *      being transferred.
     *
     * @param orderParameters     The parameters for the fulfilled order.
     * @param recipient           The intended recipient for all received items.
     */
    function _transferEach(OrderParameters memory orderParameters, address recipient) internal {
        // Read start time & end time from order parameters and place on stack.
        uint256 startTime = orderParameters.startTime;
        uint256 endTime = orderParameters.endTime;

        // Initialize an accumulator array. From this point forward, no new
        // memory regions can be safely allocated until the accumulator is no
        // longer being utilized, as the accumulator operates in an open-ended
        // fashion from this memory pointer; existing memory may still be
        // accessed and modified, however.
        // bytes memory accumulator = new bytes(AccumulatorDisarmed);

        // As of solidity 0.6.0, inline assembly cannot directly access function
        // definitions, but can still access locally scoped function variables.
        // This means that a local variable to reference the internal function
        // definition (using the same type), along with a local variable with
        // the desired type, must first be created. Then, the original function
        // pointer can be recast to the desired type.

        /**
         * Repurpose existing OfferItem memory regions on the offer array for
         * the order by overriding the _transfer function pointer to accept a
         * modified OfferItem argument in place of the usual ReceivedItem:
         *
         *   ========= OfferItem ==========   ====== ReceivedItem ======
         *   ItemType itemType; ------------> ItemType itemType;
         *   address token; ----------------> address token;
         *   uint256 identifierOrCriteria; -> uint256 identifier;
         *   uint256 startAmount; ----------> uint256 amount;
         *   uint256 endAmount; ------------> address recipient;
         */

        // Declare a nested scope to minimize stack depth.
        unchecked {
            // Read offer array length from memory and place on stack.
            uint256 totalOfferItems = orderParameters.offer.length;

            // Create a variable to indicate whether the order has any
            // native offer items
            uint256 anyNativeItems;

            // Iterate over each offer on the order.
            // Skip overflow check as for loop is indexed starting at zero.
            for (uint256 i = 0; i < totalOfferItems; ++i) {
                // Retrieve the offer item.
                OfferItem memory offerItem = orderParameters.offer[i];

                // Offer items for the native token can not be received outside
                // of a match order function except as part of a contract order.
                {
                    ItemType itemType = offerItem.itemType;
                    assembly {
                        anyNativeItems := or(anyNativeItems, iszero(itemType))
                    }
                }

                // Declare an additional nested scope to minimize stack depth.
                {
                    // Apply fill fraction to get offer item amount to transfer.
                    uint256 amount = _applyFraction(
                        offerItem.startAmount,
                        offerItem.endAmount,
                        // numerator,
                        // denominator,
                        startTime,
                        endTime,
                        false
                    );

                    // Utilize assembly to set overloaded offerItem arguments.
                    assembly {
                        // Write new fractional amount to startAmount as amount.
                        mstore(add(offerItem, ReceivedItem_amount_offset), amount)

                        // Write recipient to endAmount.
                        mstore(add(offerItem, ReceivedItem_recipient_offset), recipient)
                    }
                }

                // Transfer the item from the offerer to the recipient.
                _toOfferItemInput(_transfer)(offerItem, orderParameters.offerer);
            }

            // If a non-contract order has native offer items, throw with an
            // `InvalidNativeOfferItem` custom error.
            {
                OrderType orderType = orderParameters.orderType;
                uint256 invalidNativeOfferItem;
                assembly {
                    invalidNativeOfferItem := and(
                        // Note that this check requires that there are no order
                        // types beyond the current set (0-4).  It will need to
                        // be modified if more order types are added.
                        lt(orderType, 4),
                        anyNativeItems
                    )
                }
                if (invalidNativeOfferItem != 0) {
                    _revertInvalidNativeOfferItem();
                }
            }
        }

        // Declare a variable for the available native token balance.
        uint256 nativeTokenBalance;

        /**
         * Repurpose existing ConsiderationItem memory regions on the
         * consideration array for the order by overriding the _transfer
         * function pointer to accept a modified ConsiderationItem argument in
         * place of the usual ReceivedItem:
         *
         *   ====== ConsiderationItem =====   ====== ReceivedItem ======
         *   ItemType itemType; ------------> ItemType itemType;
         *   address token; ----------------> address token;
         *   uint256 identifierOrCriteria;--> uint256 identifier;
         *   uint256 startAmount; ----------> uint256 amount;
         *   uint256 endAmount;        /----> address recipient;
         *   address recipient; ------/
         */

        // Declare a nested scope to minimize stack depth.
        unchecked {
            // Read consideration array length from memory and place on stack.
            uint256 totalConsiderationItems = orderParameters.consideration.length;

            // Iterate over each consideration item on the order.
            // Skip overflow check as for loop is indexed starting at zero.
            for (uint256 i = 0; i < totalConsiderationItems; ++i) {
                // Retrieve the consideration item.
                ConsiderationItem memory considerationItem = (orderParameters.consideration[i]);

                // Apply fraction & derive considerationItem amount to transfer.
                uint256 amount = _applyFraction(
                    considerationItem.startAmount,
                    considerationItem.endAmount,
                    // numerator,
                    // denominator,
                    startTime,
                    endTime,
                    true
                );

                // Use assembly to set overloaded considerationItem arguments.
                assembly {
                    // Write derived fractional amount to startAmount as amount.
                    mstore(add(considerationItem, ReceivedItem_amount_offset), amount)

                    // Write original recipient to endAmount as recipient.
                    mstore(
                        add(considerationItem, ReceivedItem_recipient_offset),
                        mload(add(considerationItem, ConsiderationItem_recipient_offset))
                    )
                }

                // Reduce available value if offer spent ETH or a native token.
                if (considerationItem.itemType == ItemType.NATIVE) {
                    // Get the current available balance of native tokens.
                    assembly {
                        nativeTokenBalance := selfbalance()
                    }

                    // Ensure that sufficient native tokens are still available.
                    if (amount > nativeTokenBalance) {
                        _revertInsufficientNativeTokensSupplied();
                    }
                }

                // Transfer item from caller to recipient specified by the item.
                _toConsiderationItemInput(_transfer)(considerationItem, msg.sender);
            }
        }

        // Determine whether any native token balance remains.
        assembly {
            nativeTokenBalance := selfbalance()
        }

        // Return any remaining native token balance to the caller.
        if (nativeTokenBalance != 0) {
            _transferNativeTokens(payable(msg.sender), nativeTokenBalance);
        }
    }

    /**
     * @dev Internal function to emit an OrderFulfilled event. OfferItems are
     *      translated into SpentItems and ConsiderationItems are translated
     *      into ReceivedItems.
     *
     * @param orderHash     The order hash.
     * @param offerer       The offerer for the order.
     * @param zone          The zone for the order.
     * @param recipient     The recipient of the order, or the null address if
     *                      the order was fulfilled via order matching.
     * @param offer         The offer items for the order.
     * @param consideration The consideration items for the order.
     */
    function _emitOrderFulfilledEvent(
        bytes32 orderHash,
        address offerer,
        address zone,
        address recipient,
        OfferItem[] memory offer,
        ConsiderationItem[] memory consideration
    ) internal {
        // Cast already-modified offer memory region as spent items.
        SpentItem[] memory spentItems;
        assembly {
            spentItems := offer
        }

        // Cast already-modified consideration memory region as received items.
        ReceivedItem[] memory receivedItems;
        assembly {
            receivedItems := consideration
        }

        // Emit an event signifying that the order has been fulfilled.
        emit OrderFulfilled(orderHash, offerer, zone, recipient, spentItems, receivedItems);
    }

    /**
     * @dev Converts a function taking a calldata pointer and returning a memory
     *      pointer into a function taking that calldata pointer and returning
     *      an AdvancedOrder type.
     *
     * @param inFn The input function, taking an arbitrary calldata pointer and
     *             returning an arbitrary memory pointer.
     *
     * @return outFn The output function, taking an arbitrary calldata pointer
     *               and returning an AdvancedOrder type.
     */
    function _toOrderReturnType(
        function(CalldataPointer) internal pure returns (MemoryPointer) inFn
    ) internal pure returns (function(CalldataPointer) internal pure returns (Order memory) outFn) {
        assembly {
            outFn := inFn
        }
    }
}
