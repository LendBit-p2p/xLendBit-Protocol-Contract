// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Getters
 * @author LendBit Finance
 *
 * Public read-only functions that allow transparency into the state of LendBit
 */

contract Getters {
    /**
     * @notice This gets the USD value of amount of the token passsed.
     * @dev This uses chainlinks AggregatorV3Interface to get the price with the pricefeed address.
     *
     * @param _token a collateral token address that is allowed in our Smart Contract
     * @param _amount the amount of that token you want to get the USD equivalent of.
     *
     * @return _value returns the equivalent amount in USD.
     */
    function getUsdValue(
        address _token,
        uint256 _amount,
        uint8 _decimal
    ) public view returns (uint256 _value) {}

    /**
     * @notice Calculates The value of converting one token to another using current market price e.g ETH -> USDC
     *
     * @param _from the address of the token you are trying to convert.
     * @param _to the address of the token you are converting to.
     * @param _amount the amount of `_from` tokens you are trying to convert.
     *
     * @return _value the amount of `_to` tokens you are expected to get
     */
    function getConvertValue(
        address _from,
        address _to,
        uint256 _amount
    ) public view returns (uint256 _value) {}

    /**
     * @notice This gets the amount of collateral a user has deposited in USD
     *
     * @param _user the address of the user you want to get their collateral value
     *
     * @return _totalCollateralValueInUsd returns the value of the user deposited collateral in USD
     */
    function getAccountCollateralValue(
        address _user
    ) public view returns (uint256 _totalCollateralValueInUsd) {}
}
