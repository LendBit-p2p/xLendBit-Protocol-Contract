// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.9;
import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Constants} from "../utils/constants/Constant.sol";
import {Validator} from "../utils/validators/Validator.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../utils/validators/Error.sol";
import {Operations} from "../utils/functions/Operations.sol";
import "../model/Event.sol";
import "../model/Protocol.sol";
import "../interfaces/IUniswapV2Router02.sol";

import "../utils/functions/Utils.sol";

/// @title ProtocolFacet Contract
/// @author Chukwuma Emmanuel(@ebukizy1). Favour Aniogor (@SuperDevFavour)
contract ProtocolFacet is Operations {
    ///////////////////////
    /// VIEW FUNCTIONS ///
    //////////////////////

    /// @notice This gets the USD value of amount of the token passsed.
    /// @dev This uses chainlinks AggregatorV3Interface to get the price with the pricefeed address.
    /// @param _token a collateral token address that is allowed in our Smart Contract
    /// @param _amount the amount of that token you want to get the USD equivalent of.
    /// @return uint256 returns the equivalent amount in USD.
    function getUsdValue(
        address _token,
        uint256 _amount,
        uint8 _decimal
    ) public view returns (uint256) {
        AggregatorV3Interface _priceFeed = AggregatorV3Interface(
            _appStorage.s_priceFeeds[_token]
        );
        (, int256 _price, , , ) = _priceFeed.latestRoundData();
        return
            ((uint256(_price) * Constants.NEW_PRECISION) * (_amount)) /
            ((10 ** _decimal));
    }

    ///@notice get the expected amount in converting tokens
    function getConvertValue(
        address _from,
        address _to,
        uint256 _amount
    ) public view returns (uint256 value) {
        uint8 fromDecimal = _getTokenDecimal(_from);
        uint8 toDecimal = _getTokenDecimal(_to);
        uint256 fromUsd = getUsdValue(_from, _amount, fromDecimal);
        value = (((fromUsd * 10) / getUsdValue(_to, 10, 0)) *
            (10 ** toDecimal));
    }

    /// @notice This gets the amount of collateral a user has deposited in USD
    /// @param _user the address who you want to get their collateral value
    /// @return _totalCollateralValueInUsd returns the value of the user deposited collateral in USD
    function getAccountCollateralValue(
        address _user
    ) public view returns (uint256 _totalCollateralValueInUsd) {
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
            _totalCollateralValueInUsd += getUsdValue(
                _token,
                _amount,
                _tokenDecimal
            );
        }
    }

    function getAccountAvailableValue(
        address _user
    ) public view returns (uint256 _totalAvailableValueInUsd) {
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
            _totalAvailableValueInUsd += getUsdValue(
                _token,
                _amount,
                _tokenDecimal
            );
        }
    }

    /**
     * @notice Retrieves all the requests stored in the system
     * @dev Returns an array of all requests
     * @return An array of `Request` structs representing all stored requests
     */
    function getAllRequest() external view returns (Request[] memory) {
        return _appStorage.s_requests;
    }

    /**
     * @notice Retrieves the details of a specific loan listing by its ID
     * @dev Returns the listing if it exists, otherwise reverts if the listing's author is the zero address
     * @param _listingId The ID of the listing to retrieve
     * @return The `LoanListing` struct containing details of the specified listing
     */
    function getLoanListing(
        uint96 _listingId
    ) external view returns (LoanListing memory) {
        LoanListing memory _listing = _appStorage.loanListings[_listingId];
        if (_listing.author == address(0)) revert Protocol__IdNotExist();
        return _listing;
    }

    /**
     * @notice Retrieves the details of a specific request by its ID
     * @dev Returns the request if it exists, otherwise reverts if the request's author is the zero address
     * @param _requestId The ID of the request to retrieve
     * @return The `Request` struct containing details of the specified request
     */
    function getRequest(
        uint96 _requestId
    ) external view returns (Request memory) {
        Request memory _request = _appStorage.request[_requestId];
        if (_request.author == address(0)) revert Protocol__NotOwner();
        return _request;
    }

    /// @notice This gets the account info of any account
    /// @param _user a parameter for the user account info you want to get
    /// @return _totalBurrowInUsd returns the total amount of SC the  user has minted
    /// @return _collateralValueInUsd returns the total collateral the user has deposited in USD
    function _getAccountInfo(
        address _user
    )
        private
        view
        returns (uint256 _totalBurrowInUsd, uint256 _collateralValueInUsd)
    {
        _totalBurrowInUsd = getLoanCollectedInUsd(_user);
        _collateralValueInUsd = getAccountCollateralValue(_user);
    }

    /// @notice Checks the health Factor which is a way to check if the user has enough collateral
    /// @param _user a parameter for the address to check
    /// @return uint256 returns the health factor which is supoose to be >= 1
    function getHealthFactor(address _user) external view returns (uint256) {
        return _healthFactor(_user, 0);
    }

    /// @notice Checks the health Factor which is a way to check if the user has enough collateral to mint
    /// @param _user a parameter for the address to check
    /// @param _borrow_Value amount the user wants to borrow in usd
    /// @return uint256 returns the health factor which is supoose to be >= 1
    function _healthFactor(
        address _user,
        uint256 _borrow_Value
    ) private view returns (uint256) {
        (
            uint256 _totalBurrowInUsd,
            uint256 _collateralValueInUsd
        ) = _getAccountInfo(_user);
        uint256 _collateralAdjustedForThreshold = (_collateralValueInUsd *
            Constants.LIQUIDATION_THRESHOLD) / 100;

        if ((_totalBurrowInUsd == 0) && (_borrow_Value == 0))
            return (_collateralAdjustedForThreshold * Constants.PRECISION);

        return
            (_collateralAdjustedForThreshold * Constants.PRECISION) /
            (_totalBurrowInUsd + _borrow_Value);
    }

    function _getTokenDecimal(
        address _token
    ) internal view returns (uint8 decimal) {
        if (_token == Constants.NATIVE_TOKEN) {
            decimal = 18;
        } else {
            decimal = ERC20(_token).decimals();
        }
    }

    /// @dev get the collection of all collateral token
    /// @return {address[] memory} the collection of collateral addresses
    function getAllCollateralToken() external view returns (address[] memory) {
        return _appStorage.s_collateralToken;
    }

    /// @notice This checks the health factor to see if  it is broken if it is it reverts
    /// @param _user a parameter for the address we want to check the health factor for
    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 _userHealthFactor = _healthFactor(_user, 0);
        if (_userHealthFactor < Constants.MIN_HEALTH_FACTOR) {
            revert Protocol__BreaksHealthFactor();
        }
    }

    /// @dev gets the amount of collateral auser has deposited
    /// @param _sender the user who has the collateral
    /// @param _tokenAddr the user who has the collateral
    /// @return {uint256} the return variables of a contract’s function state variable
    function gets_addressToCollateralDeposited(
        address _sender,
        address _tokenAddr
    ) external view returns (uint256) {
        return _appStorage.s_addressToCollateralDeposited[_sender][_tokenAddr];
    }

    /// @dev gets the amount of token balance avialble to the user
    /// @param _sender the user who has the balance
    /// @param _tokenAddr the user who has the balance
    /// @return {uint256} the return variables of a contract’s function state variable
    function gets_addressToAvailableBalance(
        address _sender,
        address _tokenAddr
    ) external view returns (uint256) {
        return _appStorage.s_addressToAvailableBalance[_sender][_tokenAddr];
    }

    function getRequestToColateral(
        uint96 _requestId,
        address _token
    ) external view returns (uint256) {
        return _appStorage.s_idToCollateralTokenAmount[_requestId][_token];
    }

    /// @dev calculates the loan interest and add it to the loam
    /// @param _returnDate the date at which the loan should be returned
    /// @param _amount the amount the user want to borrow
    /// @param _interest the percentage the user has agreed to payback
    /// @return _totalRepayment the amount the user is to payback
    function _calculateLoanInterest(
        uint256 _returnDate,
        uint256 _amount,
        uint16 _interest
    ) internal view returns (uint256 _totalRepayment) {
        if (_returnDate < block.timestamp)
            revert Protocol__DateMustBeInFuture();
        // Calculate the total repayment amount including interest
        _totalRepayment =
            _amount +
            Utils.calculatePercentage(_amount, _interest);
        return _totalRepayment;
    }

    /// @dev for getting the gitcoinpoint score
    /// @param _user the address of you wan to check the score for.
    /// @return _score the user scors.
    function get_gitCoinPoint(
        address _user
    ) external view returns (uint256 _score) {
        LibDiamond.enforceIsContractOwner();
        _score = _appStorage.addressToUser[_user].gitCoinPoint;
    }

    /// @return _assets the collection of token that can be loaned in the protocol
    function getLoanableAssets()
        external
        view
        returns (address[] memory _assets)
    {
        _assets = _appStorage.s_loanableToken;
    }

    /// @dev gets a request from a user
    /// @param _user the addresss of the user
    /// @param _requestId the id of the request that was created by the user
    /// @return Documents the return variables of a contract’s function state variable
    function getUserRequest(
        address _user,
        uint96 _requestId
    ) external view returns (Request memory) {
        Request memory _request = _appStorage.request[_requestId];
        if (_request.author != _user) revert Protocol__NotOwner();
        return _request;
    }

    function getUserActiveRequests(
        address _user
    ) public view returns (Request[] memory _requests) {
        Request[] memory requests = _appStorage.s_requests;
        uint64 requestLength;
        for (uint i = 0; i < requests.length; i++) {
            if (
                requests[i].author == _user &&
                requests[i].status == Status.SERVICED
            ) {
                requestLength++;
            }
        }

        _requests = new Request[](requestLength);

        for (uint i = 0; i < requests.length; i++) {
            if (
                requests[i].author == _user &&
                requests[i].status == Status.SERVICED
            ) {
                _requests[requestLength - 1] = requests[i];
                requestLength--;
            }
        }
    }

    function getServicedRequestByLender(
        address _lender
    ) public view returns (Request[] memory _requests) {
        Request[] memory requests = _appStorage.s_requests;
        uint64 requestLength;
        for (uint i = 0; i < requests.length; i++) {
            if (requests[i].lender == _lender) {
                requestLength++;
            }
        }

        _requests = new Request[](requestLength);

        for (uint i = 0; i < requests.length; i++) {
            if (requests[i].lender == _lender) {
                _requests[requestLength - 1] = requests[i];
                requestLength--;
            }
        }
    }

    function getLoanCollectedInUsd(
        address _user
    ) public view returns (uint256 _value) {
        Request[] memory userActiveRequest = getUserActiveRequests(_user);
        uint256 loans = 0;
        for (uint i = 0; i < userActiveRequest.length; i++) {
            uint8 tokenDecimal = _getTokenDecimal(
                userActiveRequest[i].loanRequestAddr
            );
            loans += getUsdValue(
                userActiveRequest[i].loanRequestAddr,
                userActiveRequest[i].totalRepayment,
                tokenDecimal
            );
        }
        _value = loans;
    }

    function getUserCollateralTokens(
        address _user
    ) public view returns (address[] memory _collaterals) {
        address[] memory tokens = _appStorage.s_collateralToken;
        uint8 userLength = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (_appStorage.s_addressToAvailableBalance[_user][tokens[i]] > 0) {
                userLength++;
            }
        }

        address[] memory userTokens = new address[](userLength);

        for (uint256 i = 0; i < tokens.length; i++) {
            if (
                _appStorage.s_addressToCollateralDeposited[_user][tokens[i]] > 0
            ) {
                userTokens[userLength - 1] = tokens[i];
                userLength--;
            }
        }

        return userTokens;
    }
    fallback() external {
        revert("ProtocolFacet: fallback");
    }
}
