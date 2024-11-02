// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "lib/wormhole-solidity-sdk/src/interfaces/IERC20.sol";
import "lib/wormhole-solidity-sdk/src/interfaces/IWormholeRelayer.sol";
import "lib/wormhole-solidity-sdk/src/WormholeRelayerSDK.sol";
import {Validator} from "../utils/validators/Validator.sol";
import {Constants} from "../utils/constants/Constant.sol";
import "../model/Protocol.sol";
import {Message} from "../utils/functions/Message.sol";
import {IWETH} from "../interfaces/IWETH.sol";
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
    mapping(address s_tokens => address h_tokens) s_spokeToHubTokens;

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

    function depositCollateral(
        address _assetAddress,
        uint256 _amount
    ) external payable _isTokenValid(_assetAddress) {
        Validator._valueMoreThanZero(_amount, _assetAddress, msg.value);

        uint256 cost = _quoteCrossChainCost(s_hubChainId);

        if (msg.value < cost) revert spoke__InsufficientGasFee();

        if (_assetAddress == Constants.NATIVE_TOKEN) {
            _amount = msg.value - cost;
            _assetAddress = i_WETH;
            IWETH(i_WETH).deposit{value: _amount}();
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
                _payload,
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
            s_hubChainId,
            _amount,
            msg.sender,
            _assetAddress
        );
    }

    function createLendingRequest(
        uint16 _interest,
        uint256 _returnDate,
        address _loanAddress,
        uint256 _amount
    ) external payable {
        Validator._moreThanZero(_amount);
        Validator._isTokenAllowed(_loanAddress);

        uint256 cost = _quoteCrossChainCost(s_hubChainId);

        if (msg.value < cost) revert spoke__InsufficientGasFee();

        // Create and encode payload for cross-chain message
        ActionPayload memory payload;
        payload.action = Action.CreateRequest;
        payload.assetAddress = s_spokeToHubTokens[_loanAddress];
        payload.assetAmount = _amount;
        payload.sender = msg.sender;
        payload.interest = _interest;
        payload.returnDate = _returnDate;

        bytes memory _payload = Message._encodeActionPayload(payload);

        _sendPayloadToEvm(
            s_hubChainId,
            s_hubChainAddress,
            _payload,
            i_chainId,
            cost
        );

        emit Spoke__CreateRequest(
            s_hubChainId,
            _amount,
            msg.sender,
            _loanAddress
        );
    }

    function serviceRequest(
        uint96 _requestId,
        address _tokenAddress,
        uint256 _amount
    ) external payable {
        uint256 cost = _quoteCrossChainCost(s_hubChainId);

        if (msg.value < cost) revert spoke__InsufficientGasFee();

        if (_tokenAddress == Constants.NATIVE_TOKEN) {
            _amount = msg.value - cost;
            _tokenAddress = i_WETH;
            IWETH(i_WETH).deposit{value: _amount}();
        } else {
            bool success = IERC20(_tokenAddress).transferFrom(
                msg.sender,
                address(this),
                _amount
            );
            require(success, "Token transfer failed");
        }

        // Create and encode payload for cross-chain message
        ActionPayload memory payload;
        payload.action = Action.ServiceRequest;
        payload.assetAddress = _tokenAddress;
        payload.assetAmount = _amount;
        payload.sender = msg.sender;
        payload.id = _requestId;

        bytes memory _payload = Message._encodeActionPayload(payload);

        if (_tokenAddress == i_USDC) {
            sendUSDCWithPayloadToEvm(
                s_hubChainId,
                s_hubChainAddress,
                _payload,
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
                _tokenAddress,
                _amount,
                i_chainId,
                msg.sender // Refund address is this contract
            );
        }

        emit Spoke__ServiceRequest(
            s_hubChainId,
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

    function withdrawnCollateral(
        address _tokenCollateralAddress,
        uint128 _amount
    ) external payable {
        uint256 cost = _quoteCrossChainCost(s_hubChainId);

        if (msg.value < cost) revert spoke__InsufficientGasFee();

        // Create and encode payload for cross-chain message
        ActionPayload memory payload;
        payload.action = Action.Withdraw;
        payload.assetAddress = s_spokeToHubTokens[_tokenCollateralAddress];
        payload.assetAmount = _amount;
        payload.sender = msg.sender;

        bytes memory _payload = Message._encodeActionPayload(payload);

        _sendPayloadToEvm(
            s_hubChainId,
            s_hubChainAddress,
            _payload,
            i_chainId,
            cost
        );

        emit Spoke__WithrawnCollateral(
            s_hubChainId,
            s_hubChainAddress,
            msg.sender,
            _tokenCollateralAddress
        );
    }

    function createLoanListing(
        uint256 _amount,
        uint256 _min_amount,
        uint256 _max_amount,
        uint256 _returnDate,
        uint16 _interest,
        address _loanCurrency
    ) external payable {
        Validator._valueMoreThanZero(_amount, _loanCurrency, msg.value);

        uint256 cost = _quoteCrossChainCost(s_hubChainId);

        if (msg.value < cost) revert spoke__InsufficientGasFee();

        // Check for sufficient balance and allowance if using a token other than native
        if (_loanCurrency == Constants.NATIVE_TOKEN) {
            _amount = msg.value - cost;
            _loanCurrency = i_WETH;
            IWETH(i_WETH).deposit{value: _amount}();
        } else {
            if (IERC20(_loanCurrency).balanceOf(msg.sender) < _amount)
                revert Protocol__InsufficientBalance();

            if (
                IERC20(_loanCurrency).allowance(msg.sender, address(this)) <
                _amount
            ) revert Protocol__InsufficientAllowance();

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

        if (_loanCurrency == i_USDC) {
            sendUSDCWithPayloadToEvm(
                s_hubChainId,
                s_hubChainAddress,
                _payload,
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
                _loanCurrency,
                _amount,
                i_chainId,
                msg.sender // Refund address is this contract
            );
        }

        emit Spoke__createLoanListing(
            s_hubChainId,
            _amount,
            msg.sender,
            _loanCurrency
        );
    }

    function requestLoanFromListing(
        uint96 _listingId,
        uint256 _amount
    ) external payable {
        uint256 cost = _quoteCrossChainCost(s_hubChainId);

        if (msg.value < cost) revert spoke__InsufficientGasFee();

        // Create and encode payload for cross-chain message
        ActionPayload memory payload;
        payload.action = Action.RequestFromLoan;
        payload.sender = msg.sender;
        payload.id = _listingId;
        payload.assetAmount = _amount;

        bytes memory _payload = Message._encodeActionPayload(payload);

        _sendPayloadToEvm(
            s_hubChainId,
            s_hubChainAddress,
            _payload,
            i_chainId,
            cost
        );

        emit Spoke__requestLoanFromListing(
            s_hubChainId,
            _listingId,
            msg.sender,
            _amount
        );
    }

    function repayLoan(
        uint96 _requestId,
        uint256 _amount,
        address _loanCurrency
    ) external payable {
        Validator._valueMoreThanZero(_amount, _loanCurrency, msg.value);

        uint256 cost = _quoteCrossChainCost(s_hubChainId);

        if (msg.value < cost) revert spoke__InsufficientGasFee();

        if (_loanCurrency == Constants.NATIVE_TOKEN) {
            _amount = msg.value - cost;
            _loanCurrency = i_WETH;
            IWETH(i_WETH).deposit{value: _amount}();
        } else {
            if (IERC20(_loanCurrency).balanceOf(msg.sender) < _amount)
                revert Protocol__InsufficientBalance();

            if (
                IERC20(_loanCurrency).allowance(msg.sender, address(this)) <
                _amount
            ) revert Protocol__InsufficientAllowance();

            IERC20(_loanCurrency).transferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }

        // Create and encode payload for cross-chain message
        ActionPayload memory payload;
        payload.action = Action.Repay;
        payload.sender = msg.sender;
        payload.id = _requestId;
        payload.assetAmount = _amount;
        payload.assetAddress = _loanCurrency;

        bytes memory _payload = Message._encodeActionPayload(payload);

        if (_loanCurrency == i_USDC) {
            sendUSDCWithPayloadToEvm(
                s_hubChainId,
                s_hubChainAddress,
                _payload,
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
                _loanCurrency,
                _amount,
                i_chainId,
                msg.sender // Refund address is this contract
            );
        }

        emit Spoke__RepayLoan(s_hubChainId, _requestId, msg.sender, _amount);
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
