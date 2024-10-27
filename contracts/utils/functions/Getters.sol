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

    /**
     * @notice This gets the amount of available balance a user has in USD
     *
     * @param _user the address of the user you want to get their available balance value
     *
     * @return _totalAvailableValueInUsd returns the value of the user available balance in USD
     */
    function getAccountAvailableValue(
        address _user
    ) public view returns (uint256 _totalAvailableValueInUsd) {}

    /**
     * @notice Retrieves the details of a specific loan listing by its ID
     * @dev Returns the listing if it exists, otherwise reverts if the listing's author is the zero address
     *
     * @param _listingId The ID of the listing to retrieve
     *
     * @return The `LoanListing` struct containing details of the specified listing
     */
    function getLoanListing(
        uint96 _listingId
    ) external view returns (LoanListing memory) {}

    /**
     * @notice Retrieves the details of a specific request by its ID
     * @dev Returns the request if it exists, otherwise reverts if the request's author is the zero address
     *
     * @param _requestId The ID of the request to retrieve
     *
     * @return The `Request` struct containing details of the specified request
     */
    function getRequest(
        uint96 _requestId
    ) external view returns (Request memory) {}

    /**
     * @notice Checks the health Factor which is a way to check if the user has enough collateral
     *
     * @param _user a parameter for the address to check
     *
     * @return _value the health factor which is supoose to be >= 1
     */
    function getHealthFactor(
        address _user
    ) external view returns (uint256 _value) {}

    /**
     * @notice Gets the collection of all collateral token
     *
     * @return _tokens the collection of collateral addresses
     */
    function getAllCollateralToken()
        external
        view
        returns (address[] memory _tokens)
    {}
}
