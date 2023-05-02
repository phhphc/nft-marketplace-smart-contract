// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {OrderStatus, Order, OrderParameters, OrderComponents} from "./MarketplaceStruct.sol";
import {Verifiers} from "./Verifiers.sol";
import {_decodeOrderComponentsAsOrderParameters} from "./MarketplaceDecoder.sol";
import {_revertCannotCancelOrder} from "./MarketplaceErrors.sol";

contract OrderValidator is Verifiers {
    mapping(bytes32 => OrderStatus) private _orderStatus;

    function _validateOrderAndUpdateStatus(
        Order memory order,
        bool revertOnInvalid
    ) internal returns (bytes32 orderHash) {
        OrderParameters memory orderParameters = order.parameters;

        if (!_verifyTime(orderParameters.startTime, orderParameters.endTime, revertOnInvalid)) {
            return bytes32(0);
        }

        orderHash = _deriveOrderHash(orderParameters, _getCounter(orderParameters.offerer));

        // Retrieve the order status using the derived order hash.
        OrderStatus storage orderStatus = _orderStatus[orderHash];

        // Ensure order is fillable and is not cancelled.
        if (!_verifyOrderStatus(orderHash, orderStatus, revertOnInvalid)) {
            // Assuming an invalid order status and no revert, return zero fill.
            return bytes32(0);
        }

        // If the order is not already validated, verify the supplied signature.
        if (!orderStatus.isValidated) {
            _verifySignature(orderParameters.offerer, orderHash, order.signature);
        }

        orderStatus.isValidated = true;
        orderStatus.isCancelled = false;
        orderStatus.isFulFilled = true;

        // Return order hash, new numerator and denominator.
        return orderHash;
    }

    /**
     * @dev Internal function to validate an arbitrary number of orders, thereby
     *      registering their signatures as valid and allowing the fulfiller to
     *      skip signature verification on fulfillment. Note that validated
     *      orders may still be unfulfillable due to invalid item amounts or
     *      other factors; callers should determine whether validated orders are
     *      fulfillable by simulating the fulfillment call prior to execution.
     *      Also note that anyone can validate a signed order, but only the
     *      offerer can validate an order without supplying a signature.
     *
     * @param orders The orders to validate.
     *
     * @return validated A boolean indicating whether the supplied orders were
     *                   successfully validated.
     */
    function _validate(Order[] memory orders) internal returns (bool validated) {
        // Ensure that the reentrancy guard is not currently set.
        // _assertNonReentrant();

        // Declare variables outside of the loop.
        OrderStatus storage orderStatus;
        bytes32 orderHash;
        address offerer;

        // Skip overflow check as for loop is indexed starting at zero.
        unchecked {
            // Read length of the orders array from memory and place on stack.
            uint256 totalOrders = orders.length;

            // Iterate over each order.
            for (uint256 i = 0; i < totalOrders; ++i) {
                // Retrieve the order.
                Order memory order = orders[i];

                // Retrieve the order parameters.
                OrderParameters memory orderParameters = order.parameters;

                // Move offerer from memory to the stack.
                offerer = orderParameters.offerer;

                // Get current counter & use it w/ params to derive order hash.
                orderHash = _deriveOrderHash(orderParameters, _getCounter(offerer));

                // Retrieve the order status using the derived order hash.
                orderStatus = _orderStatus[orderHash];

                // Ensure order is fillable and retrieve the filled amount.
                _verifyOrderStatus(
                    orderHash,
                    orderStatus,
                    true // Signifies to revert if the order is invalid.
                );

                // If the order has not already been validated...
                if (!orderStatus.isValidated) {
                    // Verify the supplied signature.
                    _verifySignature(offerer, orderHash, order.signature);

                    // Update order status to mark the order as valid.
                    orderStatus.isValidated = true;

                    // Emit an event signifying the order has been validated.
                    emit OrderValidated(orderHash, orderParameters);
                }
            }
        }

        // Return a boolean indicating that orders were successfully validated.
        validated = true;
    }

    /**
     * @dev Internal function to cancel an arbitrary number of orders. Note that
     *      only the offerer or the zone of a given order may cancel it. Callers
     *      should ensure that the intended order was cancelled by calling
     *      `getOrderStatus` and confirming that `isCancelled` returns `true`.
     *      Also note that contract orders are not cancellable.
     *
     * @param orders The orders to cancel.
     *
     * @return cancelled A boolean indicating whether the supplied orders were
     *                   successfully cancelled.
     */
    function _cancel(OrderComponents[] calldata orders) internal returns (bool cancelled) {
        // Declare variables outside of the loop.
        OrderStatus storage orderStatus;

        // Declare a variable for tracking invariants in the loop.
        bool anyInvalidCallerOrContractOrder;

        // Skip overflow check as for loop is indexed starting at zero.
        unchecked {
            // Read length of the orders array from memory and place on stack.
            uint256 totalOrders = orders.length;

            // Iterate over each order.
            for (uint256 i = 0; i < totalOrders; ) {
                // Retrieve the order.
                OrderComponents calldata order = orders[i];

                address offerer = order.offerer;

                assembly {
                    // If caller is not the offerer, flag anyInvalidCallerOrContractOrder.
                    anyInvalidCallerOrContractOrder := or(
                        anyInvalidCallerOrContractOrder,
                        iszero(eq(caller(), offerer))
                    )
                }

                bytes32 orderHash = _deriveOrderHash(
                    _decodeOrderComponentsAsOrderParameters(order),
                    order.counter
                );

                // Retrieve the order status using the derived order hash.
                orderStatus = _orderStatus[orderHash];

                // Update the order status as not valid and cancelled.
                orderStatus.isValidated = false;
                orderStatus.isCancelled = true;

                // Emit an event signifying that the order has been cancelled.
                emit OrderCancelled(orderHash, offerer);

                // Increment counter inside body of loop for gas efficiency.
                ++i;
            }

            if (anyInvalidCallerOrContractOrder) {
                _revertCannotCancelOrder();
            }

            // Return a boolean indicating that orders were successfully cancelled.
            cancelled = true;
        }
    }

    /**
     * @dev Internal view function to retrieve the status of a given order by
     *      hash, including whether the order has been cancelled or validated
     *      and the fraction of the order that has been filled.
     *
     * @param orderHash The order hash in question.
     *
     * @return isValidated A boolean indicating whether the order in question
     *                     has been validated (i.e. previously approved or
     *                     partially filled).
     * @return isCancelled A boolean indicating whether the order in question
     *                     has been cancelled.
     */
    function _getOrderStatus(
        bytes32 orderHash
    ) internal view returns (bool isValidated, bool isCancelled, bool isFulFilled) {
        // Retrieve the order status using the order hash.
        OrderStatus storage orderStatus = _orderStatus[orderHash];

        // Return the fields on the order status.
        return (orderStatus.isValidated, orderStatus.isCancelled, orderStatus.isFulFilled);
    }
}
