// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.9;
import "./Error.sol";
import "../constants/Constant.sol";

library Validator {
    function _moreThanZero(uint256 _amount) internal pure {
        if (_amount <= 0) {
            revert Protocol__MustBeMoreThanZero();
        }
    }

    function _isTokenAllowed(
        address _priceFeeds
    ) internal pure returns (bool _isAllowed) {
        if (_priceFeeds == address(0)) {
            revert Protocol__TokenNotAllowed();
        }
        _isAllowed = true;
    }

    function _nativeMoreThanZero(address _token, uint256 _value) internal pure {
        if (_token == Constants.NATIVE_TOKEN && _value <= 0) {
            revert Protocol__MustBeMoreThanZero();
        }
    }

    function _onlyBot(address _botAddress, address _sender) internal pure {
        if (_botAddress != _sender) {
            revert Protocol__OnlyBotCanAccess();
        }
    }

    function _valueMoreThanZero(
        uint256 _amount,
        address _token,
        uint256 _value
    ) internal pure {
        if (_amount < 1) {
            revert Protocol__MustBeMoreThanZero();
        }
        if (_token == Constants.NATIVE_TOKEN && _value < 1) {
            revert Protocol__MustBeMoreThanZero();
        }
    }
}
