// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract Trader {
    using Counters for Counters.Counter;

    /**
     * @dev TODO
     */
    event NewListing(
        uint256 listingId,
        address indexed collection,
        uint256 indexed tokenId,
        address indexed seller,
        uint256 price
    );

    /**
     * @dev TODO
     */
    event ListingCanceled(
        uint256 listingId,
        address indexed collection,
        uint256 indexed tokenId,
        address indexed seller,
        uint256 price
    );

    /**
     * @dev TODO
     */
    event ListingSale(
        uint256 listingId,
        address indexed collection,
        uint256 indexed tokenId,
        address from,
        address indexed to,
        uint256 price
    );

    struct ListingItem {
        address collection;
        uint256 tokenId;
        uint256 quantity;
        uint256 price;
        address seller;
    }

    mapping(uint256 => ListingItem) private items;

    Counters.Counter private _listingIdCounter;

    modifier onlyExistsListing(uint256 listingId) {
        require(items[listingId].seller != address(0), "Listing doesn't exists");
        _;
    }

    modifier onlySeller(uint256 listingId) {
        require(items[listingId].seller == msg.sender, "You aren't the seller");
        _;
    }

    /**
     * @dev TODO
     * TODO - update for ERC1155
     */
    function _newListing(
        address seller,
        address collection,
        uint256 tokenId,
        uint256 price
    ) internal {
        uint256 listingId = _listingIdCounter.current();
        _listingIdCounter.increment();

        items[listingId] = ListingItem({
            collection: collection,
            tokenId: tokenId,
            quantity: 1,
            price: price,
            seller: seller
        });
        emit NewListing(listingId, collection, tokenId, seller, price);
    }

    /**
     * @dev TODO
     * TODO - update to erc1155
     */
    function cancelListing(
        uint256 listingId
    ) external onlyExistsListing(listingId) onlySeller(listingId) {
        ListingItem memory item = items[listingId];

        delete items[listingId];

        IERC721 erc721 = IERC721(item.collection);
        erc721.transferFrom(address(this), item.seller, item.tokenId);

        emit ListingCanceled(listingId, item.collection, item.tokenId, item.seller, item.price);
    }

    /**
     * @dev TODO
     */
    function buy(uint256 listingId) external payable onlyExistsListing(listingId) {
        ListingItem memory item = items[listingId];
        require(msg.value == item.price, "You didn't provide the correct price");

        delete items[listingId];

        IERC721 erc721 = IERC721(item.collection);
        erc721.transferFrom(address(this), msg.sender, item.tokenId);
        payable(item.seller).transfer(msg.value);

        emit ListingSale(
            listingId,
            item.collection,
            item.tokenId,
            item.seller,
            msg.sender,
            msg.value
        );
    }

    /**
     * @dev TODO
     */
    function getListing(
        uint256 listingId
    ) public view onlyExistsListing(listingId) returns (ListingItem memory) {
        return items[listingId];
    }
}
