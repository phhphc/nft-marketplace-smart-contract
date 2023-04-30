// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {ReceivedItem} from "./MarketplaceStruct.sol";
import {ItemType} from "./MarketplaceEnum.sol";
import {
    _revertUnusedItemParameters,
    _revertMissingItemAmount,
    _revertTokenTransferGenericFailure,
    _revertInvalidERC721TransferAmount
} from "./MarketplaceErrors.sol";
import "hardhat/console.sol";

contract Executor {
    /**
     * @dev Internal function to transfer a given item, either directly or via
     *      a corresponding conduit.
     *
     * @param item        The item to transfer, including an amount and a
     *                    recipient.
     * @param from        The account supplying the item.
     */
    function _transfer(ReceivedItem memory item, address from) internal {
        if (item.itemType == ItemType.NATIVE) {
            // Ensure neither the token nor the identifier parameters are set.
            if ((uint160(item.token) | item.identifier) != 0) {
                _revertUnusedItemParameters();
            }

            // transfer the native tokens to the recipient.
            _transferNativeTokens(item.recipient, item.amount);
        } else if (item.itemType == ItemType.ERC20) {
            // Ensure that no identifier is supplied.
            if (item.identifier != 0) {
                _revertUnusedItemParameters();
            }

            // Transfer ERC20 tokens from the source to the recipient.
            _transferERC20(item.token, from, item.recipient, item.amount);
        } else if (item.itemType == ItemType.ERC721) {
            // Transfer ERC721 token from the source to the recipient.
            _transferERC721(item.token, from, item.recipient, item.identifier, item.amount);
        } else {
            // Transfer ERC1155 token from the source to the recipient.
            _transferERC1155(item.token, from, item.recipient, item.identifier, item.amount);
        }
    }

    /**
     * @dev Internal function to transfer ERC1155 tokens from a given originator
     *      to a given recipient. Sufficient approvals must be set, either on
     *      the respective conduit or on this contract itself.
     *
     * @param token       The ERC1155 token to transfer.
     * @param from        The originator of the transfer.
     * @param to          The recipient of the transfer.
     * @param identifier  The id to transfer.
     * @param amount      The amount to transfer.
     */
    function _transferERC1155(
        address token,
        address from,
        address to,
        uint256 identifier,
        uint256 amount
    ) internal {
        // Ensure that the supplied amount is non-zero.
        if (amount == 0) {
            _revertMissingItemAmount();
        }

        // Perform transfer via the token contract directly.
        IERC1155(token).safeTransferFrom(from, to, identifier, amount, new bytes(0));
    }

    /**
     * @dev Internal function to transfer a single ERC721 token from a given
     *      originator to a given recipient. Sufficient approvals must be set,
     *      either on the respective conduit or on this contract itself.
     *
     * @param token       The ERC721 token to transfer.
     * @param from        The originator of the transfer.
     * @param to          The recipient of the transfer.
     * @param identifier  The tokenId to transfer (must be 1 for ERC721).
     * @param amount      The amount to transfer.
     */
    function _transferERC721(
        address token,
        address from,
        address to,
        uint256 identifier,
        uint256 amount
    ) internal {
        // Ensure that exactly one 721 item is being transferred.
        if (amount != 1) {
            _revertInvalidERC721TransferAmount(amount);
        }

        // Perform transfer via the token contract directly.
        IERC721(token).safeTransferFrom(from, to, identifier);
    }

    /**
     * @dev Internal function to transfer ERC20 tokens from a given originator
     *      to a given recipient using a given conduit if applicable. Sufficient
     *      approvals must be set on this contract or on a respective conduit.
     *
     * @param token       The ERC20 token to transfer.
     * @param from        The originator of the transfer.
     * @param to          The recipient of the transfer.
     * @param amount      The amount to transfer.
     */
    function _transferERC20(address token, address from, address to, uint256 amount) internal {
        if (amount == 0) {
            _revertMissingItemAmount();
        }
        bool success = IERC20(token).transferFrom(from, to, amount);
        if (!success) {
            _revertTokenTransferGenericFailure(token, from, to, 0, amount);
        }
    }

    /**
     * @dev Internal function to transfer Ether or other native tokens to a
     *      given recipient.
     *
     * @param to     The recipient of the transfer.
     * @param amount The amount to transfer.
     */
    function _transferNativeTokens(address payable to, uint256 amount) internal {
        if (amount == 0) {
            _revertMissingItemAmount();
        }

        to.transfer(amount);
    }
}
