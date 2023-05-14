// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {
    OrderParameters,
    Order,
    OfferItem,
    ItemType,
    ConsiderationItem,
    ReceivedItem,
    SpentItem
} from "./MarketplaceStruct.sol";
import {OrderValidator} from "./OrderValidator.sol";
import {AmountDeriver} from "./AmountDeriver.sol";
import {Executor} from "./Executor.sol";
import {
    OneWord,
    OneWordShift,
    ConsiderationItem_recipient_offset,
    ReceivedItem_recipient_offset
} from "./MarketplaceConstants.sol";
import {
    _toOfferItemInput,
    _toConsiderationItemInput,
    _convertOfferItemToReceivedItemWithRecipient
} from "./MarketplaceDecoder.sol";
import {
    _revertInvalidNativeOfferItem,
    _revertInsufficientNativeTokensSupplied
} from "./MarketplaceErrors.sol";
import "hardhat/console.sol";

contract OrderCombiner is OrderValidator, AmountDeriver, Executor {
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
        bytes32 orderHash = _validateOrderAndUpdateStatus(order, true);

        OrderParameters memory orderParameters = order.parameters;

        // Perform each item transfer with the appropriate amount.
        _transferEach(orderParameters, recipient);

        // Emit an event signifying that the order has been fulfilled.
        _emitOrderFulfilledEvent(
            orderHash,
            orderParameters.offerer,
            recipient,
            orderParameters.offer,
            orderParameters.consideration
        );

        return true;
    }

    function _validateAndFulfillOrderBatch(
        Order[] memory orders,
        address recipient
    ) internal returns (bool[] memory fulfilled) {
        // Validate orders, apply amounts, & determine if they utilize conduits.
        bytes32[] memory orderHashes = _validateOrdersAndPrepareToFulfill(
            orders,
            false, // Signifies that invalid orders should NOT revert.
            recipient
        );

        // Aggregate used offer and consideration items and execute transfers.
        return _executeAvailableFulfillments(orders, recipient, orderHashes);
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
        // Read start time & end time from order parameters.
        uint256 startTime = orderParameters.startTime;
        uint256 endTime = orderParameters.endTime;

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
                        startTime,
                        endTime,
                        false
                    );

                    // Utilize assembly to set overloaded offerItem arguments.
                    // Write new fractional amount to startAmount as amount.
                    offerItem.startAmount = amount;
                    // Write recipient to endAmount.
                    offerItem.endAmount = uint160(recipient);
                }

                // Transfer the item from the offerer to the recipient.
                _toOfferItemInput(_transfer)(offerItem, orderParameters.offerer);
            }

            // If order has native offer items, throw with an
            // `InvalidNativeOfferItem` custom error.
            {
                if (anyNativeItems != 0) {
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
                    startTime,
                    endTime,
                    true
                );

                // Use assembly to set overloaded considerationItem arguments.
                // Write derived fractional amount to startAmount as amount.
                considerationItem.startAmount = amount;
                // Write recipient to endAmount.
                considerationItem.endAmount = uint160(address(considerationItem.recipient));

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
     * @param recipient     The recipient of the order, or the null address if
     *                      the order was fulfilled via order matching.
     * @param offer         The offer items for the order.
     * @param consideration The consideration items for the order.
     */
    function _emitOrderFulfilledEvent(
        bytes32 orderHash,
        address offerer,
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
        emit OrderFulfilled(orderHash, offerer, recipient, spentItems, receivedItems);
    }

    /**
     * @dev Internal function to validate a group of orders, update their
     *      statuses, reduce amounts by their previously filled fractions, apply
     *      criteria resolvers, and emit OrderFulfilled events. Note that this
     *      function needs to be called before
     *      _aggregateValidFulfillmentConsiderationItems to set the memory
     *      layout that _aggregateValidFulfillmentConsiderationItems depends on.
     *
     * @param orders    The advanced orders to validate and reduce by
     *                          their previously filled amounts.
     * @param revertOnInvalid   A boolean indicating whether to revert on any
     *                          order being invalid; setting this to false will
     *                          instead cause the invalid order to be skipped.
     * @param recipient         The intended recipient for all items that do not
     *                          already have a designated recipient and are not
     *                          already used as part of a provided fulfillment.
     *
     * @return orderHashes      The hashes of the orders being fulfilled.
     */
    function _validateOrdersAndPrepareToFulfill(
        Order[] memory orders,
        bool revertOnInvalid,
        address recipient
    ) internal returns (bytes32[] memory orderHashes) {
        // Declare an error buffer indicating status of any native offer items.
        // Native tokens may only be provided as part of contract orders or when
        // fulfilling via matchOrders or matchAdvancedOrders; if bits indicating
        // these conditions are not met have been set, throw.
        uint256 invalidNativeOfferItemErrorBuffer;

        // Declare variables for later use.
        Order memory advancedOrder;
        uint256 terminalMemoryOffset;

        unchecked {
            // Read length of orders array and place on the stack.
            uint256 totalOrders = orders.length;

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
                    advancedOrder := mload(add(orders, i))
                }

                // Validate it, update status, and determine fraction to fill.
                bytes32 orderHash = _validateOrderAndUpdateStatus(advancedOrder, revertOnInvalid);

                // Do not track hash or adjust prices if order is not fulfilled.
                if (orderHash == bytes32(0)) {
                    // Continue iterating through the remaining orders.
                    continue;
                }

                // Otherwise, track the order hash in question.
                assembly {
                    mstore(add(orderHashes, i), orderHash)
                }

                // Place the start time for the order on the stack.
                uint256 startTime = advancedOrder.parameters.startTime;

                // Place the end time for the order on the stack.
                uint256 endTime = advancedOrder.parameters.endTime;

                // Retrieve array of offer items for the order in question.
                offer = advancedOrder.parameters.offer;

                // Read length of offer array and place on the stack.
                uint256 totalOfferItems = offer.length;

                // Iterate over each offer item on the order.
                for (uint256 j = 0; j < totalOfferItems; ++j) {
                    // Retrieve the offer item.
                    OfferItem memory offerItem = offer[j];

                    {
                        ItemType itemType = offerItem.itemType;
                        assembly {
                            // If the offer item is for the native token and the
                            // order type is not a contract order type, set the
                            // first bit of the error buffer to true.
                            invalidNativeOfferItemErrorBuffer := or(
                                invalidNativeOfferItemErrorBuffer,
                                iszero(itemType)
                            )
                        }
                    }

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

        if (invalidNativeOfferItemErrorBuffer != 0) {
            _revertInvalidNativeOfferItem();
        }

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
                    advancedOrder := mload(add(orders, i))
                }

                // Retrieve parameters for the order in question.
                OrderParameters memory orderParameters = (advancedOrder.parameters);

                // Emit an OrderFulfilled event.
                _emitOrderFulfilledEvent(
                    orderHash,
                    orderParameters.offerer,
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
     * @param orders            The orders to fulfill along with the
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
     * @param recipient                 The intended recipient for all items
     *                                  that do not already have a designated
     *                                  recipient and are not already used as
     *                                  part of a provided fulfillment.
     * @param orderHashes               An array of order hashes for each order.
     *
     * @return availableOrders An array of booleans indicating if each order
     *                         with an index corresponding to the index of the
     *                         returned boolean was fulfillable or not.
     */
    function _executeAvailableFulfillments(
        Order[] memory orders,
        address recipient,
        bytes32[] memory orderHashes
    ) internal returns (bool[] memory) {
        // Declare a variable for the available native token balance.
        uint256 nativeTokenBalance;

        // Retrieve length of offer array and place on the stack.
        uint256 totalOrders = orders.length;

        // Initialize array for tracking available orders.
        bool[] memory availableOrders = new bool[](totalOrders);

        // duplicate recipient address to stack to avoid stack-too-deep
        address _recipient = recipient;

        for (uint256 i = 0; i < totalOrders; i++) {
            Order memory advancedOrder = orders[i];

            if (orderHashes[i] == bytes32(0)) {
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
                // Retrieve consideration items.
                ConsiderationItem[] memory consideration = parameters.consideration;

                // Read length of consideration array & place on the stack.
                uint256 totalOfferItems = consideration.length;

                // Iterate over each offer item to restore it.
                for (uint256 j = 0; j < totalOfferItems; ++j) {
                    ConsiderationItem memory considerationItem = consideration[j];
                    // Retrieve original amount on the offer item.
                    uint256 originalAmount = considerationItem.endAmount;
                    // Retrieve remaining amount on the offer item.
                    uint256 unspentAmount = considerationItem.startAmount;

                    // Reduce available value if offer spent ETH or a native token.
                    if (considerationItem.itemType == ItemType.NATIVE) {
                        // Get the current available balance of native tokens.
                        assembly {
                            nativeTokenBalance := selfbalance()
                        }

                        // Ensure that sufficient native tokens are still available.
                        if (unspentAmount > nativeTokenBalance) {
                            _revertInsufficientNativeTokensSupplied();
                        }
                    }

                    // Transfer to recipient if unspent amount is not zero.
                    // Note that the transfer will not be reflected in the
                    // executions array.
                    if (unspentAmount != 0) {
                        _toConsiderationItemInput(_transfer)(considerationItem, msg.sender);
                    }

                    // Restore original amount on the offer item.
                    considerationItem.startAmount = originalAmount;
                }
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

        // Return the array containing available orders.
        return availableOrders;
    }
}
