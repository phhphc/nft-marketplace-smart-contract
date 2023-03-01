// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {OrderParameters} from "./TraderStructs.sol";

import {GettersAndDerivers} from "./GettersAndDerivers.sol";

import {TokenTransferrerErrors} from "../interfaces/TokenTransferrerErrors.sol";

import {CounterManager} from "./CounterManager.sol";

import {
    Error_selector_offset,
    MissingItemAmount_error_length,
    MissingItemAmount_error_selector
} from "./ConsiderationErrorConstants.sol";

import {
    _revertInvalidBasicOrderParameterEncoding,
    _revertMissingOriginalConsiderationItems
} from "./ConsiderationErrors.sol";

/**
 * @title Assertions
 * @author 0age
 * @notice Assertions contains logic for making various assertions that do not
 *         fit neatly within a dedicated semantic scope.
 */
contract Assertions is GettersAndDerivers, CounterManager, TokenTransferrerErrors {
    /**
     * @dev Internal view function to ensure that the supplied consideration
     *      array length on a given set of order parameters is not less than the
     *      original consideration array length for that order and to retrieve
     *      the current counter for a given order's offerer and zone and use it
     *      to derive the order hash.
     *
     * @param orderParameters The parameters of the order to hash.
     *
     * @return The hash.
     */
    function _assertConsiderationLengthAndGetOrderHash(
        OrderParameters memory orderParameters
    ) internal view returns (bytes32) {
        // Ensure supplied consideration array length is not less than original.
        _assertConsiderationLengthIsNotLessThanOriginalConsiderationLength(
            orderParameters.consideration.length,
            orderParameters.totalOriginalConsiderationItems
        );

        // Derive and return order hash using current counter for the offerer.
        return _deriveOrderHash(orderParameters, _getCounter(orderParameters.offerer));
    }

    /**
     * @dev Internal pure function to ensure that the supplied consideration
     *      array length for an order to be fulfilled is not less than the
     *      original consideration array length for that order.
     *
     * @param suppliedConsiderationItemTotal The number of consideration items
     *                                       supplied when fulfilling the order.
     * @param originalConsiderationItemTotal The number of consideration items
     *                                       supplied on initial order creation.
     */
    function _assertConsiderationLengthIsNotLessThanOriginalConsiderationLength(
        uint256 suppliedConsiderationItemTotal,
        uint256 originalConsiderationItemTotal
    ) internal pure {
        // Ensure supplied consideration array length is not less than original.
        if (suppliedConsiderationItemTotal < originalConsiderationItemTotal) {
            _revertMissingOriginalConsiderationItems();
        }
    }

    /**
     * @dev Internal pure function to ensure that a given item amount is not
     *      zero.
     *
     * @param amount The amount to check.
     */
    function _assertNonZeroAmount(uint256 amount) internal pure {
        assembly {
            if iszero(amount) {
                // Store left-padded selector with push4, mem[28:32] = selector
                mstore(0, MissingItemAmount_error_selector)

                // revert(abi.encodeWithSignature("MissingItemAmount()"))
                revert(Error_selector_offset, MissingItemAmount_error_length)
            }
        }
    }
}
