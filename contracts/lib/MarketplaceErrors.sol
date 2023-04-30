// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/**
 * @dev Revert with an error when attempting to fill an order outside the
 *      specified start time and end time.
 *
 * @param startTime The time at which the order becomes active.
 * @param endTime   The time at which the order becomes inactive.
 */
error InvalidTime(uint256 startTime, uint256 endTime);

/**
 * @dev Revert with an error when attempting to fill an order that has been
 *      cancelled.
 *
 * @param orderHash The hash of the cancelled order.
 */
error OrderIsCancelled(bytes32 orderHash);

/**
 * @dev Revert with an error when attempting to fill an order that has
 *      already been fully filled.
 *
 * @param orderHash The order hash on which a fill was attempted.
 */
error OrderAlreadyFilled(bytes32 orderHash);

/**
 * @dev Revert with an error when the signer recovered by the supplied
 *      signature does not match the offerer or an allowed EIP-1271 signer
 *      as specified by the offerer in the event they are a contract.
 */
error InvalidSigner();

/**
 * @dev Revert with an error when attempting to fulfill an order where an
 *      item has unused parameters. This includes both the token and the
 *      identifier parameters for native transfers as well as the identifier
 *      parameter for ERC20 transfers. Note that the conduit does not
 *      perform this check, leaving it up to the calling channel to enforce
 *      when desired.
 */
error UnusedItemParameters();

/**
 * @dev Revert with an error when attempting to fulfill an order where an
 *      item has an amount of zero.
 */
error MissingItemAmount();

/**
 * @dev Revert with an error when an ERC20, ERC721, or ERC1155 token
 *      transfer reverts.
 *
 * @param token      The token for which the transfer was attempted.
 * @param from       The source of the attempted transfer.
 * @param to         The recipient of the attempted transfer.
 * @param identifier The identifier for the attempted transfer.
 * @param amount     The amount for the attempted transfer.
 */
error TokenTransferGenericFailure(
    address token,
    address from,
    address to,
    uint256 identifier,
    uint256 amount
);

/**
 * @dev Revert with an error when an ERC721 transfer with amount other than
 *      one is attempted.
 *
 * @param amount The amount of the ERC721 tokens to transfer.
 */
error InvalidERC721TransferAmount(uint256 amount);

/**
 * @dev Revert with an error when attempting to fulfill an order with an
 *      offer for a native token outside of matching orders.
 */
error InvalidNativeOfferItem();

/**
 * @dev Revert with an error when insufficient native tokens are supplied as
 *      part of msg.value when fulfilling orders.
 */
error InsufficientNativeTokensSupplied();

/**
 * @dev Revert with an error when attempting to cancel an order as a caller
 *      other than the indicated offerer or zone or when attempting to
 *      cancel a contract order.
 */
error CannotCancelOrder();

function _revertInvalidTime(uint256 startTime, uint256 endTime) pure {
    revert InvalidTime({startTime: startTime, endTime: endTime});
}

function _revertOrderIsCancelled(bytes32 orderHash) pure {
    revert OrderIsCancelled(orderHash);
}

function _revertOrderAlreadyFilled(bytes32 orderHash) pure {
    revert OrderAlreadyFilled(orderHash);
}

function _revertInvalidSigner() pure {
    revert InvalidSigner();
}

function _revertUnusedItemParameters() pure {
    revert UnusedItemParameters();
}

function _revertMissingItemAmount() pure {
    revert MissingItemAmount();
}

function _revertTokenTransferGenericFailure(
    address token,
    address from,
    address to,
    uint256 identifier,
    uint256 amount
) pure {
    revert TokenTransferGenericFailure(token, from, to, identifier, amount);
}

function _revertInvalidERC721TransferAmount(uint256 amount) pure {
    revert InvalidERC721TransferAmount(amount);
}

function _revertInvalidNativeOfferItem() pure {
    revert InvalidNativeOfferItem();
}

function _revertInsufficientNativeTokensSupplied() pure {
    revert InsufficientNativeTokensSupplied();
}

function _revertCannotCancelOrder() pure {
    revert CannotCancelOrder();
}
