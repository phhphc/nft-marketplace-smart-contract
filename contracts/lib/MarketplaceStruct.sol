// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ItemType} from "./MarketplaceEnum.sol";

struct OfferItem {
    ItemType itemType;
    address token;
    uint256 identifier;
    uint256 startAmount;
    uint256 endAmount;
}

struct ConsiderationItem {
    ItemType itemType;
    address token;
    uint256 identifier;
    uint256 startAmount;
    uint256 endAmount;
    address payable recipient;
}

struct OrderParameters {
    address offerer;
    OfferItem[] offer;
    ConsiderationItem[] consideration;
    uint256 startTime;
    uint256 endTime;
    uint256 salt;
}

struct OrderComponents {
    address offerer;
    OfferItem[] offer;
    ConsiderationItem[] consideration;
    uint256 startTime;
    uint256 endTime;
    uint256 salt;
    uint256 counter;
}

struct Order {
    OrderParameters parameters;
    bytes signature;
}

struct OrderStatus {
    bool isValidated;
    bool isCancelled;
    bool isFulFilled;
}

/**
 * @dev A spent item is translated from a utilized offer item and has four
 *      components: an item type (ETH or other native tokens, ERC20, ERC721, and
 *      ERC1155), a token address, a tokenId, and an amount.
 */
struct SpentItem {
    ItemType itemType;
    address token;
    uint256 identifier;
    uint256 amount;
}

/**
 * @dev A received item is translated from a utilized consideration item and has
 *      the same four components as a spent item, as well as an additional fifth
 *      component designating the required recipient of the item.
 */
struct ReceivedItem {
    ItemType itemType;
    address token;
    uint256 identifier;
    uint256 amount;
    address payable recipient;
}
