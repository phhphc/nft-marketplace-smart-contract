// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract AmountDeriver {
    /**
     * @dev Internal view function to derive the current amount of a given item
     *      based on the current price, the starting price, and the ending
     *      price. If the start and end prices differ, the current price will be
     *      interpolated on a linear basis. Note that this function expects that
     *      the startTime parameter of orderParameters is not greater than the
     *      current block timestamp and that the endTime parameter is greater
     *      than the current block timestamp. If this condition is not upheld,
     *      duration / elapsed / remaining variables will underflow.
     *
     * @param startAmount The starting amount of the item.
     * @param endAmount   The ending amount of the item.
     * @param startTime   The starting time of the order.
     * @param endTime     The end time of the order.
     * @param roundUp     A boolean indicating whether the resultant amount
     *                    should be rounded up or down.
     *
     * @return amount The current amount.
     */
    function _locateCurrentAmount(
        uint256 startAmount,
        uint256 endAmount,
        uint256 startTime,
        uint256 endTime,
        bool roundUp
    ) internal view returns (uint256 amount) {
        // Only modify end amount if it doesn't already equal start amount.
        if (startAmount != endAmount) {
            // Declare variables to derive in the subsequent unchecked scope.
            uint256 duration;
            uint256 elapsed;
            uint256 remaining;

            // Skip underflow checks as startTime <= block.timestamp < endTime.
            unchecked {
                // Derive the duration for the order and place it on the stack.
                duration = endTime - startTime;

                // Derive time elapsed since the order started & place on stack.
                elapsed = block.timestamp - startTime;

                // Derive time remaining until order expires and place on stack.
                remaining = duration - elapsed;
            }

            // Aggregate new amounts weighted by time with rounding factor.
            uint256 totalBeforeDivision = ((startAmount * remaining) + (endAmount * elapsed));

            // Use assembly to combine operations and skip divide-by-zero check.
            assembly {
                // Multiply by iszero(iszero(totalBeforeDivision)) to ensure
                // amount is set to zero if totalBeforeDivision is zero,
                // as intermediate overflow can occur if it is zero.
                amount := mul(
                    iszero(iszero(totalBeforeDivision)),
                    // Subtract 1 from the numerator and add 1 to the result if
                    // roundUp is true to get the proper rounding direction.
                    // Division is performed with no zero check as duration
                    // cannot be zero as long as startTime < endTime.
                    add(div(sub(totalBeforeDivision, roundUp), duration), roundUp)
                )
            }

            // Return the current amount.
            return amount;
        }

        // Return the original amount as startAmount == endAmount.
        return endAmount;
    }

    /**
     * @dev Internal view function to apply a fraction to a consideration
     * or offer item.
     *
     * @param startAmount     The starting amount of the item.
     * @param endAmount       The ending amount of the item.
     * @param startTime       The starting time of the order.
     * @param endTime         The end time of the order.
     * @param roundUp         A boolean indicating whether the resultant
     *                        amount should be rounded up or down.
     *
     * @return amount The received item to transfer with the final amount.
     */
    function _applyFraction(
        uint256 startAmount,
        uint256 endAmount,
        uint256 startTime,
        uint256 endTime,
        bool roundUp
    ) internal view returns (uint256 amount) {
        // If start amount equals end amount, apply fraction to end amount.
        if (startAmount == endAmount) {
            // Apply fraction to end amount.
            amount = endAmount;
        } else {
            // Otherwise, apply fraction to both and interpolated final amount.
            amount = _locateCurrentAmount(startAmount, endAmount, startTime, endTime, roundUp);
        }
    }
}
