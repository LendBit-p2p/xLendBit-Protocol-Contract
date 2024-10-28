// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Constants} from "../constants/Constant.sol";
import "../validators/Error.sol";

library Utils {
    /// @notice calculate percentage of a number
    /// @dev _percentage is in basis points (10000 = 100%, 100 = 1%, 1 = 0.01%)
    /// @param _number the number to calculate the percentage of
    /// @param _percentage the percentage in basis points
    /// @return the percentage of the number
    function calculatePercentage(
        uint256 _number,
        uint16 _percentage
    ) internal pure returns (uint256) {
        return (_number * _percentage) / 10000;
    }

    function maxLoanableAmount(
        uint256 _collateralValueInLoanCurrency
    ) internal pure returns (uint256 _value) {
        _value =
            (_collateralValueInLoanCurrency *
                Constants.COLLATERALIZATION_RATIO) /
            100;
    }

    function calculateLoanInterest(
        uint256 _returnDate,
        uint256 _amount,
        uint16 _interest
    ) internal view returns (uint256 _totalRepayment) {
        if (_returnDate < block.timestamp)
            revert Protocol__DateMustBeInFuture();
        // Calculate the total repayment amount including interest
        _totalRepayment = _amount + calculatePercentage(_amount, _interest);
        return _totalRepayment;
    }

    function calculateColateralToLock(
        uint256 _loanUsdValue,
        uint256 _maxLoanableAmount
    ) internal pure returns (uint256 _value) {
        _value =
            (_loanUsdValue * 100 * Constants.PRECISION) /
            _maxLoanableAmount;
    }
}
