// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Side, ItemType, OrderType} from "./TraderEnums.sol";
import {
    Order,
    OrderType,
    OrderParameters,
    OfferItem,
    ConsiderationItem,
    ReceivedItem,
    ItemType,
    SpentItem,
    FulfillmentComponent,
    Execution
} from "./TraderStructs.sol";
import {Executor} from "./Executor.sol";
import {OrderValidator} from "./OrderValidator.sol";
import {AmountDeriver} from "./AmountDeriver.sol";
import {FulfillmentApplier} from "./FulfillmentApplier.sol";

import {
    ReceivedItem_amount_offset,
    ReceivedItem_recipient_offset,
    ConsiderationItem_recipient_offset,
    Order_head_size,
    Order_signature_offset,
    OneWordShift,
    OneWord,
    NonMatchSelector_InvalidErrorValue,
    NonMatchSelector_MagicMask
} from "./ConsiderationConstants.sol";

import {
    _revertInvalidNativeOfferItem,
    _revertInsufficientNativeTokensSupplied,
    _revertNoSpecifiedOrdersAvailable,
    _revertConsiderationNotMet
} from "./ConsiderationErrors.sol";

import {
    CalldataStart,
    malloc,
    CalldataPointer,
    MemoryPointer
} from "../helpers/PointerLibraries.sol";

import {console} from "hardhat/console.sol";

import {ZoneInteraction} from "./ZoneInteraction.sol";

contract OrderCombiner is
    Executor,
    OrderValidator,
    AmountDeriver,
    FulfillmentApplier,
    ZoneInteraction
{
    /**
     * @notice Internal function to attempt to fill a group of orders, fully or
     *         partially, with an arbitrary number of items for offer and
     *         consideration per order alongside criteria resolvers containing
     *         specific token identifiers and associated proofs. Any order that
     *         is not currently active, has already been fully filled, or has
     *         been cancelled will be omitted. Remaining offer and consideration
     *         items will then be aggregated where possible as indicated by the
     *         supplied offer and consideration component arrays and aggregated
     *         items will be transferred to the fulfiller or to each intended
     *         recipient, respectively. Note that a failing item transfer or an
     *         issue with order formatting will cause the entire batch to fail.
     *
     * @param orders            The orders to fulfill along with the
     *                                  fraction of those orders to attempt to
     *                                  fill. Note that both the offerer and the
     *                                  fulfiller must first approve this
     *                                  contract (or a conduit if indicated by
     *                                  the order) to transfer any relevant
     *                                  tokens on their behalf and that
     *                                  contracts must implement
     *                                  `onERC1155Received` in order to receive
     *                                  ERC1155 tokens as consideration. Also
     *                                  note that all offer and consideration
     *                                  components must have no remainder after
     *                                  multiplication of the respective amount
     *                                  with the supplied fraction for an
     *                                  order's partial fill amount to be
     *                                  considered valid.
     * @param offerFulfillments         An array of FulfillmentComponent arrays
     *                                  indicating which offer items to attempt
     *                                  to aggregate when preparing executions.
     * @param considerationFulfillments An array of FulfillmentComponent arrays
     *                                  indicating which consideration items to
     *                                  attempt to aggregate when preparing
     *                                  executions.
     * @param recipient                 The intended recipient for all received
     *                                  items.
     * @param maximumFulfilled          The maximum number of orders to fulfill.
     *
     * @return availableOrders An array of booleans indicating if each order
     *                         with an index corresponding to the index of the
     *                         returned boolean was fulfillable or not.
     * @return executions      An array of elements indicating the sequence of
     *                         transfers performed as part of matching the given
     *                         orders.
     */
    function _fulfillAvailableAdvancedOrders(
        Order[] memory orders,
        FulfillmentComponent[][] memory offerFulfillments,
        FulfillmentComponent[][] memory considerationFulfillments,
        address recipient,
        uint256 maximumFulfilled
    ) internal returns (bool[] memory /* availableOrders */, Execution[] memory /* executions */) {
        // Validate orders, apply amounts, & determine if they utilize conduits.
        bytes32[] memory orderHashes = _validateOrdersAndPrepareToFulfill(
            orders,
            false, // Signifies that invalid orders should NOT revert.
            maximumFulfilled,
            recipient
        );

        // Aggregate used offer and consideration items and execute transfers.
        return
            _executeAvailableFulfillments(
                orders,
                offerFulfillments,
                considerationFulfillments,
                recipient,
                orderHashes
            );
    }

    /**
     * @dev Internal function to validate a group of orders, update their
     *      statuses, reduce amounts by their previously filled fractions, apply
     *      criteria resolvers, and emit OrderFulfilled events. Note that this
     *      function needs to be called before
     *      _aggregateValidFulfillmentConsiderationItems to set the memory
     *      layout that _aggregateValidFulfillmentConsiderationItems depends on.
     *
     * @param advancedOrders    The advanced orders to validate and reduce by
     *                          their previously filled amounts.
     * @param revertOnInvalid   A boolean indicating whether to revert on any
     *                          order being invalid; setting this to false will
     *                          instead cause the invalid order to be skipped.
     * @param maximumFulfilled  The maximum number of orders to fulfill.
     * @param recipient         The intended recipient for all items that do not
     *                          already have a designated recipient and are not
     *                          already used as part of a provided fulfillment.
     *
     * @return orderHashes      The hashes of the orders being fulfilled.
     */
    function _validateOrdersAndPrepareToFulfill(
        Order[] memory advancedOrders,
        bool revertOnInvalid,
        uint256 maximumFulfilled,
        address recipient
    ) internal returns (bytes32[] memory orderHashes) {
        // Ensure this function cannot be triggered during a reentrant call.
        //_setReentrancyGuard(true); // Native tokens accepted during execution.

        // Declare an error buffer indicating status of any native offer items.
        // Native tokens may only be provided as part of contract orders or when
        // fulfilling via matchOrders or matchAdvancedOrders; if bits indicating
        // these conditions are not met have been set, throw.
        uint256 invalidNativeOfferItemErrorBuffer;

        // Use assembly to set the value for the second bit of the error buffer.
        assembly {
            /**
             * Use the 231st bit of the error buffer to indicate whether the
             * current function is not matchAdvancedOrders or matchOrders.
             *
             * sig                                func
             * -----------------------------------------------------------------
             * 1010100000010111010001000 0 000100 matchOrders
             * 1111001011010001001010110 0 010010 matchAdvancedOrders
             * 1110110110011000101001010 1 110100 fulfillAvailableOrders
             * 1000011100100000000110110 1 000001 fulfillAvailableAdvancedOrders
             *                           ^ 7th bit
             */
            invalidNativeOfferItemErrorBuffer := and(NonMatchSelector_MagicMask, calldataload(0))
        }

        // Declare variables for later use.
        Order memory advancedOrder;
        uint256 terminalMemoryOffset;

        unchecked {
            // Read length of orders array and place on the stack.
            uint256 totalOrders = advancedOrders.length;

            // Track the order hash for each order being fulfilled.
            orderHashes = new bytes32[](totalOrders);

            // Determine the memory offset to terminate on during loops.
            terminalMemoryOffset = (totalOrders + 1) << OneWordShift;
        }

        // Skip overflow checks as all for loops are indexed starting at zero.
        unchecked {
            // Declare inner variables.
            OfferItem[] memory offer;
            ConsiderationItem[] memory consideration;

            // Iterate over each order.
            for (uint256 i = OneWord; i < terminalMemoryOffset; i += OneWord) {
                // Retrieve order using assembly to bypass out-of-range check.
                assembly {
                    advancedOrder := mload(add(advancedOrders, i))
                }

                // Determine if max number orders have already been fulfilled.
                if (maximumFulfilled == 0) {
                    // Mark fill fraction as zero as the order will not be used.
                    // advancedOrder.numerator = 0;

                    // Continue iterating through the remaining orders.
                    continue;
                }

                // Validate it, update status, and determine fraction to fill.
                bytes32 orderHash = _validateOrderAndUpdateStatus(advancedOrder, revertOnInvalid);

                // Do not track hash or adjust prices if order is not fulfilled.
                if (orderHash == bytes32(0)) {
                    // Mark fill fraction as zero if the order is not fulfilled.
                    // advancedOrder.numerator = 0;

                    // Continue iterating through the remaining orders.
                    continue;
                }

                // Otherwise, track the order hash in question.
                assembly {
                    mstore(add(orderHashes, i), orderHash)
                }

                // Decrement the number of fulfilled orders.
                // Skip underflow check as the condition before
                // implies that maximumFulfilled > 0.
                --maximumFulfilled;

                // Place the start time for the order on the stack.
                uint256 startTime = advancedOrder.parameters.startTime;

                // Place the end time for the order on the stack.
                uint256 endTime = advancedOrder.parameters.endTime;

                // Retrieve array of offer items for the order in question.
                offer = advancedOrder.parameters.offer;

                // Read length of offer array and place on the stack.
                uint256 totalOfferItems = offer.length;

                {
                    // Create a variable indicating if the order is not a
                    // contract order. Cache in scratch space to avoid stack
                    // depth errors.
                    OrderType orderType = advancedOrder.parameters.orderType;
                    assembly {
                        // Note that this check requires that there are no order
                        // types beyond the current set (0-4).  It will need to
                        // be modified if more order types are added.
                        let isNonContract := lt(orderType, 4)
                        mstore(0, isNonContract)
                    }
                }

                // Iterate over each offer item on the order.
                for (uint256 j = 0; j < totalOfferItems; ++j) {
                    // Retrieve the offer item.
                    OfferItem memory offerItem = offer[j];

                    {
                        assembly {
                            // If the offer item is for the native token and the
                            // order type is not a contract order type, set the
                            // first bit of the error buffer to true.
                            invalidNativeOfferItemErrorBuffer := or(
                                invalidNativeOfferItemErrorBuffer,
                                lt(mload(offerItem), mload(0))
                            )
                        }
                    }

                    // // Apply order fill fraction to offer item end amount.
                    // uint256 endAmount = _getFraction(
                    //     numerator,
                    //     denominator,
                    //     offerItem.endAmount
                    // );

                    // Reuse same fraction if start and end amounts are equal.
                    // if (offerItem.startAmount == offerItem.endAmount) {
                    //     // Apply derived amount to both start and end amount.
                    //     offerItem.startAmount = endAmount;
                    // } else {
                    //     // Apply order fill fraction to offer item start amount.
                    //     offerItem.startAmount = _getFraction(
                    //         numerator,
                    //         denominator,
                    //         offerItem.startAmount
                    //     );
                    // }

                    // Adjust offer amount using current time; round down.
                    uint256 currentAmount = _locateCurrentAmount(
                        offerItem.startAmount,
                        offerItem.endAmount,
                        startTime,
                        endTime,
                        false // round down
                    );

                    // Update amounts in memory to match the current amount.
                    // Note that the end amount is used to track spent amounts.
                    offerItem.startAmount = currentAmount;
                    offerItem.endAmount = currentAmount;
                }

                // Retrieve array of consideration items for order in question.
                consideration = (advancedOrder.parameters.consideration);

                // Read length of consideration array and place on the stack.
                uint256 totalConsiderationItems = consideration.length;

                // Iterate over each consideration item on the order.
                for (uint256 j = 0; j < totalConsiderationItems; ++j) {
                    // Retrieve the consideration item.
                    ConsiderationItem memory considerationItem = (consideration[j]);

                    // Apply fraction to consideration item end amount.
                    // uint256 endAmount = _getFraction(
                    //     numerator,
                    //     denominator,
                    //     considerationItem.endAmount
                    // );

                    // Reuse same fraction if start and end amounts are equal.
                    // if (
                    //     considerationItem.startAmount ==
                    //     considerationItem.endAmount
                    // ) {
                    //     // Apply derived amount to both start and end amount.
                    //     considerationItem.startAmount = endAmount;
                    // } else {
                    //     // Apply fraction to consideration item start amount.
                    //     considerationItem.startAmount = _getFraction(
                    //         numerator,
                    //         denominator,
                    //         considerationItem.startAmount
                    //     );
                    // }

                    // Adjust consideration amount using current time; round up.
                    uint256 currentAmount = (
                        _locateCurrentAmount(
                            considerationItem.startAmount,
                            considerationItem.endAmount,
                            startTime,
                            endTime,
                            true // round up
                        )
                    );

                    considerationItem.startAmount = currentAmount;

                    // Utilize assembly to manually "shift" the recipient value,
                    // then to copy the start amount to the recipient.
                    // Note that this sets up the memory layout that is
                    // subsequently relied upon by
                    // _aggregateValidFulfillmentConsiderationItems.
                    assembly {
                        // Derive the pointer to the recipient using the item
                        // pointer along with the offset to the recipient.
                        let considerationItemRecipientPtr := add(
                            considerationItem,
                            ConsiderationItem_recipient_offset // recipient
                        )

                        // Write recipient to endAmount, as endAmount is not
                        // used from this point on and can be repurposed to fit
                        // the layout of a ReceivedItem.
                        mstore(
                            add(
                                considerationItem,
                                ReceivedItem_recipient_offset // old endAmount
                            ),
                            mload(considerationItemRecipientPtr)
                        )

                        // Write startAmount to recipient, as recipient is not
                        // used from this point on and can be repurposed to
                        // track received amounts.
                        mstore(considerationItemRecipientPtr, currentAmount)
                    }
                }
            }
        }

        // If the first bit is set, a native offer item was encountered on an
        // order that is not a contract order. If the 231st bit is set in the
        // error buffer, the current function is not matchOrders or
        // matchAdvancedOrders. If the value is 1 + (1 << 230), then both the
        // 1st and 231st bits were set; in that case, revert with an error.
        if (invalidNativeOfferItemErrorBuffer == NonMatchSelector_InvalidErrorValue) {
            _revertInvalidNativeOfferItem();
        }

        // Apply criteria resolvers to each order as applicable.
        // _applyCriteriaResolvers(advancedOrders, criteriaResolvers);

        // Emit an event for each order signifying that it has been fulfilled.
        // Skip overflow checks as all for loops are indexed starting at zero.
        unchecked {
            bytes32 orderHash;

            // Iterate over each order.
            for (uint256 i = OneWord; i < terminalMemoryOffset; i += OneWord) {
                assembly {
                    orderHash := mload(add(orderHashes, i))
                }

                // Do not emit an event if no order hash is present.
                if (orderHash == bytes32(0)) {
                    continue;
                }

                // Retrieve order using assembly to bypass out-of-range check.
                assembly {
                    advancedOrder := mload(add(advancedOrders, i))
                }

                // Retrieve parameters for the order in question.
                OrderParameters memory orderParameters = (advancedOrder.parameters);

                // Emit an OrderFulfilled event.
                _emitOrderFulfilledEvent(
                    orderHash,
                    orderParameters.offerer,
                    orderParameters.zone,
                    recipient,
                    orderParameters.offer,
                    orderParameters.consideration
                );
            }
        }
    }

    /**
     * @dev Internal function to fulfill a group of validated orders, fully or
     *      partially, with an arbitrary number of items for offer and
     *      consideration per order and to execute transfers. Any order that is
     *      not currently active, has already been fully filled, or has been
     *      cancelled will be omitted. Remaining offer and consideration items
     *      will then be aggregated where possible as indicated by the supplied
     *      offer and consideration component arrays and aggregated items will
     *      be transferred to the fulfiller or to each intended recipient,
     *      respectively. Note that a failing item transfer or an issue with
     *      order formatting will cause the entire batch to fail.
     *
     * @param advancedOrders            The orders to fulfill along with the
     *                                  fraction of those orders to attempt to
     *                                  fill. Note that both the offerer and the
     *                                  fulfiller must first approve this
     *                                  contract (or the conduit if indicated by
     *                                  the order) to transfer any relevant
     *                                  tokens on their behalf and that
     *                                  contracts must implement
     *                                  `onERC1155Received` in order to receive
     *                                  ERC1155 tokens as consideration. Also
     *                                  note that all offer and consideration
     *                                  components must have no remainder after
     *                                  multiplication of the respective amount
     *                                  with the supplied fraction for an
     *                                  order's partial fill amount to be
     *                                  considered valid.
     * @param offerFulfillments         An array of FulfillmentComponent arrays
     *                                  indicating which offer items to attempt
     *                                  to aggregate when preparing executions.
     * @param considerationFulfillments An array of FulfillmentComponent arrays
     *                                  indicating which consideration items to
     *                                  attempt to aggregate when preparing
     *                                  executions.
     * @param recipient                 The intended recipient for all items
     *                                  that do not already have a designated
     *                                  recipient and are not already used as
     *                                  part of a provided fulfillment.
     * @param orderHashes               An array of order hashes for each order.
     *
     * @return availableOrders An array of booleans indicating if each order
     *                         with an index corresponding to the index of the
     *                         returned boolean was fulfillable or not.
     * @return executions      An array of elements indicating the sequence of
     *                         transfers performed as part of matching the given
     *                         orders.
     */
    function _executeAvailableFulfillments(
        Order[] memory advancedOrders,
        FulfillmentComponent[][] memory offerFulfillments,
        FulfillmentComponent[][] memory considerationFulfillments,
        address recipient,
        bytes32[] memory orderHashes
    ) internal returns (bool[] memory availableOrders, Execution[] memory executions) {
        // Retrieve length of offer fulfillments array and place on the stack.
        uint256 totalOfferFulfillments = offerFulfillments.length;

        // Retrieve length of consideration fulfillments array & place on stack.
        uint256 totalConsiderationFulfillments = (considerationFulfillments.length);

        // Allocate an execution for each offer and consideration fulfillment.
        executions = new Execution[](totalOfferFulfillments + totalConsiderationFulfillments);

        // Skip overflow checks as all for loops are indexed starting at zero.
        unchecked {
            // Track number of filtered executions.
            uint256 totalFilteredExecutions = 0;

            // Iterate over each offer fulfillment.
            for (uint256 i = 0; i < totalOfferFulfillments; ) {
                // Derive aggregated execution corresponding with fulfillment.
                Execution memory execution = _aggregateAvailable(
                    advancedOrders,
                    Side.OFFER,
                    offerFulfillments[i],
                    bytes32(0),
                    recipient
                );

                // If offerer and recipient on the execution are the same...
                if (_unmaskedAddressComparison(execution.item.recipient, execution.offerer)) {
                    // Increment total filtered executions.
                    ++totalFilteredExecutions;
                } else {
                    // Otherwise, assign the execution to the executions array.
                    executions[i - totalFilteredExecutions] = execution;
                }

                // Increment iterator.
                ++i;
            }

            // Iterate over each consideration fulfillment.
            for (uint256 i = 0; i < totalConsiderationFulfillments; ) {
                // Derive aggregated execution corresponding with fulfillment.
                Execution memory execution = _aggregateAvailable(
                    advancedOrders,
                    Side.CONSIDERATION,
                    considerationFulfillments[i],
                    bytes32(0),
                    address(0) // unused
                );

                // If offerer and recipient on the execution are the same...
                if (_unmaskedAddressComparison(execution.item.recipient, execution.offerer)) {
                    // Increment total filtered executions.
                    ++totalFilteredExecutions;
                } else {
                    // Otherwise, assign the execution to the executions array.
                    executions[i + totalOfferFulfillments - totalFilteredExecutions] = execution;
                }

                // Increment iterator.
                ++i;
            }

            // If some number of executions have been filtered...
            if (totalFilteredExecutions != 0) {
                // reduce the total length of the executions array.
                assembly {
                    mstore(executions, sub(mload(executions), totalFilteredExecutions))
                }
            }
        }

        // Revert if no orders are available.
        if (executions.length == 0) {
            _revertNoSpecifiedOrdersAvailable();
        }

        // Perform final checks and return.
        availableOrders = _performFinalChecksAndExecuteOrders(
            advancedOrders,
            executions,
            orderHashes,
            recipient
        );

        return (availableOrders, executions);
    }

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

    /**
     * @dev Internal function to perform a final check that each consideration
     *      item for an arbitrary number of fulfilled orders has been met and to
     *      trigger associated executions, transferring the respective items.
     *
     * @param advancedOrders     The orders to check and perform executions for.
     * @param executions         An array of elements indicating the sequence of
     *                           transfers to perform when fulfilling the given
     *                           orders.
     * @param orderHashes        An array of order hashes for each order.
     * @param recipient          The intended recipient for all items that do
     *                           not already have a designated recipient and are
     *                           not used as part of a provided fulfillment.
     *
     * @return availableOrders   An array of booleans indicating if each order
     *                           with an index corresponding to the index of the
     *                           returned boolean was fulfillable or not.
     */
    function _performFinalChecksAndExecuteOrders(
        Order[] memory advancedOrders,
        Execution[] memory executions,
        bytes32[] memory orderHashes,
        address recipient
    ) internal returns (bool[] memory /* availableOrders */) {
        // Declare a variable for the available native token balance.
        uint256 nativeTokenBalance;

        // Retrieve the length of the advanced orders array and place on stack.
        uint256 totalOrders = advancedOrders.length;

        // Initialize array for tracking available orders.
        bool[] memory availableOrders = new bool[](totalOrders);

        // Initialize an accumulator array. From this point forward, no new
        // memory regions can be safely allocated until the accumulator is no
        // longer being utilized, as the accumulator operates in an open-ended
        // fashion from this memory pointer; existing memory may still be
        // accessed and modified, however.
        // bytes memory accumulator = new bytes(AccumulatorDisarmed);

        // Retrieve the length of the executions array and place on stack.
        uint256 totalExecutions = executions.length;

        // Iterate over each execution.
        for (uint256 i = 0; i < totalExecutions; ) {
            // Retrieve the execution and the associated received item.
            Execution memory execution = executions[i];
            ReceivedItem memory item = execution.item;

            // If execution transfers native tokens, reduce value available.
            if (item.itemType == ItemType.NATIVE) {
                // Get the current available balance of native tokens.
                assembly {
                    nativeTokenBalance := selfbalance()
                }

                // Ensure that sufficient native tokens are still available.
                if (item.amount > nativeTokenBalance) {
                    _revertInsufficientNativeTokensSupplied();
                }
            }

            // Transfer the item specified by the execution.
            _transfer(item, execution.offerer);

            // Skip overflow check as for loop is indexed starting at zero.
            unchecked {
                ++i;
            }
        }

        // Skip overflow checks as all for loops are indexed starting at zero.
        unchecked {
            // duplicate recipient address to stack to avoid stack-too-deep
            address _recipient = recipient;

            // Iterate over orders to ensure all consideration items are met.
            for (uint256 i = 0; i < totalOrders; ++i) {
                // Retrieve the order in question.
                Order memory advancedOrder = advancedOrders[i];

                // Skip consideration item checks for order if not fulfilled.
                if (orderHashes[i] == bytes32(0)) {
                    // This is required because the current memory region, which
                    // was previously used by the accumulator, might be dirty.
                    availableOrders[i] = false;
                    continue;
                }

                // Mark the order as available.
                availableOrders[i] = true;

                // Retrieve the order parameters.
                OrderParameters memory parameters = advancedOrder.parameters;

                {
                    // Retrieve offer items.
                    OfferItem[] memory offer = parameters.offer;

                    // Read length of offer array & place on the stack.
                    uint256 totalOfferItems = offer.length;

                    // Iterate over each offer item to restore it.
                    for (uint256 j = 0; j < totalOfferItems; ++j) {
                        OfferItem memory offerItem = offer[j];
                        // Retrieve original amount on the offer item.
                        uint256 originalAmount = offerItem.endAmount;
                        // Retrieve remaining amount on the offer item.
                        uint256 unspentAmount = offerItem.startAmount;

                        // Transfer to recipient if unspent amount is not zero.
                        // Note that the transfer will not be reflected in the
                        // executions array.
                        if (unspentAmount != 0) {
                            _transfer(
                                _convertOfferItemToReceivedItemWithRecipient(offerItem, _recipient),
                                parameters.offerer
                            );
                        }

                        // Restore original amount on the offer item.
                        offerItem.startAmount = originalAmount;
                    }
                }

                {
                    // Retrieve consideration items & ensure they are fulfilled.
                    ConsiderationItem[] memory consideration = (parameters.consideration);

                    // Read length of consideration array & place on the stack.
                    uint256 totalConsiderationItems = consideration.length;

                    // Iterate over each consideration item to ensure it is met.
                    for (uint256 j = 0; j < totalConsiderationItems; ++j) {
                        ConsiderationItem memory considerationItem = (consideration[j]);

                        // Retrieve remaining amount on the consideration item.
                        uint256 unmetAmount = considerationItem.startAmount;

                        // Revert if the remaining amount is not zero.
                        if (unmetAmount != 0) {
                            _revertConsiderationNotMet(i, j, unmetAmount);
                        }

                        // Utilize assembly to restore the original value.
                        assembly {
                            // Write recipient to startAmount.
                            mstore(
                                add(considerationItem, ReceivedItem_amount_offset),
                                mload(add(considerationItem, ConsiderationItem_recipient_offset))
                            )
                        }
                    }
                }

                // Check restricted orders and contract orders.
                _assertRestrictedOrderValidity(advancedOrder, orderHashes, orderHashes[i]);
            }
        }

        // Trigger any remaining accumulated transfers via call to the conduit.
        // _triggerIfArmed(accumulator);

        // Determine whether any native token balance remains.
        assembly {
            nativeTokenBalance := selfbalance()
        }

        // Return any remaining native token balance to the caller.
        if (nativeTokenBalance != 0) {
            _transferNativeTokens(payable(msg.sender), nativeTokenBalance);
        }

        // Clear the reentrancy guard.
        // _clearReentrancyGuard();

        // Return the array containing available orders.
        return availableOrders;
    }
}
