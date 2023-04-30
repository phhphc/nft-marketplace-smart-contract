// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {OrderParameters, SpentItem, ReceivedItem} from "../lib/MarketplaceStruct.sol";

contract MarketplaceEvents {
    /**
     * @dev Emit an event whenever an order is explicitly validated. Note that
     *      this event will not be emitted on partial fills even though they do
     *      validate the order as part of partial fulfillment.
     *
     * @param orderHash        The hash of the validated order.
     * @param orderParameters  The parameters of the validated order.
     */
    event OrderValidated(bytes32 orderHash, OrderParameters orderParameters);

    /**
     * @dev Emit an event whenever an order is successfully fulfilled.
     *
     * @param orderHash     The hash of the fulfilled order.
     * @param offerer       The offerer of the fulfilled order.
     * @param recipient     The recipient of each spent item on the fulfilled
     *                      order, or the null address if there is no specific
     *                      fulfiller (i.e. the order is part of a group of
     *                      orders). Defaults to the caller unless explicitly
     *                      specified otherwise by the fulfiller.
     * @param offer         The offer items spent as part of the order.
     * @param consideration The consideration items received as part of the
     *                      order along with the recipients of each item.
     */
    event OrderFulfilled(
        bytes32 orderHash,
        address indexed offerer,
        address recipient,
        SpentItem[] offer,
        ReceivedItem[] consideration
    );

    /**
     * @dev Emit an event whenever an order is successfully cancelled.
     *
     * @param orderHash The hash of the cancelled order.
     * @param offerer   The offerer of the cancelled order.
     */
    event OrderCancelled(bytes32 orderHash, address indexed offerer);

    /**
     * @dev Emit an event whenever a counter for a given offerer is incremented.
     *
     * @param newCounter The new counter for the offerer.
     * @param offerer    The offerer in question.
     */
    event CounterIncremented(uint256 newCounter, address indexed offerer);
}
