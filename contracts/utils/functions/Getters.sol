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
     *@param _token a collateral token address that is allowed in our Smart Contract
     *@param _amount the amount of that token you want to get the USD equivalent of.
     *
     *@return uint256 returns the equivalent amount in USD.
     */
    function getUsdValue(
        address _token,
        uint256 _amount,
        uint8 _decimal
    ) public view returns (uint256) {}
}
