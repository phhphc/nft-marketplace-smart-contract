// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Order, OrderComponents, OrderParameters} from "./lib/MarketplaceStruct.sol";
import {OrderCombiner} from "./lib/OrderCombiner.sol";
import "hardhat/console.sol";

contract Marketplace is OrderCombiner {
    function fulfillOrder(Order calldata order) external payable returns (bool fulfilled) {
        fulfilled = _validateAndFulfillOrder(order, msg.sender);
    }

    function fulfillOrderBatch(
        Order[] calldata orders
    ) external payable returns (bool[] memory fulfilled) {
        fulfilled = _validateAndFulfillOrderBatch(orders, msg.sender);
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
        Order[] calldata order
    ) external returns (bool /* validated */) {
        return _validate(order);
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
        OrderComponents calldata orderComponents
    ) external view returns (bytes32 orderHash) {
        OrderParameters memory orderParameters;

        orderParameters.offerer = orderComponents.offerer;
        orderParameters.offer = orderComponents.offer;
        orderParameters.consideration = orderComponents.consideration;
        orderParameters.startTime = orderComponents.startTime;
        orderParameters.endTime = orderComponents.endTime;
        orderParameters.salt = orderComponents.salt;

        //   Derive order hash by supplying order parameters along with counter.
        orderHash = _deriveOrderHash(orderParameters, orderComponents.counter);
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
     * @notice Retrieve configuration information for this contract.
     *
     * @return version           The contract version.
     * @return domainSeparator   The domain separator for this contract.
     */
    function information() external view returns (string memory version, bytes32 domainSeparator) {
        // Return the information for this contract.
        return _information();
    }

    /**
     * @dev Internal pure function to retrieve the default name of this
     *      contract and return.
     *
     * @return The name of this contract.
     */
    function _name() internal pure override returns (string memory) {
        return "Lover";
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

    // fallback()external {

    // }
}
