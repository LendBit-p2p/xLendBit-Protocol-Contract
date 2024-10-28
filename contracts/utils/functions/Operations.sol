// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibAppStorage} from "../../libraries/LibAppStorage.sol";
import {LibGettersImpl} from "../../libraries/LibGetters.sol";
import {LibDiamond} from "../../libraries/LibDiamond.sol";
import {Validator} from "../validators/Validator.sol";
import {Constants} from "../constants/Constant.sol";
import {Utils} from "./Utils.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../model/Protocol.sol";
import "../../model/Event.sol";
import "../validators/Error.sol";

/**
 * @title Operations
 * @author LendBit Finance
 *
 * Public write-only functions that allows writing into the state of LendBit
 */
contract Operations {
    using SafeERC20 for IERC20;

    LibAppStorage.Layout internal _appStorage;

    /**
     * @dev Allows users to deposit collateral of a specified token into the protocol. Supports both
     *      native and ERC-20 token collateral deposits.
     *
     * @param _tokenCollateralAddress The address of the token being deposited as collateral.
     * @param _amountOfCollateral The amount of the token to deposit as collateral.
     *
     * Requirements:
     * - `_amountOfCollateral` must be greater than zero.
     * - `_tokenCollateralAddress` must be an allowed token (i.e., have a non-zero price feed).
     *
     * If the deposit is in the native token, `_amountOfCollateral` is set to `msg.value`.
     * The function updates the collateral and available balance mappings for the sender, and if
     * the collateral is an ERC-20 token, it transfers `_amountOfCollateral` from the sender to the contract.
     * Emits a `CollateralDeposited` event on successful deposit.
     */
    function depositCollateral(
        address _tokenCollateralAddress,
        uint256 _amountOfCollateral
    ) external payable {
        // Validate the input parameters: `_amountOfCollateral` must be greater than zero,
        // and `_tokenCollateralAddress` must have a valid price feed (non-zero address).
        Validator._valueMoreThanZero(
            _amountOfCollateral,
            _tokenCollateralAddress,
            msg.value
        );
        Validator._isTokenAllowed(
            _appStorage.s_priceFeeds[_tokenCollateralAddress]
        );

        // Determine if the collateral is the native token
        bool _isNativeToken = _tokenCollateralAddress == Constants.NATIVE_TOKEN;

        // Set `_amountOfCollateral` to `msg.value` if it's a native token deposit
        if (_isNativeToken) {
            _amountOfCollateral = msg.value;
        }

        // Update the user's collateral and available balance in storage
        _appStorage.s_addressToCollateralDeposited[msg.sender][
            _tokenCollateralAddress
        ] += _amountOfCollateral;
        _appStorage.s_addressToAvailableBalance[msg.sender][
            _tokenCollateralAddress
        ] += _amountOfCollateral;

        // Transfer ERC-20 tokens from the sender to the contract if not the native token
        if (!_isNativeToken) {
            IERC20(_tokenCollateralAddress).safeTransferFrom(
                msg.sender,
                address(this),
                _amountOfCollateral
            );
        }

        // Emit an event for the collateral deposit
        emit CollateralDeposited(
            msg.sender,
            _tokenCollateralAddress,
            _amountOfCollateral
        );
    }

    /**
     * @dev Creates a new lending request by validating input parameters, calculating loanable amounts,
     *      and locking collateral proportional to the loan request.
     *
     * @param _amount The amount of loan requested by the borrower.
     * @param _interest The interest rate for the loan.
     * @param _returnDate The expected return date for the loan.
     * @param _loanCurrency The token address for the currency in which the loan is requested.
     *
     * Requirements:
     * - `_amount` must be greater than zero.
     * - `_loanCurrency` must be an approved loanable token.
     * - `_returnDate` must be at least 1 day in the future.
     * - The calculated USD value of `_amount` should meet the minimum loan amount requirement.
     * - Borrower must have sufficient collateral based on their collateral value and `_loanUsdValue`.
     *
     * The function locks collateral based on the proportional USD value of each token in the borrower’s
     * collateral, calculates the total repayment including interest, and stores loan request data.
     * Emits a `RequestCreated` event on successful request creation.
     */
    function createLendingRequest(
        uint128 _amount,
        uint16 _interest,
        uint256 _returnDate,
        address _loanCurrency
    ) external {
        // Validate that the loan amount is greater than zero
        Validator._moreThanZero(_amount);

        // Check if the loan currency is allowed by validating it against allowed loanable tokens
        if (!_appStorage.s_isLoanable[_loanCurrency]) {
            revert Protocol__TokenNotLoanable();
        }

        // Ensure the return date is at least 1 day in the future
        if ((_returnDate - block.timestamp) < 1 days) {
            revert Protocol__DateMustBeInFuture();
        }

        // Retrieve the loan currency's decimal precision
        uint8 decimal = LibGettersImpl._getTokenDecimal(_loanCurrency);

        // Calculate the USD equivalent of the loan amount
        uint256 _loanUsdValue = LibGettersImpl._getUsdValue(
            _appStorage,
            _loanCurrency,
            _amount,
            decimal
        );

        // Ensure that the USD value of the loan is valid and meets minimum requirements
        if (_loanUsdValue < 1) revert Protocol__InvalidAmount();

        // Get the total USD collateral value for the borrower
        uint256 collateralValueInLoanCurrency = LibGettersImpl
            ._getAccountCollateralValue(_appStorage, msg.sender);

        // Calculate the maximum loanable amount based on available collateral
        uint256 maxLoanableAmount = Utils.maxLoanableAmount(
            collateralValueInLoanCurrency
        );

        // Check if the loan exceeds the user's collateral allowance
        if (
            _appStorage.addressToUser[msg.sender].totalLoanCollected +
                _loanUsdValue >=
            maxLoanableAmount
        ) {
            revert Protocol__InsufficientCollateral();
        }

        // Retrieve collateral tokens associated with the borrower
        address[] memory _collateralTokens = LibGettersImpl
            ._getUserCollateralTokens(_appStorage, msg.sender);

        // Increment the request ID and initialize the new loan request
        _appStorage.requestId = _appStorage.requestId + 1;
        Request storage _newRequest = _appStorage.request[
            _appStorage.requestId
        ];
        _newRequest.requestId = _appStorage.requestId;
        _newRequest.author = msg.sender;
        _newRequest.amount = _amount;
        _newRequest.interest = _interest;
        _newRequest.returnDate = _returnDate;
        _newRequest.totalRepayment = Utils.calculateLoanInterest(
            _returnDate,
            _amount,
            _interest
        );
        _newRequest.loanRequestAddr = _loanCurrency;
        _newRequest.collateralTokens = _collateralTokens;
        _newRequest.status = Status.OPEN;

        // Calculate the amount of collateral to lock based on the loan value
        uint256 collateralToLock = Utils.calculateColateralToLock(
            _loanUsdValue,
            maxLoanableAmount
        );

        // For each collateral token, lock an appropriate amount based on its USD value
        for (uint256 i = 0; i < _collateralTokens.length; i++) {
            address token = _collateralTokens[i];
            uint8 _decimalToken = LibGettersImpl._getTokenDecimal(token);
            uint256 userBalance = _appStorage.s_addressToCollateralDeposited[
                msg.sender
            ][token];

            // Calculate the amount to lock in USD for each token based on the proportional collateral
            uint256 amountToLockUSD = (LibGettersImpl._getUsdValue(
                _appStorage,
                token,
                userBalance,
                _decimalToken
            ) * collateralToLock) / 100;

            // Convert USD amount to token amount and apply the correct decimal scaling
            uint256 amountToLock = ((((amountToLockUSD) * 10) /
                LibGettersImpl._getUsdValue(_appStorage, token, 10, 0)) *
                (10 ** _decimalToken)) / (Constants.PRECISION);

            // Store the locked amount for each collateral token
            _appStorage.s_idToCollateralTokenAmount[_appStorage.requestId][
                token
            ] = amountToLock;
        }

        // Emit an event for the created loan request
        emit RequestCreated(
            msg.sender,
            _appStorage.requestId,
            _amount,
            _interest
        );
    }

    /**
     * @dev Services a lending request by transferring funds from the lender to the borrower and updating request status.
     * @param _requestId The ID of the lending request to service.
     * @param _tokenAddress The address of the token to be used for funding.
     *
     * Requirements:
     * - `_tokenAddress` must be the native token or the lender must have approved sufficient balance of the specified token.
     * - Request must be open, not expired, and authored by someone other than the lender.
     * - Lender must have sufficient balance and allowance for ERC20 tokens, or sufficient msg.value for native tokens.
     * - The borrower's collateral must have a healthy factor after the loan is funded.
     *
     * Emits a `RequestServiced` event upon successful funding.
     */
    function serviceRequest(
        uint96 _requestId,
        address _tokenAddress
    ) external payable {
        // Validate if native token is being used and msg.value is non-zero
        Validator._nativeMoreThanZero(_tokenAddress, msg.value);

        // Load the request from storage
        Request storage _foundRequest = _appStorage.request[_requestId];

        // Ensure the request status is open and has not expired
        if (_foundRequest.status != Status.OPEN)
            revert Protocol__RequestNotOpen();
        if (_foundRequest.loanRequestAddr != _tokenAddress)
            revert Protocol__InvalidToken();
        if (_foundRequest.author == msg.sender) {
            revert Protocol__CantFundSelf();
        }
        if (_foundRequest.returnDate <= block.timestamp) {
            revert Protocol__RequestExpired();
        }

        // Update lender and request status to indicate servicing
        _foundRequest.lender = msg.sender;
        _foundRequest.status = Status.SERVICED;
        uint256 amountToLend = _foundRequest.amount;

        // Validate lender's balance and allowance if using ERC20 token, or msg.value if using native token
        if (_tokenAddress == Constants.NATIVE_TOKEN) {
            if (msg.value < amountToLend) {
                revert Protocol__InsufficientAmount();
            }
        } else {
            if (IERC20(_tokenAddress).balanceOf(msg.sender) < amountToLend)
                revert Protocol__InsufficientBalance();
            if (
                IERC20(_tokenAddress).allowance(msg.sender, address(this)) <
                amountToLend
            ) revert Protocol__InsufficientAllowance();
        }

        // Get token's decimal value and calculate the loan's USD equivalent
        uint8 _decimalToken = LibGettersImpl._getTokenDecimal(_tokenAddress);
        uint256 _loanUsdValue = LibGettersImpl._getUsdValue(
            _appStorage,
            _tokenAddress,
            amountToLend,
            _decimalToken
        );

        // Calculate the total repayment amount including interest
        uint256 _totalRepayment = amountToLend +
            Utils.calculateLoanInterest(
                _foundRequest.returnDate,
                _foundRequest.amount,
                _foundRequest.interest
            );
        _foundRequest.totalRepayment = _totalRepayment;

        // Update total loan collected in USD for the borrower
        _appStorage
            .addressToUser[_foundRequest.author]
            .totalLoanCollected += LibGettersImpl._getUsdValue(
            _appStorage,
            _tokenAddress,
            _totalRepayment,
            _decimalToken
        );

        // Validate borrower's collateral health factor after loan
        if (
            LibGettersImpl._healthFactor(
                _appStorage,
                _foundRequest.author,
                _loanUsdValue
            ) < 1
        ) {
            revert Protocol__InsufficientCollateral();
        }

        // Lock collateral amounts in the specified tokens for the request
        for (uint i = 0; i < _foundRequest.collateralTokens.length; i++) {
            _appStorage.s_addressToAvailableBalance[_foundRequest.author][
                _foundRequest.collateralTokens[i]
            ] -= _appStorage.s_idToCollateralTokenAmount[_requestId][
                _foundRequest.collateralTokens[i]
            ];
        }

        // Transfer loan amount to borrower based on token type
        if (_tokenAddress != Constants.NATIVE_TOKEN) {
            IERC20(_tokenAddress).safeTransferFrom(
                msg.sender,
                _foundRequest.author,
                amountToLend
            );
        } else {
            (bool sent, ) = payable(_foundRequest.author).call{
                value: amountToLend
            }("");

            if (!sent) revert Protocol__TransferFailed();
        }

        // Emit an event indicating successful servicing of the request
        emit RequestServiced(
            _requestId,
            msg.sender,
            _foundRequest.author,
            amountToLend
        );
    }

    /**
     * @dev Allows a user to withdraw a specified amount of collateral.
     * @param _tokenCollateralAddress The address of the collateral token to withdraw.
     * @param _amount The amount of collateral to withdraw.
     *
     * Requirements:
     * - The token address must be valid and allowed by the protocol.
     * - The withdrawal amount must be greater than zero.
     * - User must have at least the specified amount of collateral deposited.
     *
     * Emits a `CollateralWithdrawn` event on successful withdrawal.
     */
    function withdrawCollateral(
        address _tokenCollateralAddress,
        uint128 _amount
    ) external {
        // Validate that the token is allowed and the amount is greater than zero
        Validator._isTokenAllowed(
            _appStorage.s_priceFeeds[_tokenCollateralAddress]
        );
        Validator._moreThanZero(_amount);

        // Retrieve the user's deposited amount for the specified token
        uint256 depositedAmount = _appStorage.s_addressToAvailableBalance[
            msg.sender
        ][_tokenCollateralAddress];

        // Check if the user has sufficient collateral to withdraw the requested amount
        if (depositedAmount < _amount) {
            revert Protocol__InsufficientCollateralDeposited();
        }

        // Update storage to reflect the withdrawal of collateral
        _appStorage.s_addressToCollateralDeposited[msg.sender][
            _tokenCollateralAddress
        ] -= _amount;
        _appStorage.s_addressToAvailableBalance[msg.sender][
            _tokenCollateralAddress
        ] -= _amount;

        // Handle withdrawal for native token vs ERC20 tokens
        if (_tokenCollateralAddress == Constants.NATIVE_TOKEN) {
            // Transfer native token to the user
            (bool sent, ) = payable(msg.sender).call{value: _amount}("");
            if (!sent) revert Protocol__TransferFailed();
        } else {
            // Transfer ERC20 token to the user
            IERC20(_tokenCollateralAddress).safeTransfer(msg.sender, _amount);
        }

        // Emit an event indicating successful collateral withdrawal
        emit CollateralWithdrawn(msg.sender, _tokenCollateralAddress, _amount);
    }

    /**
     * @dev Adds new collateral tokens along with their respective price feeds to the protocol.
     * @param _tokens An array of token addresses to add as collateral.
     * @param _priceFeeds An array of corresponding price feed addresses for the tokens.
     *
     * Requirements:
     * - Only the contract owner can call this function.
     * - The `_tokens` and `_priceFeeds` arrays must have the same length.
     *
     * Emits an `UpdatedCollateralTokens` event with the total number of collateral tokens added.
     */
    function addCollateralTokens(
        address[] memory _tokens,
        address[] memory _priceFeeds
    ) external {
        // Ensure only the contract owner can add collateral tokens
        LibDiamond.enforceIsContractOwner();

        // Validate that the tokens and price feeds arrays have the same length
        if (_tokens.length != _priceFeeds.length) {
            revert Protocol__tokensAndPriceFeedsArrayMustBeSameLength();
        }

        // Loop through each token to set its price feed and add it to the collateral list
        for (uint8 i = 0; i < _tokens.length; i++) {
            _appStorage.s_priceFeeds[_tokens[i]] = _priceFeeds[i]; // Map token to price feed
            _appStorage.s_collateralToken.push(_tokens[i]); // Add token to collateral array
        }

        // Emit an event indicating the updated number of collateral tokens
        emit UpdatedCollateralTokens(
            msg.sender,
            uint8(_appStorage.s_collateralToken.length)
        );
    }
}
