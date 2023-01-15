// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./Trader.sol";

contract Marketplace is IERC721Receiver, Trader {
    enum ERC721ReceivedActionType {
        Listing
    }

    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        ERC721ReceivedActionType action = ERC721ReceivedActionType(abi.decode(data[:32], (uint8)));

        if (action == ERC721ReceivedActionType.Listing) {
            uint256 value = abi.decode(data[32:], (uint256));
            _newListing(from, msg.sender, tokenId, value);
        }

        return this.onERC721Received.selector;
    }
}
