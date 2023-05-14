// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {OrderStatus} from "./MarketplaceStruct.sol";
import {
    _revertInvalidTime,
    _revertOrderIsCancelled,
    _revertOrderAlreadyFilled,
    _revertInvalidSigner
} from "./MarketplaceErrors.sol";
import {GettersAndDerivers} from "./GettersAndDerivers.sol";

contract Verifiers is GettersAndDerivers {
    /**
     * @dev Internal view function to ensure that the current time falls within
     *      an order's valid timespan.
     *
     * @param startTime       The time at which the order becomes active.
     * @param endTime         The time at which the order becomes inactive.
     * @param revertOnInvalid A boolean indicating whether to revert if the
     *                        order is not active.
     *
     * @return valid A boolean indicating whether the order is active.
     */
    function _verifyTime(
        uint256 startTime,
        uint256 endTime,
        bool revertOnInvalid
    ) internal view returns (bool valid) {
        assembly {
            valid := and(iszero(gt(startTime, timestamp())), gt(endTime, timestamp()))
        }

        if (revertOnInvalid && !valid) {
            _revertInvalidTime(startTime, endTime);
        }
    }

    /**
     * @dev Internal view function to validate that a given order is fillable
     *      and not cancelled based on the order status.
     *
     * @param orderHash       The order hash.
     * @param orderStatus     The status of the order, including whether it has
     *                        been cancelled and the fraction filled.
     * @param revertOnInvalid A boolean indicating whether to revert if the
     *                        order has been cancelled or filled beyond the
     *                        allowable amount.
     *
     * @return valid A boolean indicating whether the order is valid.
     */
    function _verifyOrderStatus(
        bytes32 orderHash,
        OrderStatus storage orderStatus,
        bool revertOnInvalid
    ) internal view returns (bool valid) {
        // Ensure that the order has not been cancelled.
        if (orderStatus.isCancelled) {
            // Only revert if revertOnInvalid has been supplied as true.
            if (revertOnInvalid) {
                _revertOrderIsCancelled(orderHash);
            }

            // Return false as the order status is invalid.
            return false;
        }

        // Ensure that the order has not been fulfilled.
        if (orderStatus.isFulFilled) {
            // Only revert if revertOnInvalid has been supplied as true.
            if (revertOnInvalid) {
                _revertOrderAlreadyFilled(orderHash);
            }

            // Return false as the order status is invalid.
            return false;
        }

        // Return true as the order status is valid.
        valid = true;
    }

    /**
     * @dev Internal view function to verify the signature of an order. An
     *      ERC-1271 fallback will be attempted if either the signature length
     *      is not 64 or 65 bytes or if the recovered signer does not match the
     *      supplied offerer. Note that in cases where a 64 or 65 byte signature
     *      is supplied, only standard ECDSA signatures that recover to a
     *      non-zero address are supported.
     *
     * @param offerer   The offerer for the order.
     * @param orderHash The order hash.
     * @param signature A signature from the offerer indicating that the order
     *                  has been approved.
     */
    function _verifySignature(
        address offerer,
        bytes32 orderHash,
        bytes memory signature
    ) internal view {
        // Skip signature verification if the offerer is the caller.
        if (offerer == msg.sender) {
            return;
        }

        bytes32 domainSeparator = _domainSeparator();

        // Derive original EIP-712 digest using domain separator and order hash.
        bytes32 digest = _deriveEIP712Digest(domainSeparator, orderHash);

        (bytes32 r, bytes32 s, uint8 v) = _deriveSignature(signature);

        address signer = ecrecover(digest, v, r, s);
        if (signer != offerer) {
            _revertInvalidSigner();
        }
    }
}
