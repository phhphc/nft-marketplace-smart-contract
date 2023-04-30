// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import {
    ReceivedItem,
    OfferItem,
    ConsiderationItem,
    OrderComponents,
    OrderParameters
} from "./MarketplaceStruct.sol";
import {ReceivedItem_recipient_offset} from "./MarketplaceConstants.sol";

/**
 * @dev Converts a function taking ReceivedItem, address, bytes32, and bytes
 *      types (e.g. the _transfer function) into a function taking
 *      OfferItem, address, bytes32, and bytes types.
 *
 * @param inFn The input function, taking ReceivedItem, address, bytes32,
 *             and bytes types (e.g. the _transfer function).
 *
 * @return outFn The output function, taking OfferItem, address, bytes32,
 *               and bytes types.
 */
function _toOfferItemInput(
    function(ReceivedItem memory, address) internal inFn
) pure returns (function(OfferItem memory, address) internal outFn) {
    assembly {
        outFn := inFn
    }
}

/**
 * @dev Converts a function taking ReceivedItem, address, bytes32, and bytes
 *      types (e.g. the _transfer function) into a function taking
 *      ConsiderationItem, address, bytes32, and bytes types.
 *
 * @param inFn The input function, taking ReceivedItem, address, bytes32,
 *             and bytes types (e.g. the _transfer function).
 *
 * @return outFn The output function, taking ConsiderationItem, address,
 *               bytes32, and bytes types.
 */
function _toConsiderationItemInput(
    function(ReceivedItem memory, address) internal inFn
) pure returns (function(ConsiderationItem memory, address) internal outFn) {
    assembly {
        outFn := inFn
    }
}

function _decodeOrderComponentsAsOrderParameters(
    OrderComponents memory orderComponents
) pure returns (OrderParameters memory orderParameters) {
    orderParameters.offerer = orderComponents.offerer;
    orderParameters.offer = orderComponents.offer;
    orderParameters.consideration = orderComponents.consideration;
    orderParameters.startTime = orderComponents.startTime;
    orderParameters.endTime = orderComponents.endTime;
    orderParameters.salt = orderComponents.salt;
}

/**
 * @dev Converts an offer item into a received item, applying a given
 *      recipient.
 *
 * @param offerItem The offer item.
 * @param recipient The recipient.
 *
 * @return receivedItem The received item.
 */
function _convertOfferItemToReceivedItemWithRecipient(
    OfferItem memory offerItem,
    address recipient
) pure returns (ReceivedItem memory receivedItem) {
    assembly {
        receivedItem := offerItem
        mstore(add(receivedItem, ReceivedItem_recipient_offset), recipient)
    }
}
