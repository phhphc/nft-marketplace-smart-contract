// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ItemType, OrderType} from "./TraderEnums.sol";
import {CalldataPointer, MemoryPointer} from "../helpers/PointerLibraries.sol";

/**
 * @dev An offer item has five components: an item type (ETH or other native
 *      tokens, ERC20, ERC721, and ERC1155, as well as criteria-based ERC721 and
 *      ERC1155), a token address, a dual-purpose "identifierOrCriteria"
 *      component that will either represent a tokenId or a merkle root
 *      depending on the item type, and a start and end amount that support
 *      increasing or decreasing amounts over the duration of the respective
 *      order.
 */
struct OfferItem {
    ItemType itemType;
    address token;
    uint256 identifier;
    uint256 startAmount;
    uint256 endAmount;
}

/**
 * @dev A consideration item has the same five components as an offer item and
 *      an additional sixth component designating the required recipient of the
 *      item.
 */
struct ConsiderationItem {
    ItemType itemType;
    address token;
    uint256 identifier;
    uint256 startAmount;
    uint256 endAmount;
    address payable recipient;
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

/**
 * @dev The full set of order components, with the exception of the counter,
 *      must be supplied when fulfilling more sophisticated orders or groups of
 *      orders. The total number of original consideration items must also be
 *      supplied, as the caller may specify additional consideration items.
 */
struct OrderParameters {
    address offerer; // 0x00
    address zone; // 0x20
    OfferItem[] offer; // 0x40
    ConsiderationItem[] consideration; // 0x60
    OrderType orderType; // 0x80
    uint256 startTime; // 0xa0
    uint256 endTime; // 0xc0
    bytes32 zoneHash; // 0xe0
    uint256 salt; // 0x100
    uint256 totalOriginalConsiderationItems; // 0x120
    // offer.length                          // 0x160
}

/**
 * @dev An order contains eleven components: an offerer, a zone (or account that
 *      can cancel the order or restrict who can fulfill the order depending on
 *      the type), the order type (specifying partial fill support as well as
 *      restricted order status), the start and end time, a hash that will be
 *      provided to the zone when validating restricted orders, a salt, a key
 *      corresponding to a given conduit, a counter, and an arbitrary number of
 *      offer items that can be spent along with consideration items that must
 *      be received by their respective recipient.
 */
struct OrderComponents {
    address offerer; //0x00
    address zone; //0x20
    OfferItem[] offer; //0x40
    ConsiderationItem[] consideration; //0x60
    OrderType orderType; //0x80
    uint256 startTime; //0xa0
    uint256 endTime; //0xc0
    bytes32 zoneHash; //0xe0
    uint256 salt; //0x100
    uint256 counter; //0x120
}

/**
 * @dev Orders require a signature in addition to the other order parameters.
 */
struct Order {
    OrderParameters parameters;
    bytes signature;
}

/**
 * @dev Advanced orders include a numerator (i.e. a fraction to attempt to fill)
 *      and a denominator (the total size of the order) in addition to the
 *      signature and other order parameters. It also supports an optional field
 *      for supplying extra data; this data will be provided to the zone if the
 *      order type is restricted and the zone is not the caller, or will be
 *      provided to the offerer as context for contract order types.
 */
struct AdvancedOrder {
    OrderParameters parameters;
    uint120 numerator;
    uint120 denominator;
    bytes signature;
    bytes extraData;
}

/**
 * @dev Orders can be validated (either explicitly via `validate`, or as a
 *      consequence of a full or partial fill), specifically cancelled (they can
 *      also be cancelled in bulk via incrementing a per-zone counter), and
 *      partially or fully filled (with the fraction filled represented by a
 *      numerator and denominator).
 */
struct OrderStatus {
    bool isValidated;
    bool isCancelled;
    bool isFulFilled;
}

/**
 * @dev A fulfillment is applied to a group of orders. It decrements a series of
 *      offer and consideration items, then generates a single execution
 *      element. A given fulfillment can be applied to as many offer and
 *      consideration items as desired, but must contain at least one offer and
 *      at least one consideration that match. The fulfillment must also remain
 *      consistent on all key parameters across all offer items (same offerer,
 *      token, type, tokenId, and conduit preference) as well as across all
 *      consideration items (token, type, tokenId, and recipient).
 */
struct Fulfillment {
    FulfillmentComponent[] offerComponents;
    FulfillmentComponent[] considerationComponents;
}

/**
 * @dev Each fulfillment component contains one index referencing a specific
 *      order and another referencing a specific offer or consideration item.
 */
struct FulfillmentComponent {
    uint256 orderIndex;
    uint256 itemIndex;
}

/**
 * @dev An execution is triggered once all consideration items have been zeroed
 *      out. It sends the item in question from the offerer to the item's
 *      recipient, optionally sourcing approvals from either this contract
 *      directly or from the offerer's chosen conduit if one is specified. An
 *      execution is not provided as an argument, but rather is derived via
 *      orders, criteria resolvers, and fulfillments (where the total number of
 *      executions will be less than or equal to the total number of indicated
 *      fulfillments) and returned as part of `matchOrders`.
 */
struct Execution {
    ReceivedItem item;
    address offerer;
    bytes32 conduitKey;
}

using StructPointers for OrderComponents global;
using StructPointers for OfferItem global;
using StructPointers for ConsiderationItem global;
using StructPointers for SpentItem global;
using StructPointers for ReceivedItem global;
// using StructPointers for BasicOrderParameters global;
// using StructPointers for AdditionalRecipient global;
using StructPointers for OrderParameters global;
using StructPointers for Order global;
using StructPointers for AdvancedOrder global;
using StructPointers for OrderStatus global;

// using StructPointers for CriteriaResolver global;
using StructPointers for Fulfillment global;
using StructPointers for FulfillmentComponent global;

// using StructPointers for Execution global;
// using StructPointers for ZoneParameters global;

/**
 * @dev This library provides a set of functions for converting structs to
 *      pointers.
 */
library StructPointers {
    /**
     * @dev Get a MemoryPointer from OrderComponents.
     *
     * @param obj The OrderComponents object.
     *
     * @return ptr The MemoryPointer.
     */
    function toMemoryPointer(OrderComponents memory obj) internal pure returns (MemoryPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a CalldataPointer from OrderComponents.
     *
     * @param obj The OrderComponents object.
     *
     * @return ptr The CalldataPointer.
     */
    function toCalldataPointer(
        OrderComponents calldata obj
    ) internal pure returns (CalldataPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a MemoryPointer from OfferItem.
     *
     * @param obj The OfferItem object.
     *
     * @return ptr The MemoryPointer.
     */
    function toMemoryPointer(OfferItem memory obj) internal pure returns (MemoryPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a CalldataPointer from OfferItem.
     *
     * @param obj The OfferItem object.
     *
     * @return ptr The CalldataPointer.
     */
    function toCalldataPointer(OfferItem calldata obj) internal pure returns (CalldataPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a MemoryPointer from ConsiderationItem.
     *
     * @param obj The ConsiderationItem object.
     *
     * @return ptr The MemoryPointer.
     */
    function toMemoryPointer(
        ConsiderationItem memory obj
    ) internal pure returns (MemoryPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a CalldataPointer from ConsiderationItem.
     *
     * @param obj The ConsiderationItem object.
     *
     * @return ptr The CalldataPointer.
     */
    function toCalldataPointer(
        ConsiderationItem calldata obj
    ) internal pure returns (CalldataPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a MemoryPointer from SpentItem.
     *
     * @param obj The SpentItem object.
     *
     * @return ptr The MemoryPointer.
     */
    function toMemoryPointer(SpentItem memory obj) internal pure returns (MemoryPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a CalldataPointer from SpentItem.
     *
     * @param obj The SpentItem object.
     *
     * @return ptr The CalldataPointer.
     */
    function toCalldataPointer(SpentItem calldata obj) internal pure returns (CalldataPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a MemoryPointer from ReceivedItem.
     *
     * @param obj The ReceivedItem object.
     *
     * @return ptr The MemoryPointer.
     */
    function toMemoryPointer(ReceivedItem memory obj) internal pure returns (MemoryPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a CalldataPointer from ReceivedItem.
     *
     * @param obj The ReceivedItem object.
     *
     * @return ptr The CalldataPointer.
     */
    function toCalldataPointer(
        ReceivedItem calldata obj
    ) internal pure returns (CalldataPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    // /**
    //  * @dev Get a MemoryPointer from AdditionalRecipient.
    //  *
    //  * @param obj The AdditionalRecipient object.
    //  *
    //  * @return ptr The MemoryPointer.
    //  */
    // function toMemoryPointer(
    //     AdditionalRecipient memory obj
    // ) internal pure returns (MemoryPointer ptr) {
    //     assembly {
    //         ptr := obj
    //     }
    // }

    // /**
    //  * @dev Get a CalldataPointer from AdditionalRecipient.
    //  *
    //  * @param obj The AdditionalRecipient object.
    //  *
    //  * @return ptr The CalldataPointer.
    //  */
    // function toCalldataPointer(
    //     AdditionalRecipient calldata obj
    // ) internal pure returns (CalldataPointer ptr) {
    //     assembly {
    //         ptr := obj
    //     }
    // }

    /**
     * @dev Get a MemoryPointer from OrderParameters.
     *
     * @param obj The OrderParameters object.
     *
     * @return ptr The MemoryPointer.
     */
    function toMemoryPointer(OrderParameters memory obj) internal pure returns (MemoryPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a CalldataPointer from OrderParameters.
     *
     * @param obj The OrderParameters object.
     *
     * @return ptr The CalldataPointer.
     */
    function toCalldataPointer(
        OrderParameters calldata obj
    ) internal pure returns (CalldataPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a MemoryPointer from Order.
     *
     * @param obj The Order object.
     *
     * @return ptr The MemoryPointer.
     */
    function toMemoryPointer(Order memory obj) internal pure returns (MemoryPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a CalldataPointer from Order.
     *
     * @param obj The Order object.
     *
     * @return ptr The CalldataPointer.
     */
    function toCalldataPointer(Order calldata obj) internal pure returns (CalldataPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a MemoryPointer from AdvancedOrder.
     *
     * @param obj The AdvancedOrder object.
     *
     * @return ptr The MemoryPointer.
     */
    function toMemoryPointer(AdvancedOrder memory obj) internal pure returns (MemoryPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a CalldataPointer from AdvancedOrder.
     *
     * @param obj The AdvancedOrder object.
     *
     * @return ptr The CalldataPointer.
     */
    function toCalldataPointer(
        AdvancedOrder calldata obj
    ) internal pure returns (CalldataPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a MemoryPointer from OrderStatus.
     *
     * @param obj The OrderStatus object.
     *
     * @return ptr The MemoryPointer.
     */
    function toMemoryPointer(OrderStatus memory obj) internal pure returns (MemoryPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    /**
     * @dev Get a CalldataPointer from OrderStatus.
     *
     * @param obj The OrderStatus object.
     *
     * @return ptr The CalldataPointer.
     */
    function toCalldataPointer(
        OrderStatus calldata obj
    ) internal pure returns (CalldataPointer ptr) {
        assembly {
            ptr := obj
        }
    }

    // /**
    //  * @dev Get a MemoryPointer from CriteriaResolver.
    //  *
    //  * @param obj The CriteriaResolver object.
    //  *
    //  * @return ptr The MemoryPointer.
    //  */
    // function toMemoryPointer(
    //     CriteriaResolver memory obj
    // ) internal pure returns (MemoryPointer ptr) {
    //     assembly {
    //         ptr := obj
    //     }
    // }

    // /**
    //  * @dev Get a CalldataPointer from CriteriaResolver.
    //  *
    //  * @param obj The CriteriaResolver object.
    //  *
    //  * @return ptr The CalldataPointer.
    //  */
    // function toCalldataPointer(
    //     CriteriaResolver calldata obj
    // ) internal pure returns (CalldataPointer ptr) {
    //     assembly {
    //         ptr := obj
    //     }
    // }

    // /**
    //  * @dev Get a MemoryPointer from Fulfillment.
    //  *
    //  * @param obj The Fulfillment object.
    //  *
    //  * @return ptr The MemoryPointer.
    //  */
    // function toMemoryPointer(
    //     Fulfillment memory obj
    // ) internal pure returns (MemoryPointer ptr) {
    //     assembly {
    //         ptr := obj
    //     }
    // }

    // /**
    //  * @dev Get a CalldataPointer from Fulfillment.
    //  *
    //  * @param obj The Fulfillment object.
    //  *
    //  * @return ptr The CalldataPointer.
    //  */
    // function toCalldataPointer(
    //     Fulfillment calldata obj
    // ) internal pure returns (CalldataPointer ptr) {
    //     assembly {
    //         ptr := obj
    //     }
    // }

    // /**
    //  * @dev Get a MemoryPointer from FulfillmentComponent.
    //  *
    //  * @param obj The FulfillmentComponent object.
    //  *
    //  * @return ptr The MemoryPointer.
    //  */
    // function toMemoryPointer(
    //     FulfillmentComponent memory obj
    // ) internal pure returns (MemoryPointer ptr) {
    //     assembly {
    //         ptr := obj
    //     }
    // }

    // /**
    //  * @dev Get a CalldataPointer from FulfillmentComponent.
    //  *
    //  * @param obj The FulfillmentComponent object.
    //  *
    //  * @return ptr The CalldataPointer.
    //  */
    // function toCalldataPointer(
    //     FulfillmentComponent calldata obj
    // ) internal pure returns (CalldataPointer ptr) {
    //     assembly {
    //         ptr := obj
    //     }
    // }

    // /**
    //  * @dev Get a MemoryPointer from Execution.
    //  *
    //  * @param obj The Execution object.
    //  *
    //  * @return ptr The MemoryPointer.
    //  */
    // function toMemoryPointer(
    //     Execution memory obj
    // ) internal pure returns (MemoryPointer ptr) {
    //     assembly {
    //         ptr := obj
    //     }
    // }

    // /**
    //  * @dev Get a CalldataPointer from Execution.
    //  *
    //  * @param obj The Execution object.
    //  *
    //  * @return ptr The CalldataPointer.
    //  */
    // function toCalldataPointer(
    //     Execution calldata obj
    // ) internal pure returns (CalldataPointer ptr) {
    //     assembly {
    //         ptr := obj
    //     }
    // }

    // /**
    //  * @dev Get a MemoryPointer from ZoneParameters.
    //  *
    //  * @param obj The ZoneParameters object.
    //  *
    //  * @return ptr The MemoryPointer.
    //  */
    // function toMemoryPointer(
    //     ZoneParameters memory obj
    // ) internal pure returns (MemoryPointer ptr) {
    //     assembly {
    //         ptr := obj
    //     }
    // }

    // /**
    //  * @dev Get a CalldataPointer from ZoneParameters.
    //  *
    //  * @param obj The ZoneParameters object.
    //  *
    //  * @return ptr The CalldataPointer.
    //  */
    // function toCalldataPointer(
    //     ZoneParameters calldata obj
    // ) internal pure returns (CalldataPointer ptr) {
    //     assembly {
    //         ptr := obj
    //     }
    // }
}
