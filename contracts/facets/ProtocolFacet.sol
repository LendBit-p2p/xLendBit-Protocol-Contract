// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.9;
import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Constants} from "../utils/constants/constant.sol";
import {Validator} from "../utils/validators/Validator.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../utils/validators/Error.sol";
import "../model/Event.sol";
import "../model/Protocol.sol";

/// @title ProtocolFacet Contract
/// @author Chukwuma Emmanuel(@ebukizy1).
contract ProtocolFacet {
    LibAppStorage.Layout internal _appStorage;

    //////////////////
    /// Modifiers ///
    ////////////////

    /**
     * @dev Ensures that the provided token is allowed by checking
     *  if a price feed exists for it in the protocol
     * @param _token The address of the token to be verified
     */
    modifier _isTokenAllowed(address _token) {
        if (_appStorage.s_priceFeeds[_token] == address(0)) {
            revert Protocol__TokenNotAllowed();
        }
        _;
    }

    /**
     * @dev Ensures that the provided amount is greater than zero
     * @param _amount The amount to be validated
     */
    modifier _moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert Protocol__MustBeMoreThanZero();
        }
        _;
    }

    //////////////////
    /// FUNCTIONS ///
    ////////////////

    /// @param _tokenCollateralAddress The address of the token to deposit as collateral
    /// @param _amountOfCollateral The amount of collateral to deposit
    function depositCollateral(
        address _tokenCollateralAddress,
        uint128 _amountOfCollateral
    )
        external
        _moreThanZero(_amountOfCollateral)
        _isTokenAllowed(_tokenCollateralAddress)
    {
        _appStorage.s_addressToCollateralDeposited[msg.sender][
                _tokenCollateralAddress
            ] += _amountOfCollateral;
        emit CollateralDeposited(
            msg.sender,
            _tokenCollateralAddress,
            _amountOfCollateral
        );
        bool _success = IERC20(_tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            _amountOfCollateral
        );
        if (!_success) {
            revert Protocol__TransferFailed();
        }
    }

    /**
     * @notice Creates a request for a loan
     * @param _amount The principal amount of the loan
     * @param _interest The annual interest rate of the loan (in percentage points)
     * @param _returnDate The unix timestamp by when the loan should be repaid
     * @param _loanCurrency The currency in which the loan is denominated
     * @dev This function calculates the required repayments and checks the borrower's collateral before accepting a loan request.
     */
    function createLendingRequest(
        uint128 _amount,
        uint8 _interest,
        uint256 _returnDate,
        address _loanCurrency
    ) external _moreThanZero(_amount) {
        if (!_appStorage.s_isLoanable[_loanCurrency]) {
            revert Protocol__TokenNotLoanable();
        }
        uint256 _loanUsdValue = getUsdValue(_loanCurrency, _amount);
        if (_loanUsdValue < 1) revert Protocol__InvalidAmount();

        uint256 collateralValueInLoanCurrency = getAccountCollateralValue(
            msg.sender
        );
        uint256 maxLoanableAmount = (collateralValueInLoanCurrency *
            Constants.COLLATERALIZATION_RATIO) / 100;

        if (
            _appStorage.addressToUser[msg.sender].totalLoanCollected +
                _loanUsdValue >=
            maxLoanableAmount
        ) {
            revert Protocol__InsufficientCollateral();
        }
        //
        _appStorage.requestId = _appStorage.requestId + 1;
        Request storage _newRequest = _appStorage.request[
            _appStorage.requestId
        ];
        _newRequest.requestId = _appStorage.requestId;
        _newRequest.author = msg.sender;
        _newRequest.amount = _amount;
        _newRequest.interest = _interest;
        _newRequest.returnDate = _returnDate;
        _newRequest.totalRepayment = _calculateLoanInterest(
            _returnDate,
            _amount,
            _interest,
            _loanCurrency
        );
        _newRequest.loanRequestAddr = _loanCurrency;
        _newRequest.status = Status.OPEN;
        _appStorage.s_requests.push(_newRequest);

        emit RequestCreated(
            msg.sender,
            _appStorage.requestId,
            _amount,
            _interest
        );
    }



    /// @notice Directly services a lending request by transferring funds to the borrower
    /// @param _requestId Identifier of the request being serviced
    /// @param _tokenAddress Token in which the funds are being transferred
    function serviceRequest(uint8 _requestId, address _tokenAddress) external {
        Request storage _foundRequest = _appStorage.request[_requestId];

        if (_foundRequest.status != Status.OPEN)
            revert Protocol__RequestNotOpen();
        if (_foundRequest.loanRequestAddr != _tokenAddress)
            revert Protocol__InvalidToken();

        _foundRequest.lender = msg.sender;
        _foundRequest.status = Status.SERVICED;
        uint128 amountToLend = _foundRequest.amount;

        // Check if the lender has enough balance and the allowance to transfer the tokens
        if (IERC20(_tokenAddress).balanceOf(msg.sender) < amountToLend)
            revert Protocol__InsufficientBalance();
        if (
            IERC20(_tokenAddress).allowance(msg.sender, address(this)) <
            amountToLend
        ) revert Protocol__InsufficientAllowance();

        uint256 _loanUsdValue = getUsdValue(_tokenAddress, amountToLend);

        uint256 _totalRepayment = _loanUsdValue +
            _calculateLoanInterest(
                _foundRequest.returnDate,
                _foundRequest.amount,
                _foundRequest.interest,
                _foundRequest.loanRequestAddr
            );
        _foundRequest.totalRepayment = _totalRepayment;
        _appStorage
            .addressToUser[_foundRequest.author]
            .totalLoanCollected += _totalRepayment;

        if (_healthFactor(_foundRequest.author) < 1) {
            revert Protocol__InsufficientCollateral();
        }

        // Transfer the funds from the lender to the borrower
        bool success = IERC20(_tokenAddress).transferFrom(
            msg.sender,
            _foundRequest.author,
            amountToLend
        );
        require(success, "Protocol__TransferFailed");

        // Update the request's status to serviced
        _foundRequest.status = Status.SERVICED;

        // Emit a success event with relevant details
        emit ServiceRequestSuccessful(
            msg.sender,
            _foundRequest.author,
            _requestId,
            amountToLend
        );
    }



    /// @notice Withdraws collateral from the protocol
    /// @param _tokenCollateralAddress Address of the collateral token
    /// @param _amount Amount of collateral to withdraw
    function withdrawCollateral(
        address _tokenCollateralAddress,
        uint128 _amount
    ) external _isTokenAllowed(_tokenCollateralAddress) _moreThanZero(_amount) {
        uint256 depositedAmount = _appStorage.s_addressToCollateralDeposited[
            msg.sender
        ][_tokenCollateralAddress];
        if (depositedAmount < _amount) {
            revert Protocol__InsufficientCollateralDeposited();
        }

        _appStorage.s_addressToCollateralDeposited[msg.sender][
            _tokenCollateralAddress
        ] -= _amount;

        // Check if remaining collateral still covers all loan obligations
        _revertIfHealthFactorIsBroken(msg.sender);

        bool success = IERC20(_tokenCollateralAddress).transfer(
            msg.sender,
            _amount
        );
        require(success, "Protocol__TransferFailed");

        emit CollateralWithdrawn(msg.sender, _tokenCollateralAddress, _amount);
    }



    /// @notice Adds new collateral tokens to the protocol
    /// @param _tokens Array of new collateral token addresses
    /// @param _priceFeeds Array of price feed addresses for the new collateral tokens
    function addCollateralTokens(
        address[] memory _tokens,
        address[] memory _priceFeeds
    ) external {
        LibDiamond.enforceIsContractOwner();

        if (_tokens.length != _priceFeeds.length) {
            revert Protocol__tokensAndPriceFeedsArrayMustBeSameLength();
        }
        for (uint8 i = 0; i < _tokens.length; i++) {
            _appStorage.s_priceFeeds[_tokens[i]] = _priceFeeds[i];
            _appStorage.s_collateralToken.push(_tokens[i]);
        }
        emit UpdatedCollateralTokens(
            msg.sender,
            uint8(_appStorage.s_collateralToken.length)
        );
    }



    /// @notice Removes collateral tokens from the protocol
    /// @param _tokens Array of collateral token addresses to remove
    function removeCollateralTokens(address[] memory _tokens) external {
        LibDiamond.enforceIsContractOwner();

        for (uint8 i = 0; i < _tokens.length; i++) {
            _appStorage.s_priceFeeds[_tokens[i]] = address(0);
            for (uint8 j = 0; j < _appStorage.s_collateralToken.length; j++) {
                if (_appStorage.s_collateralToken[j] == _tokens[i]) {
                    _appStorage.s_collateralToken[j] = _appStorage
                        .s_collateralToken[
                            _appStorage.s_collateralToken.length - 1
                        ];
                    _appStorage.s_collateralToken.pop();
                }
            }
        }
        emit UpdatedCollateralTokens(
            msg.sender,
            uint8(_appStorage.s_collateralToken.length)
        );
    }



    /// @dev For adding more tokens that are loanable on the platform
    /// @param _token the address of the token you want to be loanable on the protocol
    /// @param _priceFeed the address of the currency pair on chainlink
    function addLoanableToken(address _token, address _priceFeed) external {
        LibDiamond.enforceIsContractOwner();
        _appStorage.s_isLoanable[_token] = true;
        _appStorage.s_priceFeeds[_token] = _priceFeed;
        _appStorage.s_loanableToken.push(_token);
        emit UpdateLoanableToken(_token, _priceFeed, msg.sender);
    }



    /// @dev for upating git coin post score
    /// @param _user the address to the user you want to update
    /// @param _score the gitcoin point score.
    function updateGPScore(address _user, uint256 _score) public {
        LibDiamond.enforceIsContractOwner();
        _appStorage.addressToUser[_user].gitCoinPoint = _score;
    }


    /**
     * @notice Creates a new ad listing for a loan with specified parameters
     * @dev The function checks the loan currency's eligibility,
     * @param _amount The amount of the loan to be listed
     * @param _interest The interest rate applied to the loan
     * @param _returnDate The date by which the loan must be returned
     * @param _loanCurrency The token address for the loan currency
     */
    function createListingAds(
        uint128 _amount,
        uint8 _interest,
        uint256 _returnDate,
        address _loanCurrency
    ) external {
        if (!_appStorage.s_isLoanable[_loanCurrency]) {
            revert Protocol__TokenNotLoanable();
        }

        if (IERC20(_loanCurrency).balanceOf(msg.sender) < _amount)
            revert Protocol__InsufficientBalance();

        if (
            IERC20(_loanCurrency).allowance(msg.sender, address(this)) < _amount
        ) revert Protocol__InsufficientAllowance();

        bool success = IERC20(_loanCurrency).transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        require(success, "Protocol__TransferFailed");

        _appStorage.s_orderId = _appStorage.s_orderId + 1;
        Order storage _newOrder = _appStorage.order[_appStorage.s_orderId];
        _newOrder.orderId = _appStorage.s_orderId;
        _newOrder.author = msg.sender;
        _newOrder.amount = _amount;
        _newOrder.interest = _interest;
        _newOrder.returnDate = _returnDate;
        _newOrder.totalRepayment = _calculateLoanInterest(
            _returnDate,
            _amount,
            _interest,
            _loanCurrency
        );
        _newOrder.loanAddress = _loanCurrency;
        _newOrder.orderStatus = OrderStatus.OPEN;
        _appStorage.s_order.push(_newOrder);

        emit OrderCreated(
            msg.sender,
            _loanCurrency,
            _amount,
            _appStorage.s_orderId
        );
    }



    /**
     * @notice Allows a user to withdraw the deposited ads token for a specific order
     * @dev Withdraws the ads token associated with an open order, closes the order, and emits an event
     * @param _orderId The ID of the order to withdraw the token from
     */
    function withdrawnDepositedAdsToken(uint96 _orderId) external {
        Order storage _newOrder = _appStorage.order[_orderId];
        if (_newOrder.orderStatus != OrderStatus.OPEN)
            revert Protocol__OrderNotOpen();
        if (_newOrder.author != msg.sender)
            revert Protocol__OwnerCreatedOrder();
        if (_newOrder.amount <= 0) revert Protocol__MustBeMoreThanZero();

        uint128 _amount = _newOrder.amount;
        _newOrder.amount = 0;
        _newOrder.orderStatus = OrderStatus.CLOSED;

        bool success = IERC20(_newOrder.loanAddress).transfer(
            msg.sender,
            _amount
        );
        require(success, "Protocol__TransferFailed");

        emit withdrawnAdsToken(
            msg.sender,
            _orderId,
            uint8(_newOrder.orderStatus),
            _amount
        );
    }



    /**
     * @notice Accepts a listed ad order and processes the loan transfer to the borrower
     * @dev Accepts the listed ad, calculates the total repayment with interest,
     *  checks the borrower's health factor, and transfers the loan amount.
     *  Emits an event when the ad is accepted.
     * @param _orderId The ID of the ad order to be accepted
     */
    function acceptListedAds(uint96 _orderId) external {
        Order storage _newOrder = _appStorage.order[_orderId];
        if (_newOrder.orderStatus != OrderStatus.OPEN)
            revert Protocol__OrderNotOpen();
        if (_newOrder.author == msg.sender)
            revert Protocol__OwnerCreatedOrder();

        uint256 _loanUsdValue = getUsdValue(
            _newOrder.loanAddress,
            _newOrder.amount
        );

        uint256 _totalRepayment = _loanUsdValue +
            _calculateLoanInterest(
                _newOrder.returnDate,
                _newOrder.amount,
                _newOrder.interest,
                _newOrder.loanAddress
            );
        _newOrder.totalRepayment = _totalRepayment;
        _appStorage
            .addressToUser[msg.sender]
            .totalLoanCollected += _totalRepayment;

        if (_healthFactor(msg.sender) < 1) {
            revert Protocol__InsufficientCollateral();
        }
        _newOrder.orderStatus = OrderStatus.ACCEPTED;

        bool success = IERC20(_newOrder.loanAddress).transfer(
            msg.sender,
            _newOrder.amount
        );

        require(success, "Protocol__TransferFailed");

        emit AcceptedListedAds(
            msg.sender,
            _orderId,
            _newOrder.amount,
            uint8(_newOrder.orderStatus)
        );
    }



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
        uint128 _amount
    ) public view returns (uint256) {
        AggregatorV3Interface _priceFeed = AggregatorV3Interface(
            _appStorage.s_priceFeeds[_token]
        );
        (, int256 _price, , , ) = _priceFeed.latestRoundData();
        return
            ((uint256(_price) * Constants.NEW_PRECISION) * _amount) /
            Constants.PRECISION;
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
            uint128 _amount = _appStorage.s_addressToCollateralDeposited[_user][
                _token
            ];
            _totalCollateralValueInUsd += getUsdValue(_token, _amount);
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
     * @notice Retrieves all listed orders stored in the system
     * @dev Returns an array of all orders
     * @return An array of `Order` structs representing all listed orders
     */
    function getAllListedOrders() external view returns (Order[] memory) {
        return _appStorage.s_order;
    }



    /**
     * @notice Retrieves the details of a specific order by its ID
     * @dev Returns the order if it exists, otherwise reverts if the order's author is the zero address
     * @param _orderId The ID of the order to retrieve
     * @return The `Order` struct containing details of the specified order
     */
    function getOrder(uint96 _orderId) external view returns (Order memory) {
        Order memory _order = _appStorage.order[_orderId];
        if (_order.author == address(0)) revert Protocol__NotOwner();
        return _order;
    }



    /**
     * @notice Retrieves the details of a specific request by its ID
     * @dev Returns the request if it exists, otherwise reverts if the request's author is the zero address
     * @param _requestId The ID of the request to retrieve
     * @return The `Request` struct containing details of the specified request
     */
    function getRquest(
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
        _totalBurrowInUsd = _appStorage.addressToUser[_user].totalLoanCollected;
        _collateralValueInUsd = getAccountCollateralValue(_user);
    }



    /// @notice Checks the health Factor which is a way to check if the user has enough collateral to mint
    /// @param _user a parameter for the address to check
    /// @return uint256 returns the health factor which is supoose to be >= 1
    function _healthFactor(address _user) private view returns (uint256) {
        (
            uint256 _totalBurrowInUsd,
            uint256 _collateralValueInUsd
        ) = _getAccountInfo(_user);
        uint256 _collateralAdjustedForThreshold = (_collateralValueInUsd *
            Constants.LIQUIDATION_THRESHOLD) / 100;
        return
            (_collateralAdjustedForThreshold * Constants.PRECISION) /
            _totalBurrowInUsd;
    }



    /// @dev get the collection of all collateral token
    /// @return {address[] memory} the collection of collateral addresses
    function getAllCollateralToken() external view returns (address[] memory) {
        return _appStorage.s_collateralToken;
    }



    /// @notice This checks the health factor to see if  it is broken if it is it reverts
    /// @param _user a parameter for the address we want to check the health factor for
    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 _userHealthFactor = _healthFactor(_user);
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



    /// @dev calculates the loan interest and add it to the loam
    /// @param _returnDate the date at which the loan should be returned
    /// @param _amount the amount the user want to borrow
    /// @param _interest the percentage the user has agreed to payback
    /// @param _token the token the user want to borrow
    /// @return _totalRepayment the amount the user is to payback
    function _calculateLoanInterest(
        uint256 _returnDate,
        uint128 _amount,
        uint8 _interest,
        address _token
    ) internal view returns (uint256 _totalRepayment) {
        if (_returnDate < block.timestamp)
            revert Protocol__DateMustBeInFuture();
        // usd value
        uint256 amountInUsd = getUsdValue(_token, _amount);
        // Calculate the total repayment amount including interest
        _totalRepayment = (amountInUsd * _interest) / 100;
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
}