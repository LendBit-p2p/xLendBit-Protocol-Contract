// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

library Utils {
    /// @notice calculate percentage of a number
    /// @dev _percentage is in basis points (10000 = 100%, 100 = 1%, 1 = 0.01%)
    /// @param _number the number to calculate the percentage of
    /// @param _percentage the percentage in basis points
    /// @return the percentage of the number
    function calculatePercentage(
        uint128 _number,
        uint16 _percentage
    ) internal pure returns (uint256) {
        return (_number * _percentage) / 10000;
    }
}
