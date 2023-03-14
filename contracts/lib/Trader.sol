// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Order, OrderComponents, FulfillmentComponent, Execution} from "./TraderStructs.sol";
import {CalldataStart, CalldataPointer} from "../helpers/PointerLibraries.sol";

import {OrderCombiner} from "./OrderCombiner.sol";

import {
    OrderParameters_counter_offset,
    Offset_fulfillAvailableOrders_offerFulfillments,
    Offset_fulfillAvailableOrders_considerationFulfillments
} from "./ConsiderationConstants.sol";

contract Trader is OrderCombiner {
    /**
     * @notice Fulfill an order with an arbitrary number of items for offer and
     *         consideration. Note that this function does not support
     *         criteria-based orders or partial filling of orders (though
     *         filling the remainder of a partially-filled order is supported).
     *
     * @custom:param order        The order to fulfill. Note that both the
     *                            offerer and the fulfiller must first approve
     *                            this contract (or the corresponding conduit if
     *                            indicated) to transfer any relevant tokens on
     *                            their behalf and that contracts must implement
     *                            `onERC1155Received` to receive ERC1155 tokens
     *                            as consideration.
     *
     * @return fulfilled A boolean indicating whether the order has been
     *                   successfully fulfilled.
     */
    function fulfillOrder(
        /**
         * @custom:name order
         */
        Order calldata
    ) external payable returns (bool fulfilled) {
        // Convert order to "advanced" order, then validate and fulfill it.
        fulfilled = _validateAndFulfillOrder(
            _toOrderReturnType(_decodeOrder)(CalldataStart.pptr()),
            msg.sender
        );
    }

    /**
     * @notice Validate an arbitrary number of orders, thereby registering their
     *         signatures as valid and allowing the fulfiller to skip signature
     *         verification on fulfillment. Note that validated orders may still
     *         be unfulfillable due to invalid item amounts or other factors;
     *         callers should determine whether validated orders are fulfillable
     *         by simulating the fulfillment call prior to execution. Also note
     *         that anyone can validate a signed order, but only the offerer can
     *         validate an order without supplying a signature.
     *
     * @custom:param orders The orders to validate.
     *
     * @return validated A boolean indicating whether the supplied orders have
     *                   been successfully validated.
     */
    function validate(
        /**
         * @custom:name orders
         */
        Order[] calldata
    ) external returns (bool /* validated */) {
        return _validate(_toOrdersReturnType(_decodeOrders)(CalldataStart.pptr()));
    }

    /**
     * @notice Attempt to fill a group of orders, each with an arbitrary number
     *         of items for offer and consideration. Any order that is not
     *         currently active, has already been fully filled, or has been
     *         cancelled will be omitted. Remaining offer and consideration
     *         items will then be aggregated where possible as indicated by the
     *         supplied offer and consideration component arrays and aggregated
     *         items will be transferred to the fulfiller or to each intended
     *         recipient, respectively. Note that a failing item transfer or an
     *         issue with order formatting will cause the entire batch to fail.
     *         Note that this function does not support criteria-based orders or
     *         partial filling of orders (though filling the remainder of a
     *         partially-filled order is supported).
     *
     * @custom:param orders                    The orders to fulfill. Note that
     *                                         both the offerer and the
     *                                         fulfiller must first approve this
     *                                         contract (or the corresponding
     *                                         conduit if indicated) to transfer
     *                                         any relevant tokens on their
     *                                         behalf and that contracts must
     *                                         implement `onERC1155Received` to
     *                                         receive ERC1155 tokens as
     *                                         consideration.
     * @custom:param offerFulfillments         An array of FulfillmentComponent
     *                                         arrays indicating which offer
     *                                         items to attempt to aggregate
     *                                         when preparing executions. Note
     *                                         that any offer items not included
     *                                         as part of a fulfillment will be
     *                                         sent unaggregated to the caller.
     * @custom:param considerationFulfillments An array of FulfillmentComponent
     *                                         arrays indicating which
     *                                         consideration items to attempt to
     *                                         aggregate when preparing
     *                                         executions.
     * @param maximumFulfilled                 The maximum number of orders to
     *                                         fulfill.
     *
     * @return availableOrders An array of booleans indicating if each order
     *                         with an index corresponding to the index of the
     *                         returned boolean was fulfillable or not.
     * @return executions      An array of elements indicating the sequence of
     *                         transfers performed as part of matching the given
     *                         orders.
     */
    function fulfillAvailableOrders(
        /**
         * @custom:name orders
         */
        Order[] calldata,
        /**
         * @custom:name offerFulfillments
         */
        FulfillmentComponent[][] calldata,
        /**
         * @custom:name considerationFulfillments
         */
        FulfillmentComponent[][] calldata,
        uint256 maximumFulfilled
    )
        external
        payable
        returns (bool[] memory /* availableOrders */, Execution[] memory /* executions */)
    {
        // Convert orders to "advanced" orders and fulfill all available orders.
        return
            _fulfillAvailableAdvancedOrders(
                _toOrdersReturnType(_decodeOrders)(CalldataStart.pptr()), // Convert to advanced orders.
                _toNestedFulfillmentComponentsReturnType(_decodeNestedFulfillmentComponents)(
                    CalldataStart.pptr(Offset_fulfillAvailableOrders_offerFulfillments)
                ),
                _toNestedFulfillmentComponentsReturnType(_decodeNestedFulfillmentComponents)(
                    CalldataStart.pptr(Offset_fulfillAvailableOrders_considerationFulfillments)
                ),
                msg.sender,
                maximumFulfilled
            );
    }

    /**
     * @notice Cancel an arbitrary number of orders. Note that only the offerer
     *         or the zone of a given order may cancel it. Callers should ensure
     *         that the intended order was cancelled by calling `getOrderStatus`
     *         and confirming that `isCancelled` returns `true`.
     *
     * @param orders The orders to cancel.
     *
     * @return cancelled A boolean indicating whether the supplied orders have
     *                   been successfully cancelled.
     */
    function cancel(OrderComponents[] calldata orders) external returns (bool cancelled) {
        // Cancel the orders.
        cancelled = _cancel(orders);
    }

    /**
     * @notice Cancel all orders from a given offerer with a given zone in bulk
     *         by incrementing a counter. Note that only the offerer may
     *         increment the counter.
     *
     * @return newCounter The new counter.
     */
    function incrementCounter() external returns (uint256 newCounter) {
        // Increment current counter for the supplied offerer.  Note that the
        // counter is incremented by a large, quasi-random interval.
        newCounter = _incrementCounter();
    }

    /**
     * @notice Retrieve the order hash for a given order.
     *
     * @custom:param order The components of the order.
     *
     * @return orderHash The order hash.
     */
    function getOrderHash(
        /**
         * @custom:name order
         */
        OrderComponents calldata
    ) external view returns (bytes32 orderHash) {
        CalldataPointer orderPointer = CalldataStart.pptr();

        // Derive order hash by supplying order parameters along with counter.
        orderHash = _deriveOrderHash(
            _toOrderParametersReturnType(_decodeOrderComponentsAsOrderParameters)(orderPointer),
            // Read order counter
            orderPointer.offset(OrderParameters_counter_offset).readUint256()
        );
    }

    /**
     * @notice Retrieve the status of a given order by hash, including whether
     *         the order has been cancelled or validated and the fraction of the
     *         order that has been filled. Since the _orderStatus[orderHash]
     *         does not get set for contract orders, getOrderStatus will always
     *         return (false, false, 0, 0) for those hashes. Note that this
     *         function is susceptible to view reentrancy and so should be used
     *         with care when calling from other contracts.
     *
     * @param orderHash The order hash in question.
     *
     * @return isValidated A boolean indicating whether the order in question
     *                     has been validated (i.e. previously approved or
     *                     partially filled).
     * @return isCancelled A boolean indicating whether the order in question
     *                     has been cancelled.
     */
    function getOrderStatus(
        bytes32 orderHash
    ) external view returns (bool isValidated, bool isCancelled, bool isFulFilled) {
        // Retrieve the order status using the order hash.
        return _getOrderStatus(orderHash);
    }

    /**
     * @notice Retrieve the current counter for a given offerer.
     *
     * @param offerer The offerer in question.
     *
     * @return counter The current counter.
     */
    function getCounter(address offerer) external view returns (uint256 counter) {
        // Return the counter for the supplied offerer.
        counter = _getCounter(offerer);
    }

    /**
     * @notice Retrieve configuration information for this contract.
     *
     * @return version           The contract version.
     * @return domainSeparator   The domain separator for this contract.
     * @return conduitController The conduit Controller set for this contract.
     */
    function information()
        external
        view
        returns (string memory version, bytes32 domainSeparator, address conduitController)
    {
        // Return the information for this contract.
        return _information();
    }

    /**
     * @notice Retrieve the name of this contract.
     *
     * @return contractName The name of this contract.
     */
    function name() external pure returns (string memory /* contractName */) {
        // Return the name of the contract.
        return _name();
    }
}
