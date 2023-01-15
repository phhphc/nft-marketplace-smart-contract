// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract Trader {
    /**
     * @dev TODO
     */
    event Listing(address indexed collection, uint256 indexed tokenId, uint256 price);

    /**
     * @dev TODO
     */
    event ListingCanceled(address indexed collection, uint256 indexed tokenId);

    /**
     * @dev TODO
     */
    event Sale(
        address indexed collection,
        uint256 indexed tokenId,
        address from,
        address to,
        uint256 price
    );

    struct ListingItem {
        uint256 price;
        address seller;
    }

    mapping(address => mapping(uint256 => ListingItem)) private items;

    modifier onlyExistsListing(address collection, uint256 tokenId) {
        require(items[collection][tokenId].seller != address(0), "Listing doesn't exists");
        _;
    }

    modifier onlySeller(address collection, uint256 tokenId) {
        require(items[collection][tokenId].seller == msg.sender, "You aren't the seller");
        _;
    }

    /**
     * @dev TODO
     */
    function listing(address seller, address collection, uint256 tokenId, uint256 value) internal {
        items[collection][tokenId] = ListingItem({price: value, seller: seller});
        emit Listing(collection, tokenId, value);
    }

    /**
     * @dev TODO
     */
    function cancelListing(
        address collection,
        uint256 tokenId
    ) external onlyExistsListing(collection, tokenId) onlySeller(collection, tokenId) {
        ListingItem memory item = items[collection][tokenId];
        IERC721 erc721 = IERC721(collection);

        erc721.transferFrom(address(this), item.seller, tokenId);

        delete items[collection][tokenId];
        emit ListingCanceled(collection, tokenId);
    }

    /**
     * @dev TODO
     */
    function buy(
        address collection,
        uint256 tokenId
    ) external payable onlyExistsListing(collection, tokenId) {
        ListingItem memory item = items[collection][tokenId];
        require(msg.value == item.price, "You didn't provide the correct price");

        IERC721 erc721 = IERC721(collection);
        erc721.transferFrom(address(this), msg.sender, tokenId);
        payable(item.seller).transfer(msg.value);

        emit Sale(collection, tokenId, items[collection][tokenId].seller, msg.sender, msg.value);
    }

    /**
     * @dev TODO
     */
    function getListing(
        address collection,
        uint256 tokenId
    ) public view onlyExistsListing(collection, tokenId) returns (ListingItem memory) {
        return items[collection][tokenId];
    }
}
