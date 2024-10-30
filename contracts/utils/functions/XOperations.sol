// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Message} from "./Message.sol";
import {XOperationsImpl} from "./XOperationsImpl.sol";
import {LibDiamond} from "../../libraries/LibDiamond.sol";
import {IWormhole} from "../../interfaces/IWormhole.sol";
import "../../model/Protocol.sol";

contract XOperations is Message, XOperationsImpl {
    /**
     * @notice Registers a spoke contract. Only wormhole messages from registered spoke contracts are allowed.
     *
     * @param chainId - The chain id which the spoke is deployed on
     * @param spokeContractAddress - The address of the spoke contract on its chain
     */
    function registerSpoke(
        uint16 chainId,
        address spokeContractAddress
    ) external {
        LibDiamond.enforceIsContractOwner();
        _registerSpokeContract(chainId, spokeContractAddress);
    }

    /**
     * @notice Completes a deposit that was initiated on a spoke
     * @param encodedMessage: encoded Wormhole message with a TokenBridge message as the payload
     * The TokenBridge message is used to complete a TokenBridge transfer of tokens to the Hub,
     * and contains a payload of the deposit information
     */
    function completeDeposit(bytes memory _encodedMessage) public {
        completeAction(_encodedMessage, true);
    }

    function completeCreateRequest(bytes memory encodedMessage) public {
        completeAction(encodedMessage, false);
    }

    /**
     * @notice Completes a withdraw that was initiated on a spoke
     * @param encodedMessage: encoded Wormhole message with withdraw information as the payload
     */
    function completeWithdraw(bytes memory encodedMessage) public {
        completeAction(encodedMessage, false);
    }

    function completeServiceRequest(bytes memory encodedMessage) public {
        completeAction(encodedMessage, false);
    }

    function completeCreateListing(bytes memory encodedMessage) public {
        completeAction(encodedMessage, false);
    }

    function completeRequestFromLoan(bytes memory encodedMessage) public {
        completeAction(encodedMessage, false);
    }

    /**
     * @notice Completes a repay that was initiated on a spoke
     * @param encodedMessage: encoded Wormhole message with a TokenBridge message as the payload
     * The TokenBridge message is used to complete a TokenBridge transfer of tokens to the Hub,
     * and contains a payload of the repay information
     */
    function completeRepay(bytes memory encodedMessage) public {
        completeAction(encodedMessage, true);
    }

    function completeAction(
        bytes memory _encodedMessage,
        bool _isTokenBridgePayload
    ) internal returns (bool completed, uint64 sequence) {
        bytes memory encodedActionPayload;
        IWormhole.VM memory parsed = _getWormholeParsed(_encodedMessage);

        if (_isTokenBridgePayload) {
            encodedActionPayload = _extractPayloadFromTransferPayload(
                _getTransferPayload(_encodedMessage)
            );
        } else {
            _verifySenderIsSpoke(
                parsed.emitterChainId,
                address(uint160(uint256(parsed.emitterAddress)))
            );
            encodedActionPayload = parsed.payload;
        }

        ActionPayload memory params = _decodeActionPayload(
            encodedActionPayload
        );
        Action action = Action(params.action);

        checkValidAddress(params.assetAddress);
        completed = true;
        bool transferTokensToSender = false;

        if (action == Action.Withdraw) {
            transferTokensToSender = true;
        } else if (action == Action.ServiceRequest) {
            _serviceRequest();
        } else if (
            action == Action.CreateListing
        ) {} else if (action == Action.RequestFromLoan) {} else if (
            action == Action.Repay
        ) {
            completed = allowedToRepay(
                params.sender,
                params.assetAddress,
                params.assetAmount
            );
            if (!completed) {
                transferTokensToSender = true;
            }
        }

        if (completed) {
            logActionOnHub(
                action,
                params.sender,
                params.assetAddress,
                params.assetAmount,
                parsed.emitterChainId
            );
        }

        if (transferTokensToSender) {
            sequence = transferTokens(
                params.sender,
                params.assetAddress,
                params.assetAmount,
                parsed.emitterChainId
            );
        }
    }

    /**
     * @notice Updates the vault's state to log either a deposit, borrow, withdraw, or repay
     *
     * @param action - the action (either Deposit, Borrow, Withdraw, or Repay)
     * @param vault - the address of the vault
     * @param assetAddress - the address of the relevant asset being logged
     * @param amount - the amount of the asset assetAddress being logged
     */
    function logActionOnHub(
        Action action,
        address _msgSender,
        address _assetAddress,
        uint256 _amount,
        uint16 _chainId,
        uint16 _interest,
        uint256 _returnDate
    ) internal {
        if (action == Action.Deposit) {
            _depositCollateral(_assetAddress, _amount, _msgSender, _chainId);
        } else if (action == Action.CreateRequest) {
            _createLendingRequest(
        uint128 _amount,
        uint16 _interest,
        uint256 _returnDate,
        address _assetAddress,
        address _msgSender,
        uint16 _chainId
    );
        } else if (action == Action.Borrow) {
            uint256 normalizedBorrow = normalizeAmount(
                amount,
                indices.borrowed,
                Round.UP
            );
            vaultAmounts.borrowed += normalizedBorrow;
            globalAmounts.borrowed += normalizedBorrow;
        } else if (action == Action.Repay) {
            uint256 normalizedRepay = normalizeAmount(
                amount,
                indices.borrowed,
                Round.DOWN
            );
            if (normalizedRepay > vaultAmounts.borrowed) {
                normalizedRepay = vaultAmounts.borrowed;
            }
            vaultAmounts.borrowed -= normalizedRepay;
            globalAmounts.borrowed -= normalizedRepay;
        }
    }
}
