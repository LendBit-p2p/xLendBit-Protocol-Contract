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

contract SpokeProtocol is TokenSender, Message {
    mapping(address => uint16 chainId) s_spokeProtocols;
    mapping(address spokeContractAddress => Provider) s_spokeProtocolProvider;
    mapping(address token => bool) isTokenValid;

    constructor(
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole,
        address[] memory _tokens,
        uint16 chainId
    ) TokenBase(_wormholeRelayer, _tokenBridge, _wormhole) {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);

        if (_tokens.length < 1) revert spoke__TokenArrayCantBeEmpty();
        for (uint8 i = 0; i < _tokens.length; i++) {
            isTokenValid[_tokens[i]] = true;
        }
        s_spokeProtocols[address(this)] = chainId;
    }

    modifier ValidateChainId(uint16 _chainId) {
        uint16 currentChainId = _getChainId(address(this));
        if (currentChainId != _chainId) revert spoke__InvalidSpokeChainId();
        _;
    }

    function depositCollateral(
        uint16 _targetChain,
        address _targetAddress,
        address _assetAddress,
        uint256 _amount
    ) external payable {
        Validator._valueMoreThanZero(_amount, _assetAddress, msg.value);

        uint256 cost = _quoteCrossChainCost(_targetChain);
        uint16 currentChainId = _getChainId(address(this));
        if (currentChainId < 1) revert spoke__InvalidSpokeChainId();

        if (msg.value < cost) revert spoke__InsufficientGasFee();

        if (_assetAddress == Constants.NATIVE_TOKEN) {
            _amount = msg.value;
            _assetAddress = Constants.WETH;
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

        // Send the token with payload to the target chain
        sendTokenWithPayloadToEvm(
            _targetChain,
            _targetAddress,
            _payload,
            0, // No native tokens sent
            Constants.GAS_LIMIT,
            _assetAddress,
            _amount,
            currentChainId, // remember to change with the current chain it was sent
            msg.sender // Refund address is this contract
        );
        emit Spoke__DepositCollateral(
            _targetChain,
            _amount,
            msg.sender,
            _assetAddress
        );
    }

    function createLendingRequest(
        uint16 _targetChain,
        address _targetAddress,
        uint16 _interest,
        uint256 _returnDate,
        address _loanAddress,
        uint256 _amount
    ) external payable {
        Validator._moreThanZero(_amount);
        //todo check address zero and comment

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
    ) external payable{

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
    function repayLoan( uint16 _targetChain, address _targetAddress,uint96 _requestId, uint256 _amount) external payable {

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

        emit Spoke__RepayLoan(
            _targetChain,
            _requestId,
            msg.sender,
            _amount
        );

    }
        

    //   /**
    //  * @dev Registers a spoke contract for a specific chain ID.
    //  * Used to verify valid sending addresses for cross-chain interactions.
    //  * @param chainId The chain ID associated with the spoke contract.
    //  * @param spokeContractAddress The address of the spoke contract to register.
    //  */
    // function _registerSpokeContract(
    //     uint16 chainId,
    //     address spokeContractAddress
    // ) internal {
    //     s_spokeProtocols[chainId] = spokeContractAddress;
    // }

    function _getChainId(
        address _spokeContractAddress
    ) private view returns (uint16 chainId_) {
        chainId_ = s_spokeProtocols[_spokeContractAddress];
    }

    function registerSpokeContractProvider(
        uint16 _chainId,
        address payable _wormhole,
        address _tokenBridge,
        address _wormholeRelayer,
        address _circleTokenMessenger,
        address _circleMessageTransmitter
    ) external ValidateChainId(_chainId) {
        Provider storage provider = s_spokeProtocolProvider[address(this)];
        provider.chainId = _chainId;
        provider.wormhole = _wormhole;
        provider.tokenBridge = _tokenBridge;
        provider.wormholeRelayer = _wormholeRelayer;
        provider.circleTokenMessenger = _circleTokenMessenger;
        provider.circleMessageTransmitter = _circleMessageTransmitter;
    }

    function quoteCrossChainCost(
        uint16 _targetChain
    ) external view returns (uint256 deliveryCost) {
        deliveryCost = _quoteCrossChainCost(_targetChain);
    }

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
