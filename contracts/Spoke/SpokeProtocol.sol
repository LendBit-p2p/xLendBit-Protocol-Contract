// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "lib/wormhole-solidity-sdk/src/interfaces/IERC20.sol";
import "lib/wormhole-solidity-sdk/src/interfaces/IWormholeRelayer.sol";
import "lib/wormhole-solidity-sdk/src/WormholeRelayerSDK.sol";
import {Validator} from "../utils/validators/Validator.sol";
import {Constants} from "../utils/constants/Constant.sol";
import "../model/Protocol.sol";
import {Message} from "../utils/functions/Message.sol";
import "../utils/validators/Error.sol";
import "../model/Event.sol";

/**
 * @title SpokeProtocol
 * @author LendBit Finance
 * Contains public write-only functions that modify the state of the LendBit system
 * via interactions with the Wormhole protocol for cross-chain communication.
 * This contract utilizes `TokenSender` and `Message` functionalities.
 */
contract SpokeProtocol is CCTPAndTokenSender, CCTPAndTokenReceiver, Message {
    uint16 public immutable i_chainId;
    address public immutable i_WETH;
    address public immutable i_USDC;
    uint16 s_hubChainId;
    address s_hubChainAddress;
    mapping(address token => bool) isTokenValid;

    constructor(
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole,
        address[] memory _tokens,
        address _circleTM,
        address _circleMT,
        uint16 _chainId,
        address _USDC,
        address _WETH
    )
        CCTPAndTokenBase(
            _wormholeRelayer,
            _tokenBridge,
            _wormhole,
            _circleMT,
            _circleTM,
            _USDC
        )
    {
        if (_tokens.length < 1) revert spoke__TokenArrayCantBeEmpty();
        for (uint8 i = 0; i < _tokens.length; i++) {
            isTokenValid[_tokens[i]] = true;
        }
        i_chainId = _chainId;
        i_USDC = _USDC;
        i_WETH = _WETH;
    }

    //////////////////
    /// Modifiers ///
    ////////////////

    /**
     * @dev Checks if the specified token address is valid.
     * Reverts with `spoke_TokenNotValid` if the token is not allowed.
     */
    modifier _isTokenValid(address _addr) {
        if (!isTokenValid[_addr]) revert spoke_TokenNotVaid();
        _;
    }

    /**
     * @dev Allows users to deposit collateral of a specified token into the protocol, supporting both
     *      native and ERC-20 token deposits. Deposits collateral on the current chain and sends a payload
     *      to the specified target chain via Wormhole protocol.
     *
     * @param _targetChain The ID of the target chain to which the payload will be sent.
     * @param _targetAddress The address on the target chain that will receive the payload.
     * @param _assetAddress The address of the token to deposit as collateral (use `Constants.NATIVE_TOKEN` for native tokens).
     * @param _amount The amount of the token to deposit as collateral. If depositing a native token, this must equal `msg.value`.
     *
     * Requirements:
     * - `_amount` must be greater than zero.
     * - `_assetAddress` must be an allowed token with a valid price feed.
     * - `msg.value` should be sufficient to cover cross-chain gas fees and, if depositing native tokens, `_amount`.
     *
     * Emits a `Spoke__DepositCollateral` event on successful deposit.
     */
    function depositCollateral(
        address _assetAddress,
        uint256 _amount
    ) external payable _isTokenValid(_assetAddress) {
        Validator._valueMoreThanZero(_amount, _assetAddress, msg.value);

        uint256 cost = _quoteCrossChainCost(_targetChain);

        if (msg.value - cost < 1) revert spoke__InsufficientGasFee();

        if (_assetAddress == Constants.NATIVE_TOKEN) {
            _amount = msg.value - cost;
            _assetAddress = i_WETH;
        } else {
            bool success = IERC20(_assetAddress).transferFrom(
                msg.sender,
                address(this),
                _amount
            );
            require(success, "Token transfer failed");
        }

        // Create and encode payload for cross-chain message
        ActionPayload memory payload;
        payload.action = Action.Deposit;
        payload.assetAddress = _assetAddress;
        payload.assetAmount = _amount;
        payload.sender = msg.sender;

        bytes memory _payload = Message._encodeActionPayload(payload);

        if (_assetAddress == i_USDC) {
            sendUSDCWithPayloadToEvm(
                s_hubChainId,
                s_hubChainAddress,
                payload,
                0,
                Constants.GAS_LIMIT,
                _amount
            );
        } else {
            // Send the token with payload to the target chain
            sendTokenWithPayloadToEvm(
                s_hubChainId,
                s_hubChainAddress,
                _payload,
                0, // No native tokens sent
                Constants.GAS_LIMIT,
                _assetAddress,
                _amount,
                i_chainId,
                msg.sender // Refund address is this contract
            );
        }

        emit Spoke__DepositCollateral(
            _targetChain,
            _amount,
            msg.sender,
            _assetAddress
        );
    }

    /**
     * @dev Creates a lending request that is sent to the specified `_targetChain` and `_targetAddress`
     *      through a cross-chain message. This function allows users to request a loan with a specified
     *      interest rate, return date, and loan currency.
     *
     * @param _targetChain The target chain ID for the cross-chain message.
     * @param _targetAddress The address on the target chain to receive the lending request.
     * @param _interest The interest rate applied to the lending request.
     * @param _returnDate The UNIX timestamp by which the loan should be repaid.
     * @param _loanAddress The address of the loan currency token.
     * @param _amount The amount of currency being requested as a loan.
     *
     * Requirements:
     * - `_amount` must be greater than zero.
     * - `_loanAddress` cannot be the zero address.
     * - Sufficient cross-chain gas fee must be provided in `msg.value`.
     *
     * Emits a `Spoke__CreateRequest` event indicating the target chain, loan amount, sender, and loan currency.
     */
    function createLendingRequest(
        uint16 _targetChain,
        address _targetAddress,
        uint16 _interest,
        uint256 _returnDate,
        address _loanAddress,
        uint256 _amount
    ) external payable {
        Validator._moreThanZero(_amount);
        Validator._isTokenAllowed(_loanAddress);

        uint256 cost = _quoteCrossChainCost(_targetChain);

        uint16 currentChainId = _getChainId(address(this));
        if (currentChainId < 1) revert spoke__InvalidSpokeChainId();

        if (msg.value < cost) revert spoke__InsufficientGasFee();

        // Create and encode payload for cross-chain message
        ActionPayload memory payload;
        payload.action = Action.CreateRequest;
        payload.assetAddress = _loanAddress;
        payload.assetAmount = _amount;
        payload.sender = msg.sender;
        payload.interest = _interest;
        payload.returnDate = _returnDate;

        bytes memory _payload = Message._encodeActionPayload(payload);

        _sendPayloadToEvm(
            _targetChain,
            _targetAddress,
            _payload,
            currentChainId,
            cost
        );

        emit Spoke__CreateRequest(
            _targetChain,
            _amount,
            msg.sender,
            _loanAddress
        );
    }

    /**
     * @dev Initiates a service request sent to `_targetChain` and `_targetAddress`
     *      via a cross-chain message. The request includes a specified token and request ID.
     *
     * @param _targetChain The target chain ID for the cross-chain message.
     * @param _targetAddress The address on the target chain to receive the service request.
     * @param _requestId The unique identifier for the service request.
     * @param _tokenAddress The address of the token related to the service request.
     *
     * Requirements:
     * - Sufficient cross-chain gas fee must be provided in `msg.value`.
     *
     * Emits a `Spoke__ServiceRequest` event indicating the target chain, request ID, sender, and token address.
     */
    function serviceRequest(
        uint16 _targetChain,
        address _targetAddress,
        uint96 _requestId,
        address _tokenAddress
    ) external payable {
        uint256 cost = _quoteCrossChainCost(_targetChain);

        uint16 currentChainId = _getChainId(address(this));
        if (currentChainId < 1) revert spoke__InvalidSpokeChainId();

        if (msg.value < cost) revert spoke__InsufficientGasFee();

        // Create and encode payload for cross-chain message
        ActionPayload memory payload;
        payload.action = Action.ServiceRequest;
        payload.assetAddress = _tokenAddress;
        payload.sender = msg.sender;
        payload.id = _requestId;

        bytes memory _payload = Message._encodeActionPayload(payload);

        _sendPayloadToEvm(
            _targetChain,
            _targetAddress,
            _payload,
            currentChainId,
            cost
        );

        emit Spoke__ServiceRequest(
            _targetChain,
            _requestId,
            msg.sender,
            _tokenAddress
        );
    }

    /**
     * @dev Sends an encoded payload to a specified `_targetChain` and `_targetAddress`.
     *
     * @param _targetChain The target chain ID for cross-chain message.
     * @param _targetAddress The address on the target chain to receive the payload.
     * @param _payload The encoded payload data to be sent.
     * @param _currentChainId The current chain ID where the function is executed.
     * @param _costFee The gas fee for cross-chain messaging.
     */
    function _sendPayloadToEvm(
        uint16 _targetChain,
        address _targetAddress,
        bytes memory _payload,
        uint16 _currentChainId,
        uint256 _costFee
    ) private {
        wormholeRelayer.sendPayloadToEvm{value: _costFee}(
            _targetChain,
            _targetAddress,
            _payload,
            0,
            Constants.GAS_LIMIT,
            _currentChainId,
            msg.sender
        );
    }

    /**
     * @dev Allows a user to withdraw a specified amount of collateral from the protocol
     *      and send it to a specified address on a target chain.
     *
     * @param _targetChain The target chain ID for the cross-chain message.
     * @param _targetAddress The address on the target chain to receive the withdrawn collateral.
     * @param _tokenCollateralAddress The address of the token being withdrawn as collateral.
     * @param _amount The amount of the token to withdraw.
     *
     * Requirements:
     * - Sufficient cross-chain gas fee must be provided in `msg.value`.
     * - `_amount` must be greater than zero.
     * - `_targetChain` must be a valid chain ID.
     *
     * Emits a `Spoke__WithdrawnCollateral` event on successful collateral withdrawal.
     */
    function withdrawnCollateral(
        uint16 _targetChain,
        address _targetAddress,
        address _tokenCollateralAddress,
        uint128 _amount
    ) external payable {
        uint256 cost = _quoteCrossChainCost(_targetChain);

        uint16 currentChainId = _getChainId(address(this));
        if (currentChainId < 1) revert spoke__InvalidSpokeChainId();

        if (msg.value < cost) revert spoke__InsufficientGasFee();

        // Create and encode payload for cross-chain message
        ActionPayload memory payload;
        payload.action = Action.Withdraw;
        payload.assetAddress = _tokenCollateralAddress;
        payload.assetAmount = _amount;
        payload.sender = msg.sender;

        bytes memory _payload = Message._encodeActionPayload(payload);

        _sendPayloadToEvm(
            _targetChain,
            _targetAddress,
            _payload,
            currentChainId,
            cost
        );

        emit Spoke__WithrawnCollateral(
            _targetChain,
            _targetAddress,
            msg.sender,
            _tokenCollateralAddress
        );
    }

    /**
     * @dev Creates a loan listing for potential lenders, publishing the listing details via Wormhole
     * to facilitate cross-chain interactions.
     *
     * @param _targetChain The ID of the target chain where the loan listing will be published.
     * @param _targetAddress The address on the target chain that will receive the loan listing details.
     * @param _amount The total amount being loaned.
     * @param _min_amount The minimum amount a lender can fund.
     * @param _max_amount The maximum amount a lender can fund.
     * @param _returnDate The date by which the loan should be repaid.
     * @param _interest The interest rate applied to the loan.
     * @param _loanCurrency The currency (token address) in which the loan is issued.
     *
     * Requirements:
     * - `_amount` must be greater than zero.
     * - `_loanCurrency` must be a loanable token.
     * - If `_loanCurrency` is a token, the sender must have sufficient balance and allowance.
     * - If using the native token, the equivalent amount must be sent as part of the transaction.
     * - `msg.value` must cover the cross-chain transaction fee to the Wormhole.
     *
     * Emits a `LoanListingCreated` event, containing the listing ID, author, and loan currency.
     */

    function createLoanListing(
        uint16 _targetChain,
        address _targetAddress,
        uint256 _amount,
        uint256 _min_amount,
        uint256 _max_amount,
        uint256 _returnDate,
        uint16 _interest,
        address _loanCurrency
    ) external payable {
        Validator._valueMoreThanZero(_amount, _loanCurrency, msg.value);

        uint256 cost = _quoteCrossChainCost(_targetChain);
        uint16 currentChainId = _getChainId(address(this));
        if (currentChainId < 1) revert spoke__InvalidSpokeChainId();

        if (msg.value < cost) revert spoke__InsufficientGasFee();

        // Check for sufficient balance and allowance if using a token other than native
        if (_loanCurrency != Constants.NATIVE_TOKEN) {
            if (IERC20(_loanCurrency).balanceOf(msg.sender) < _amount)
                revert Protocol__InsufficientBalance();

            if (
                IERC20(_loanCurrency).allowance(msg.sender, address(this)) <
                _amount
            ) revert Protocol__InsufficientAllowance();
        }

        // If using the native token, set the amount to the value sent with the transaction
        if (_loanCurrency == Constants.NATIVE_TOKEN) {
            _amount = msg.value;
        }

        // Transfer the specified amount from the user to the contract if using a token
        if (_loanCurrency != Constants.NATIVE_TOKEN) {
            IERC20(_loanCurrency).transferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }

        // Create and encode payload for cross-chain message
        ActionPayload memory payload;
        payload.action = Action.CreateListing;
        payload.assetAddress = _loanCurrency;
        payload.assetAmount = _amount;
        payload.sender = msg.sender;
        payload.returnDate = _returnDate;
        payload.min_amount = _min_amount;
        payload.max_amount = _max_amount;
        payload.interest = _interest;

        bytes memory _payload = Message._encodeActionPayload(payload);

        // Send the token with payload to the target chain
        sendTokenWithPayloadToEvm(
            _targetChain,
            _targetAddress,
            _payload,
            0, // No native tokens sent
            Constants.GAS_LIMIT,
            _loanCurrency,
            _amount,
            currentChainId, // remember to change with the current chain it was sent
            msg.sender // Refund address is this contract
        );
        emit Spoke__createLoanListing(
            _targetChain,
            _amount,
            msg.sender,
            _loanCurrency
        );
    }

    /**
     * @dev Allows a borrower to request a loan from an open listing.
     *  * @param _targetChain The ID of the target chain where the loan listing will be published.
     * @param _targetAddress The address on the target chain that will receive the loan listing details.
     * @param _listingId The unique identifier of the loan listing.
     * @param _amount The requested loan amount.
     *
     * Requirements:
     * - `_amount` must be greater than zero.
     * - The listing must be open, not created by the borrower, and within min/max constraints.
     * - The borrower must have sufficient collateral to meet the health factor.
     *
     * Emits:
     * - `RequestCreated` when a loan request is successfully created.
     * - `RequestServiced` when the loan request is successfully serviced.
     */
    function requestLoanFromListing(
        uint16 _targetChain,
        address _targetAddress,
        uint96 _listingId,
        uint256 _amount
    ) external payable {
        uint256 cost = _quoteCrossChainCost(_targetChain);

        uint16 currentChainId = _getChainId(address(this));
        if (currentChainId < 1) revert spoke__InvalidSpokeChainId();

        if (msg.value < cost) revert spoke__InsufficientGasFee();

        // Create and encode payload for cross-chain message
        ActionPayload memory payload;
        payload.action = Action.RequestFromLoan;
        payload.sender = msg.sender;
        payload.id = _listingId;
        payload.assetAmount = _amount;

        bytes memory _payload = Message._encodeActionPayload(payload);

        _sendPayloadToEvm(
            _targetChain,
            _targetAddress,
            _payload,
            currentChainId,
            cost
        );

        emit Spoke__requestLoanFromListing(
            _targetChain,
            _listingId,
            msg.sender,
            _amount
        );
    }

    /**
     * @dev Allows a borrower to repay a loan in part or in full.
     * @param _targetChain The ID of the target chain where the loan listing will be published.
     * @param _targetAddress The address on the target chain that will receive the loan listing details.
     * @param _requestId The unique identifier of the loan request.
     * @param _amount The repayment amount.
     *
     * Requirements:
     * - `_amount` must be greater than zero.
     * - The loan request must be in the SERVICED status.
     * - The caller must be the borrower who created the loan request.
     * - If repaying in a token, the borrower must have sufficient balance and allowance.
     *
     * Emits:
     * - `LoanRepayment` upon successful repayment.
     */
    function repayLoan(
        uint16 _targetChain,
        address _targetAddress,
        uint96 _requestId,
        uint256 _amount
    ) external payable {
        uint256 cost = _quoteCrossChainCost(_targetChain);

        uint16 currentChainId = _getChainId(address(this));
        if (currentChainId < 1) revert spoke__InvalidSpokeChainId();

        if (msg.value < cost) revert spoke__InsufficientGasFee();

        // Create and encode payload for cross-chain message
        ActionPayload memory payload;
        payload.action = Action.Repay;
        payload.sender = msg.sender;
        payload.id = _requestId;
        payload.assetAmount = _amount;

        bytes memory _payload = Message._encodeActionPayload(payload);

        _sendPayloadToEvm(
            _targetChain,
            _targetAddress,
            _payload,
            currentChainId,
            cost
        );

        emit Spoke__RepayLoan(_targetChain, _requestId, msg.sender, _amount);
    }

    /**
     * @dev Retrieves the chain ID associated with a given spoke contract address.
     *
     * @param _spokeContractAddress The address of the spoke contract.
     * @return chainId_ The chain ID linked to the provided spoke contract address.
     */
    function _getChainId(
        address _spokeContractAddress
    ) private view returns (uint16 chainId_) {
        chainId_ = s_spokeProtocols[_spokeContractAddress];
    }

    /**
     * @dev Registers provider information for the spoke contract, linking it to essential
     *      cross-chain infrastructure like Wormhole, token bridges, and Circle token messenger.
     *
     * @param _chainId The chain ID for the spoke contract being registered.
     * @param _wormhole The Wormhole contract address for cross-chain interactions.
     * @param _tokenBridge The token bridge address for asset transfers.
     * @param _wormholeRelayer The Wormhole relayer address for relayed messages.
     * @param _circleTokenMessenger The Circle token messenger for token transfers.
     * @param _circleMessageTransmitter The Circle message transmitter for cross-chain messaging.
     *
     * Requirements:
     * - `_chainId` must match the chain ID associated with the contract's address.
     * - Only callable by an external address.
     *
     * Emits an event for successful provider registration.
     */
    function registerSpokeContractProvider(
        uint16 _chainId,
        address payable _wormhole,
        address _tokenBridge,
        address _wormholeRelayer,
        address _circleTokenMessenger,
        address _circleMessageTransmitter
    ) external {
        uint16 currentChainId = _getChainId(address(this));
        if (currentChainId != _chainId) revert spoke__InvalidSpokeChainId();

        Provider storage provider = s_spokeProtocolProvider[address(this)];
        provider.chainId = _chainId;
        provider.wormhole = _wormhole;
        provider.tokenBridge = _tokenBridge;
        provider.wormholeRelayer = _wormholeRelayer;
        provider.circleTokenMessenger = _circleTokenMessenger;
        provider.circleMessageTransmitter = _circleMessageTransmitter;

        emit ProviderRegistered(_chainId, address(this));
    }

    /**
     * @dev Publicly accessible function to retrieve the estimated cost of a cross-chain transaction to the target chain.
     *
     * @param _targetChain The target chain ID for the cross-chain transaction.
     * @return deliveryCost The estimated delivery cost for the transaction.
     */
    function quoteCrossChainCost(
        uint16 _targetChain
    ) external view returns (uint256 deliveryCost) {
        deliveryCost = _quoteCrossChainCost(_targetChain);
    }

    /**
     * @dev Private function to calculate the delivery cost for a cross-chain transaction,
     *      including the message fee for Wormhole.
     *
     * @param targetChain The target chain ID for the cross-chain transaction.
     * @return cost The total calculated cost of the transaction.
     */
    function _quoteCrossChainCost(
        uint16 targetChain
    ) private view returns (uint256 cost) {
        uint256 deliveryCost;
        (deliveryCost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            0,
            Constants.GAS_LIMIT
        );

        cost = deliveryCost + wormhole.messageFee();
    }

    receive() external payable {}
}
