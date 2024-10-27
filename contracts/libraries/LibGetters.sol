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
}
