// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AppStorage} from "./AppStorage.sol";
import {WormholeUtilities} from "./WormholeUtilities.sol";
import {LibGettersImpl} from "../../libraries/LibGetters.sol";
import {LibDiamond} from "../../libraries/LibDiamond.sol";
import {Validator} from "../validators/Validator.sol";
import {Constants} from "../constants/Constant.sol";
import {Utils} from "./Utils.sol";
import "../../interfaces/IUniswapV2Router02.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Wormhole/TokenBase.sol";
import "../../model/Protocol.sol";
import "../../model/Event.sol";
import "../validators/Error.sol";

/**
 * @title Operations Implementation
 * @author LendBit Finance
 *
 * Internal write-only functions that allows writing into the state of LendBit
 */
contract XOperationsImpl is TokenReceiver, WormholeUtilities {
    using SafeERC20 for IERC20;

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
        emit CollateralDeposited(
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
        emit RequestCreated(
            payload.sender,
            _appStorage.requestId,
            payload.assetAmount,
            payload.interest,
            _chainId
        );
    }

    // /**
    //  * @dev Services a lending request by transferring funds from the lender to the borrower and updating request status.
    //  * @param _requestId The ID of the lending request to service.
    //  * @param _tokenAddress The address of the token to be used for funding.
    //  *
    //  * Requirements:
    //  * - `_tokenAddress` must be the native token or the lender must have approved sufficient balance of the specified token.
    //  * - Request must be open, not expired, and authored by someone other than the lender.
    //  * - Lender must have sufficient balance and allowance for ERC20 tokens, or sufficient msg.value for native tokens.
    //  * - The borrower's collateral must have a healthy factor after the loan is funded.
    //  *
    //  * Emits a `RequestServiced` event upon successful funding.
    //  */
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
        emit RequestServiced(
            _requestId,
            msg.sender,
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

    // /**
    //  * @dev Allows a user to withdraw a specified amount of collateral.
    //  * @param _tokenCollateralAddress The address of the collateral token to withdraw.
    //  * @param _amount The amount of collateral to withdraw.
    //  *
    //  * Requirements:
    //  * - The token address must be valid and allowed by the protocol.
    //  * - The withdrawal amount must be greater than zero.
    //  * - User must have at least the specified amount of collateral deposited.
    //  *
    //  * Emits a `CollateralWithdrawn` event on successful withdrawal.
    //  */
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
        emit CollateralWithdrawn(
            _msgSender,
            _tokenCollateralAddress,
            _amount,
            _chainId
        );
    }

    // /**
    //  * @dev Creates a loan listing for lenders to fund.
    //  * @param _amount The total amount being loaned.
    //  * @param _min_amount The minimum amount a lender can fund.
    //  * @param _max_amount The maximum amount a lender can fund.
    //  * @param _returnDate The date by which the loan should be repaid.
    //  * @param _interest The interest rate to be applied on the loan.
    //  * @param _loanCurrency The currency in which the loan is issued (token address).
    //  *
    //  * Requirements:
    //  * - The loan amount must be greater than zero.
    //  * - The currency must be a loanable token.
    //  * - If using a token, the sender must have sufficient balance and allowance.
    //  * - If using the native token, the amount must be sent as part of the transaction.
    //  *
    //  * Emits a `LoanListingCreated` event indicating the listing ID, author, and loan currency.
    //  */
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
        _newListing.chainId = _sourceChain

        // Emit an event to notify that a new loan listing has been created
        emit LoanListingCreated(
            _appStorage.listingId,
            msg.sender,
            _loanCurrency,
            _amount,
            _sourceChain
        );
    }

    // /**
    //  * @dev Allows a borrower to request a loan from an open listing.
    //  * @param _listingId The unique identifier of the loan listing.
    //  * @param _amount The requested loan amount.
    //  *
    //  * Requirements:
    //  * - `_amount` must be greater than zero.
    //  * - The listing must be open, not created by the borrower, and within min/max constraints.
    //  * - The borrower must have sufficient collateral to meet the health factor.
    //  *
    //  * Emits:
    //  * - `RequestCreated` when a loan request is successfully created.
    //  * - `RequestServiced` when the loan request is successfully serviced.
    //  */
    function _requestLoanFromListing(uint96 _listingId, uint256 _amount, address _msgSender, uint16 _sourceChain) internal {
        Validator._moreThanZero(_amount);

        LoanListing storage _listing = _appStorage.loanListings[_listingId];

        // Check if the listing is open and the borrower is not the listing creator
        if (_listing.listingStatus != ListingStatus.OPEN)
            revert Protocol__ListingNotOpen();
        if (_listing.author == msg.sender)
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
            _appStorage.s_addressToAvailableBalance[_msgSender][
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
        emit RequestCreated(
            msg.sender,
            _appStorage.requestId,
            _amount,
            _listing.interest,
            _sourceChain
        );
        emit RequestServiced(
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
            _amount,
            0
        );
        bytes memory _payload = _encodeActionPayload(payload);
        _handleTokenTransfer(
            _chainId,
            _appStorage.s_spokeProtocols[_chainId],
            _payload,
            _listing.tokenAddress,
            _amount
        );

    }

    // /**
    //  * @dev Allows a borrower to repay a loan in part or in full.
    //  * @param _requestId The unique identifier of the loan request.
    //  * @param _amount The repayment amount.
    //  *
    //  * Requirements:
    //  * - `_amount` must be greater than zero.
    //  * - The loan request must be in the SERVICED status.
    //  * - The caller must be the borrower who created the loan request.
    //  * - If repaying in a token, the borrower must have sufficient balance and allowance.
    //  *
    //  * Emits:
    //  * - `LoanRepayment` upon successful repayment.
    //  */
    // function repayLoan(uint96 _requestId, uint256 _amount) external payable {
    //     Validator._moreThanZero(_amount);

    //     Request storage _request = _appStorage.request[_requestId];

    //     // Ensure that the loan request is currently serviced and the caller is the original borrower
    //     if (_request.status != Status.SERVICED)
    //         revert Protocol__RequestNotServiced();
    //     if (msg.sender != _request.author) revert Protocol__NotOwner();

    //     // Process repayment amount based on the token type
    //     if (_request.loanRequestAddr == Constants.NATIVE_TOKEN) {
    //         _amount = msg.value;
    //     } else {
    //         IERC20 _token = IERC20(_request.loanRequestAddr);
    //         if (_token.balanceOf(msg.sender) < _amount)
    //             revert Protocol__InsufficientBalance();
    //         if (_token.allowance(msg.sender, address(this)) < _amount)
    //             revert Protocol__InsufficientAllowance();

    //         _token.safeTransferFrom(msg.sender, address(this), _amount);
    //     }

    //     // If full repayment is made, close the request and release the collateral
    //     if (_amount >= _request.totalRepayment) {
    //         _amount = _request.totalRepayment;
    //         _request.totalRepayment = 0;
    //         _request.status = Status.CLOSED;

    //         for (uint i = 0; i < _request.collateralTokens.length; i++) {
    //             address collateralToken = _request.collateralTokens[i];
    //             _appStorage.s_addressToAvailableBalance[_request.author][
    //                 collateralToken
    //             ] += _appStorage.s_idToCollateralTokenAmount[_requestId][
    //                 collateralToken
    //             ];
    //         }
    //     } else {
    //         // Reduce the outstanding repayment amount for partial payments
    //         _request.totalRepayment -= _amount;
    //     }

    //     // Update borrower’s loan collected metrics in USD
    //     uint8 decimal = LibGettersImpl._getTokenDecimal(
    //         _request.loanRequestAddr
    //     );
    //     uint256 _loanUsdValue = LibGettersImpl._getUsdValue(
    //         _appStorage,
    //         _request.loanRequestAddr,
    //         _amount,
    //         decimal
    //     );
    //     uint256 loanCollected = LibGettersImpl._getLoanCollectedInUsd(
    //         _appStorage,
    //         msg.sender
    //     );

    //     // Deposit the repayment amount to the lender's available balance
    //     _appStorage.s_addressToCollateralDeposited[_request.lender][
    //         _request.loanRequestAddr
    //     ] += _amount;
    //     _appStorage.s_addressToAvailableBalance[_request.lender][
    //         _request.loanRequestAddr
    //     ] += _amount;

    //     // Adjust the borrower's total loan collected
    //     if (loanCollected > _loanUsdValue) {
    //         _appStorage.addressToUser[msg.sender].totalLoanCollected =
    //             loanCollected -
    //             _loanUsdValue;
    //     } else {
    //         _appStorage.addressToUser[msg.sender].totalLoanCollected = 0;
    //     }

    //     // Emit event to notify of loan repayment
    //     emit LoanRepayment(msg.sender, _requestId, _amount);
    // }

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
