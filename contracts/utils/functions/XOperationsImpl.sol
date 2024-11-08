// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AppStorage} from "./AppStorage.sol";
import {WormholeUtilities} from "./WormholeUtilities.sol";
import {LibGettersImpl} from "../../libraries/LibGetters.sol";
import {Validator} from "../validators/Validator.sol";
import {Constants} from "../constants/Constant.sol";
import {Utils} from "./Utils.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CCTPAndTokenReceiver} from "./Wormhole/CCTPAndTokenBase.sol";
import "../../model/Protocol.sol";
import "../../model/Event.sol";
import "../validators/Error.sol";

/**
 * @title Operations Implementation
 * @author LendBit Finance
 *
 * Internal write-only functions that allows writing into the state of LendBit
 */
contract XOperationsImpl is CCTPAndTokenReceiver, WormholeUtilities {
    using SafeERC20 for IERC20;

    function _depositCollateral(
        address _tokenCollateralAddress,
        uint256 _amountOfCollateral,
        address _msgSender,
        uint16 _chainId
    ) internal {
        // Validate the input parameters: `_amountOfCollateral` must be greater than zero,
        // and `_tokenCollateralAddress` must have a valid price feed (non-zero address).
        Validator._moreThanZero(_amountOfCollateral);
        Validator._isTokenAllowed(
            _appStorage.s_priceFeeds[_tokenCollateralAddress]
        );

        // Update the user's collateral and available balance in storage
        _appStorage.s_addressToCollateralDeposited[_msgSender][
            _tokenCollateralAddress
        ] += _amountOfCollateral;
        _appStorage.s_addressToAvailableBalance[_msgSender][
            _tokenCollateralAddress
        ] += _amountOfCollateral;

        // Emit an event for the collateral deposit
        emit Event.CollateralDeposited(
            _msgSender,
            _tokenCollateralAddress,
            _amountOfCollateral,
            _chainId
        );
    }

    function _createLendingRequest(
        ActionPayload memory payload,
        uint16 _chainId
    ) internal {
        // Validate that the loan amount is greater than zero
        Validator._moreThanZero(payload.assetAmount);

        // Check if the loan currency is allowed by validating it against allowed loanable tokens
        if (!_appStorage.s_isLoanable[payload.assetAddress]) {
            revert Protocol__TokenNotLoanable();
        }

        // Ensure the return date is at least 1 day in the future
        if ((payload.returnDate - block.timestamp) < 1 days) {
            revert Protocol__DateMustBeInFuture();
        }

        // Retrieve the loan currency's decimal precision
        uint8 decimal = LibGettersImpl._getTokenDecimal(payload.assetAddress);

        // Calculate the USD equivalent of the loan amount
        uint256 _loanUsdValue = LibGettersImpl._getUsdValue(
            _appStorage,
            payload.assetAddress,
            payload.assetAmount,
            decimal
        );

        // Ensure that the USD value of the loan is valid and meets minimum requirements
        if (_loanUsdValue < 1) revert Protocol__InvalidAmount();

        // Get the total USD collateral value for the borrower
        uint256 collateralValueInLoanCurrency = LibGettersImpl
            ._getAccountCollateralValue(_appStorage, payload.sender);

        // Calculate the maximum loanable amount based on available collateral
        uint256 maxLoanableAmount = Utils.maxLoanableAmount(
            collateralValueInLoanCurrency
        );

        // Check if the loan exceeds the user's collateral allowance
        if (
            _appStorage.addressToUser[payload.sender].totalLoanCollected +
                _loanUsdValue >=
            maxLoanableAmount
        ) {
            revert Protocol__InsufficientCollateral();
        }

        // Retrieve collateral tokens associated with the borrower
        address[] memory _collateralTokens = LibGettersImpl
            ._getUserCollateralTokens(_appStorage, payload.sender);

        // Increment the request ID and initialize the new loan request
        _appStorage.requestId = _appStorage.requestId + 1;
        Request storage _newRequest = _appStorage.request[
            _appStorage.requestId
        ];
        _newRequest.requestId = _appStorage.requestId;
        _newRequest.author = payload.sender;
        _newRequest.amount = payload.assetAmount;
        _newRequest.interest = payload.interest;
        _newRequest.returnDate = payload.returnDate;
        _newRequest.totalRepayment = Utils.calculateLoanInterest(
            payload.returnDate,
            payload.assetAmount,
            payload.interest
        );
        _newRequest.loanRequestAddr = payload.assetAddress;
        _newRequest.collateralTokens = _collateralTokens;
        _newRequest.status = Status.OPEN;
        _newRequest.chainId = _chainId;

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
                payload.sender
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
        emit Event.RequestCreated(
            payload.sender,
            _appStorage.requestId,
            payload.assetAmount,
            payload.interest,
            _chainId
        );
    }

    function _serviceRequest(
        uint96 _requestId,
        address _tokenAddress,
        address _msgSender,
        uint16 _chainId,
        uint256 _amount
    ) internal {
        // Validate if native token is being used and msg.value is non-zero
        Validator._nativeMoreThanZero(_tokenAddress, _amount);

        // Load the request from storage
        Request storage _foundRequest = _appStorage.request[_requestId];

        // Ensure the request status is open and has not expired
        if (_foundRequest.status != Status.OPEN)
            revert Protocol__RequestNotOpen();
        if (_foundRequest.loanRequestAddr != _tokenAddress)
            revert Protocol__InvalidToken();
        if (_foundRequest.author == _msgSender) {
            revert Protocol__CantFundSelf();
        }
        if (_foundRequest.returnDate <= block.timestamp) {
            revert Protocol__RequestExpired();
        }

        // Update lender and request status to indicate servicing
        _foundRequest.lender = _msgSender;
        _foundRequest.status = Status.SERVICED;
        uint256 amountToLend = _foundRequest.amount;

        // Validate lender's balance and allowance if using ERC20 token, or msg.value if using native token
        if (_amount < amountToLend) {
            revert Protocol__InsufficientAmount();
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

        // Emit an event indicating successful servicing of the request
        emit Event.RequestServiced(
            _requestId,
            _msgSender,
            _foundRequest.author,
            amountToLend,
            _chainId
        );

        if (_foundRequest.chainId == _appStorage.provider.chainId) {
            if (_tokenAddress != Constants.NATIVE_TOKEN) {
                IERC20(_tokenAddress).safeTransfer(
                    _foundRequest.author,
                    amountToLend
                );
            } else {
                (bool sent, ) = payable(_foundRequest.author).call{
                    value: amountToLend
                }("");

                if (!sent) revert Protocol__TransferFailed();
            }
        } else {
            ActionPayload memory payload = ActionPayload(
                Action.Credit,
                0,
                _requestId,
                _msgSender,
                _tokenAddress,
                _amount,
                0,
                0,
                0
            );
            bytes memory _payload = _encodeActionPayload(payload);
            _handleTokenTransfer(
                _foundRequest.chainId,
                _appStorage.s_spokeProtocols[_foundRequest.chainId],
                _payload,
                _tokenAddress,
                _amount
            );
        }
    }

    function _withdrawCollateral(
        address _tokenCollateralAddress,
        uint256 _amount,
        address _msgSender,
        uint16 _chainId
    ) internal {
        // Validate that the token is allowed and the amount is greater than zero
        Validator._isTokenAllowed(
            _appStorage.s_priceFeeds[_tokenCollateralAddress]
        );
        Validator._moreThanZero(_amount);

        // Retrieve the user's deposited amount for the specified token
        uint256 depositedAmount = _appStorage.s_addressToAvailableBalance[
            _msgSender
        ][_tokenCollateralAddress];

        // Check if the user has sufficient collateral to withdraw the requested amount
        if (depositedAmount < _amount) {
            revert Protocol__InsufficientCollateralDeposited();
        }

        // Update storage to reflect the withdrawal of collateral
        _appStorage.s_addressToCollateralDeposited[_msgSender][
            _tokenCollateralAddress
        ] -= _amount;
        _appStorage.s_addressToAvailableBalance[_msgSender][
            _tokenCollateralAddress
        ] -= _amount;

        // Handle withdrawal for native token vs ERC20 tokens
        ActionPayload memory payload = ActionPayload(
            Action.Credit,
            0,
            0,
            _msgSender,
            _tokenCollateralAddress,
            _amount,
            0,
            0,
            0
        );
        bytes memory _payload = _encodeActionPayload(payload);
        _handleTokenTransfer(
            _chainId,
            _appStorage.s_spokeProtocols[_chainId],
            _payload,
            _tokenCollateralAddress,
            _amount
        );

        // Emit an event indicating successful collateral withdrawal
        emit Event.CollateralWithdrawn(
            _msgSender,
            _tokenCollateralAddress,
            _amount,
            _chainId
        );
    }

    function _createLoanListing(
        uint256 _amount,
        uint256 _min_amount,
        uint256 _max_amount,
        uint256 _returnDate,
        uint16 _interest,
        address _loanCurrency,
        address _msgSender,
        uint16 _sourceChain
    ) internal {
        // Validate that the amount is greater than zero and that a value has been sent if using native token
        Validator._moreThanZero(_amount);

        // Ensure the specified loan currency is a loanable token
        if (!_appStorage.s_isLoanable[_loanCurrency]) {
            revert Protocol__TokenNotLoanable();
        }

        // Increment the listing ID to create a new loan listing
        _appStorage.listingId = _appStorage.listingId + 1;
        LoanListing storage _newListing = _appStorage.loanListings[
            _appStorage.listingId
        ];

        // Populate the loan listing struct with the provided details
        _newListing.listingId = _appStorage.listingId;
        _newListing.author = _msgSender;
        _newListing.amount = _amount;
        _newListing.min_amount = _min_amount;
        _newListing.max_amount = _max_amount;
        _newListing.interest = _interest;
        _newListing.returnDate = _returnDate;
        _newListing.tokenAddress = _loanCurrency;
        _newListing.listingStatus = ListingStatus.OPEN;
        _newListing.chainId = _sourceChain;

        // Emit an event to notify that a new loan listing has been created
        emit Event.LoanListingCreated(
            _appStorage.listingId,
            _msgSender,
            _loanCurrency,
            _amount,
            _sourceChain
        );
    }

    function _requestLoanFromListing(
        uint96 _listingId,
        uint256 _amount,
        address _msgSender,
        uint16 _sourceChain
    ) internal {
        Validator._moreThanZero(_amount);

        LoanListing storage _listing = _appStorage.loanListings[_listingId];

        // Check if the listing is open and the borrower is not the listing creator
        if (_listing.listingStatus != ListingStatus.OPEN)
            revert Protocol__ListingNotOpen();
        if (_listing.author == _msgSender)
            revert Protocol__OwnerCreatedListing();

        // Validate that the requested amount is within the listing's constraints
        if ((_amount < _listing.min_amount) || (_amount > _listing.max_amount))
            revert Protocol__InvalidAmount();
        if (_amount > _listing.amount) revert Protocol__InvalidAmount();

        // Fetch token decimal and calculate USD value of the loan amount
        uint8 _decimalToken = LibGettersImpl._getTokenDecimal(
            _listing.tokenAddress
        );
        uint256 _loanUsdValue = LibGettersImpl._getUsdValue(
            _appStorage,
            _listing.tokenAddress,
            _amount,
            _decimalToken
        );

        // Ensure borrower meets the health factor threshold for collateralization
        if (
            LibGettersImpl._healthFactor(
                _appStorage,
                _msgSender,
                _loanUsdValue
            ) < 1
        ) {
            revert Protocol__InsufficientCollateral();
        }

        // Calculate max loanable amount based on collateral value
        uint256 collateralValueInLoanCurrency = LibGettersImpl
            ._getAccountCollateralValue(_appStorage, _msgSender);
        uint256 maxLoanableAmount = Utils.maxLoanableAmount(
            collateralValueInLoanCurrency
        );

        // Update the listing's available amount, adjusting min/max amounts as necessary
        _listing.amount = _listing.amount - _amount;
        if (_listing.amount <= _listing.max_amount)
            _listing.max_amount = _listing.amount;
        if (_listing.amount <= _listing.min_amount) _listing.min_amount = 0;
        if (_listing.amount == 0) _listing.listingStatus = ListingStatus.CLOSED;

        // Retrieve the borrower's collateral tokens for collateralization
        address[] memory _collateralTokens = LibGettersImpl
            ._getUserCollateralTokens(_appStorage, _msgSender);

        // Create a new loan request with a unique ID
        _appStorage.requestId = _appStorage.requestId + 1;
        Request storage _newRequest = _appStorage.request[
            _appStorage.requestId
        ];
        _newRequest.requestId = _appStorage.requestId;
        _newRequest.author = _msgSender;
        _newRequest.lender = _listing.author;
        _newRequest.amount = _amount;
        _newRequest.interest = _listing.interest;
        _newRequest.returnDate = _listing.returnDate;
        _newRequest.totalRepayment = Utils.calculateLoanInterest(
            _listing.returnDate,
            _amount,
            _listing.interest
        );
        _newRequest.loanRequestAddr = _listing.tokenAddress;
        _newRequest.collateralTokens = _collateralTokens;
        _newRequest.status = Status.SERVICED;
        _newRequest.chainId = _sourceChain;

        // Calculate collateral to lock for each token, proportional to its USD value
        uint256 collateralToLock = Utils.calculateColateralToLock(
            _loanUsdValue,
            maxLoanableAmount
        );
        for (uint256 i = 0; i < _collateralTokens.length; i++) {
            address token = _collateralTokens[i];
            uint8 decimal = LibGettersImpl._getTokenDecimal(token);
            uint256 userBalance = _appStorage.s_addressToCollateralDeposited[
                _msgSender
            ][token];

            uint256 amountToLockUSD = (LibGettersImpl._getUsdValue(
                _appStorage,
                token,
                userBalance,
                decimal
            ) * collateralToLock) / 100;

            uint256 amountToLock = ((((amountToLockUSD) * 10) /
                LibGettersImpl._getUsdValue(_appStorage, token, 10, 0)) *
                (10 ** _decimalToken)) / (Constants.PRECISION);

            _appStorage.s_idToCollateralTokenAmount[_appStorage.requestId][
                token
            ] = amountToLock;
            _appStorage.s_addressToAvailableBalance[_newRequest.author][
                token
            ] -= amountToLock;
        }

        // Update borrower's total loan collected in USD
        _appStorage
            .addressToUser[_msgSender]
            .totalLoanCollected += LibGettersImpl._getUsdValue(
            _appStorage,
            _listing.tokenAddress,
            _newRequest.totalRepayment,
            _decimalToken
        );

        // Emit events to notify the loan request creation and servicing
        emit Event.RequestCreated(
            _msgSender,
            _appStorage.requestId,
            _amount,
            _listing.interest,
            _sourceChain
        );
        emit Event.RequestServiced(
            _newRequest.requestId,
            _newRequest.lender,
            _newRequest.author,
            _amount,
            _listing.chainId
        );

        ActionPayload memory payload = ActionPayload(
            Action.Credit,
            0,
            0,
            _msgSender,
            _listing.tokenAddress,
            _newRequest.amount,
            0,
            0,
            0
        );
        bytes memory _payload = _encodeActionPayload(payload);
        _handleTokenTransfer(
            _sourceChain,
            _appStorage.s_spokeProtocols[_sourceChain],
            _payload,
            _listing.tokenAddress,
            _newRequest.amount
        );
    }

    function _repayLoan(
        uint96 _requestId,
        uint256 _amount,
        address _token,
        address _msgSender,
        uint16 _sourceChain
    ) internal {
        Validator._moreThanZero(_amount);

        Request storage _request = _appStorage.request[_requestId];

        // Ensure that the loan request is currently serviced and the caller is the original borrower
        if (_request.status != Status.SERVICED)
            revert Protocol__RequestNotServiced();
        if (_msgSender != _request.author) revert Protocol__NotOwner();

        if (_request.loanRequestAddr != _token) revert Protocol__InvalidToken();

        // If full repayment is made, close the request and release the collateral
        if (_amount >= _request.totalRepayment) {
            _amount = _request.totalRepayment;
            _request.totalRepayment = 0;
            _request.status = Status.CLOSED;

            for (uint i = 0; i < _request.collateralTokens.length; i++) {
                address collateralToken = _request.collateralTokens[i];
                _appStorage.s_addressToAvailableBalance[_request.author][
                    collateralToken
                ] += _appStorage.s_idToCollateralTokenAmount[_requestId][
                    collateralToken
                ];
            }
        } else {
            // Reduce the outstanding repayment amount for partial payments
            _request.totalRepayment -= _amount;
        }

        // Update borrower’s loan collected metrics in USD
        uint8 decimal = LibGettersImpl._getTokenDecimal(
            _request.loanRequestAddr
        );
        uint256 _loanUsdValue = LibGettersImpl._getUsdValue(
            _appStorage,
            _request.loanRequestAddr,
            _amount,
            decimal
        );
        uint256 loanCollected = LibGettersImpl._getLoanCollectedInUsd(
            _appStorage,
            _msgSender
        );

        // Deposit the repayment amount to the lender's available balance
        _appStorage.s_addressToCollateralDeposited[_request.lender][
            _request.loanRequestAddr
        ] += _amount;
        _appStorage.s_addressToAvailableBalance[_request.lender][
            _request.loanRequestAddr
        ] += _amount;

        // Adjust the borrower's total loan collected
        if (loanCollected > _loanUsdValue) {
            _appStorage.addressToUser[_msgSender].totalLoanCollected =
                loanCollected -
                _loanUsdValue;
        } else {
            _appStorage.addressToUser[_msgSender].totalLoanCollected = 0;
        }

        // Emit event to notify of loan repayment
        emit Event.LoanRepayment(_msgSender, _requestId, _amount, _sourceChain);
    }

    function _vetTokenAndUnwrap(
        TokenReceived[] memory _tokenReceived
    ) internal returns (TokenReceived memory _token) {
        if (_tokenReceived.length != 1) {
            revert Protocol__InvalidAction();
        }
        _token = _tokenReceived[0];

        if (_token.tokenAddress == Constants.WETH) {
            IWETH(Constants.WETH).withdraw(_token.amount);
            _token.tokenAddress = Constants.NATIVE_TOKEN;
        }
    }
}
