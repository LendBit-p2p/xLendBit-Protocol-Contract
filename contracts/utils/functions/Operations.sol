// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibAppStorage} from "../../libraries/LibAppStorage.sol";
import {LibGettersImpl} from "../../libraries/LibGetters.sol";
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

    function serviceRequest(
        uint96 _requestId,
        address _tokenAddress
    ) external payable {
        Validator._nativeMoreThanZero(_tokenAddress, msg.value);

        Request storage _foundRequest = _appStorage.request[_requestId];

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

        _foundRequest.lender = msg.sender;
        _foundRequest.status = Status.SERVICED;
        uint256 amountToLend = _foundRequest.amount;

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

        uint8 _decimalToken = LibGettersImpl._getTokenDecimal(_tokenAddress);

        uint256 _loanUsdValue = LibGettersImpl._getUsdValue(
            _appStorage,
            _tokenAddress,
            amountToLend,
            _decimalToken
        );

        uint256 _totalRepayment = amountToLend +
            Utils.calculateLoanInterest(
                _foundRequest.returnDate,
                _foundRequest.amount,
                _foundRequest.interest
            );
        _foundRequest.totalRepayment = _totalRepayment;

        _appStorage
            .addressToUser[_foundRequest.author]
            .totalLoanCollected += LibGettersImpl._getUsdValue(
            _appStorage,
            _tokenAddress,
            _totalRepayment,
            _decimalToken
        );

        if (
            LibGettersImpl._healthFactor(
                _appStorage,
                _foundRequest.author,
                _loanUsdValue
            ) < 1
        ) {
            revert Protocol__InsufficientCollateral();
        }

        for (uint i = 0; i < _foundRequest.collateralTokens.length; i++) {
            _appStorage.s_addressToAvailableBalance[_foundRequest.author][
                _foundRequest.collateralTokens[i]
            ] =
                _appStorage.s_addressToAvailableBalance[_foundRequest.author][
                    _foundRequest.collateralTokens[i]
                ] -
                _appStorage.s_idToCollateralTokenAmount[_requestId][
                    _foundRequest.collateralTokens[i]
                ];
        }

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

        emit RequestServiced(
            _requestId,
            msg.sender,
            _foundRequest.author,
            amountToLend
        );
    }
}
