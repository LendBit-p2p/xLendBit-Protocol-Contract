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

    function createLendingRequest(
        uint128 _amount,
        uint16 _interest,
        uint256 _returnDate,
        address _loanCurrency
    ) external {
        Validator._moreThanZero(_amount);

        if (!_appStorage.s_isLoanable[_loanCurrency]) {
            revert Protocol__TokenNotLoanable();
        }

        if ((_returnDate - block.timestamp) < 1 days) {
            revert Protocol__DateMustBeInFuture();
        }

        uint8 decimal = LibGettersImpl._getTokenDecimal(_loanCurrency);

        uint256 _loanUsdValue = LibGettersImpl._getUsdValue(
            _appStorage,
            _loanCurrency,
            _amount,
            decimal
        );

        if (_loanUsdValue < 1) revert Protocol__InvalidAmount();

        uint256 collateralValueInLoanCurrency = LibGettersImpl
            ._getAccountCollateralValue(_appStorage, msg.sender);

        uint256 maxLoanableAmount = Utils.maxLoanableAmount(
            collateralValueInLoanCurrency
        );

        if (
            _appStorage.addressToUser[msg.sender].totalLoanCollected +
                _loanUsdValue >=
            maxLoanableAmount
        ) {
            revert Protocol__InsufficientCollateral();
        }

        address[] memory _collateralTokens = LibGettersImpl
            ._getUserCollateralTokens(_appStorage, msg.sender);

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

        uint256 collateralToLock = Utils.calculateColateralToLock(
            _loanUsdValue,
            maxLoanableAmount
        );

        for (uint256 i = 0; i < _collateralTokens.length; i++) {
            address token = _collateralTokens[i];
            uint8 _decimalToken = LibGettersImpl._getTokenDecimal(token);
            uint256 userBalance = _appStorage.s_addressToCollateralDeposited[
                msg.sender
            ][token];

            // Calculate the amount to lock for each token based on its proportion of the total collateral
            uint256 amountToLockUSD = (LibGettersImpl._getUsdValue(
                _appStorage,
                token,
                userBalance,
                _decimalToken
            ) * collateralToLock) / 100;

            uint256 amountToLock = ((((amountToLockUSD) * 10) /
                LibGettersImpl._getUsdValue(_appStorage, token, 10, 0)) *
                (10 ** _decimalToken)) / (Constants.PRECISION);

            _appStorage.s_idToCollateralTokenAmount[_appStorage.requestId][
                token
            ] = amountToLock;
        }

        emit RequestCreated(
            msg.sender,
            _appStorage.requestId,
            _amount,
            _interest
        );
    }
}
