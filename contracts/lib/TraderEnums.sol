// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

enum OrderType {
    // 0: no partial fills, anyone can execute
    FULL_OPEN,
    // // 1: partial fills supported, anyone can execute
    // PARTIAL_OPEN,

    // 2: no partial fills, only offerer or zone can execute
    FULL_RESTRICTED

    // // 3: partial fills supported, only offerer or zone can execute
    // PARTIAL_RESTRICTED,

    // // 4: contract order type
    // CONTRACT
}

enum ItemType {
    // 0: ETH on mainnet, MATIC on polygon, etc.
    NATIVE,
    // 1: ERC20 items (ERC777 and ERC20 analogues could also technically work)
    ERC20,
    // 2: ERC721 items
    ERC721,
    // 3: ERC1155 items
    ERC1155
}
