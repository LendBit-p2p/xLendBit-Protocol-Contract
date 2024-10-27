// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {LibAppStorage} from "./LibAppStorage.sol";
import {Constants} from "../utils/constants/constant.sol";

library LibGettersImpl {
    /**
     * @dev This uses chainlinks AggregatorV3Interface to get the price with the pricefeed address.
     *
     * @param _token a collateral token address that is allowed in our Smart Contract
     * @param _amount the amount of that token you want to get the USD equivalent of.
     *
     * @return {uint256} returns the equivalent amount in USD.
     */
    function _getUsdValue(
        address _token,
        uint256 _amount,
        uint8 _decimal
    ) internal view returns (uint256) {
        AggregatorV3Interface _priceFeed = AggregatorV3Interface(
            _appStorage.s_priceFeeds[_token]
        );
        (, int256 _price, , , ) = _priceFeed.latestRoundData();
        return
            ((uint256(_price) * Constants.NEW_PRECISION) * (_amount)) /
            ((10 ** _decimal));
    }

    /**
     * @dev This uses chainlink pricefeed underneth to get the prices and the ERC20 Standard to get the decimals for each Token.
     *
     * @param _from the address of the token you are trying to convert.
     * @param _to the address of the token you are converting to.
     * @param _amount the amount of `_from` tokens you are trying to convert.
     *
     * @return value the amount of `_to` tokens you are expected to get
     */
    function _getConvertValue(
        address _from,
        address _to,
        uint256 _amount
    ) internal view returns (uint256 value) {
        uint8 fromDecimal = _getTokenDecimal(_from);
        uint8 toDecimal = _getTokenDecimal(_to);
        uint256 fromUsd = _getUsdValue(_from, _amount, fromDecimal);
        value = (((fromUsd * 10) / _getUsdValue(_to, 10, 0)) *
            (10 ** toDecimal));
    }

    /**
     * @dev This uses Chainlink pricefeed and ERC20 Standard in getting the Token/USD price and Token decimals.
     *
     * @param _appStorage The storage Layout of the contract.
     * @param _user The address of the user you want to get their collateral value.
     *
     * @return _totalCollateralValueInUsd returns the value of the user deposited collateral in USD.
     */
    function _getAccountCollateralValue(
        LibAppStorage.Layout storage _appStorage,
        address _user
    ) internal view returns (uint256 _totalCollateralValueInUsd) {
        for (
            uint256 index = 0;
            index < _appStorage.s_collateralToken.length;
            index++
        ) {
            address _token = _appStorage.s_collateralToken[index];
            uint256 _amount = _appStorage.s_addressToCollateralDeposited[_user][
                _token
            ];
            uint8 _tokenDecimal = _getTokenDecimal(_token);
            _totalCollateralValueInUsd += _getUsdValue(
                _token,
                _amount,
                _tokenDecimal
            );
        }
    }

    /**
     * @dev This uses Chainlink pricefeed and ERC20 Standard in getting the Token/USD price and Token decimals.
     *
     * @param _appStorage The storage Layout of the contract.
     * @param _user the address of the user you want to get their available balance value
     *
     * @return _totalAvailableValueInUsd returns the value of the user available balance in USD
     */
    function _getAccountAvailableValue(
        LibAppStorage.Layout storage _appStorage,
        address _user
    ) internal view returns (uint256 _totalAvailableValueInUsd) {
        for (
            uint256 index = 0;
            index < _appStorage.s_collateralToken.length;
            index++
        ) {
            address _token = _appStorage.s_collateralToken[index];
            uint256 _amount = _appStorage.s_addressToAvailableBalance[_user][
                _token
            ];
            uint8 _tokenDecimal = _getTokenDecimal(_token);
            _totalAvailableValueInUsd += _getUsdValue(
                _token,
                _amount,
                _tokenDecimal
            );
        }
    }

    /**
     * @dev Returns the listing if it exists, otherwise reverts if the listing's author is the zero address
     *
     * @param _appStorage The storage Layout of the contract.
     * @param _listingId The ID of the listing to retrieve
     *
     * @return The `LoanListing` struct containing details of the specified listing
     */
    function _getLoanListing(
        LibAppStorage.Layout storage _appStorage,
        uint96 _listingId
    ) internal view returns (LoanListing memory) {
        LoanListing memory _listing = _appStorage.loanListings[_listingId];
        if (_listing.author == address(0)) revert Protocol__IdNotExist();
        return _listing;
    }

    /**
     * @dev Returns the request if it exists, otherwise reverts if the request's author is the zero address
     *
     * @param _appStorage The storage Layout of the contract.
     * @param _requestId The ID of the request to retrieve
     *
     * @return _request The `Request` struct containing details of the specified request
     */
    function _getRequest(
        LibAppStorage.Layout storage _appStorage,
        uint96 _requestId
    ) internal view returns (Request memory) {
        Request memory _request = _appStorage.request[_requestId];
        if (_request.author == address(0)) revert Protocol__NotOwner();
        return _request;
    }

    /**
     * @dev This gets the account info of any account.
     *
     * @param _appStorage The storage Layout of the contract.
     * @param _user a parameter for the user account info you want to get.
     *
     * @return _totalBurrowInUsd returns the total amount of SC the  user has minted.
     * @return _collateralValueInUsd returns the total collateral the user has deposited in USD.
     */
    function _getAccountInfo(
        LibAppStorage.Layout storage _appStorage,
        address _user
    )
        internal
        view
        returns (uint256 _totalBurrowInUsd, uint256 _collateralValueInUsd)
    {
        _totalBurrowInUsd = _getLoanCollectedInUsd(_appStorage, _user);
        _collateralValueInUsd = _getAccountCollateralValue(_appStorage, _user);
    }
}
