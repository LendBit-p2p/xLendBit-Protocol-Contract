// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {XOperationsImpl} from "./XOperationsImpl.sol";
import {LibDiamond} from "../../libraries/LibDiamond.sol";
import {LibXGetters} from "../../libraries/LibXGetters.sol";
import {IWormhole} from "../../interfaces/IWormhole.sol";
import {Validator} from "../validators/Validator.sol";
import {Constants} from "../constants/Constant.sol";
import "../../model/Protocol.sol";
import "../validators/Error.sol";

contract XOperations is XOperationsImpl {
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

    function receivePayloadAndTokens(
        bytes memory _payload,
        TokenReceived[] memory _receivedTokens,
        bytes32 _sourceAddress,
        uint16 _sourceChain,
        bytes32 _deliveryHash
    ) internal override {
        Validator._isWormholeRelayer(
            _appStorage.provider.wormholeRelayer,
            msg.sender
        );

        _verifySenderIsSpoke(
            _sourceChain,
            address(uint160(uint256(_sourceAddress)))
        );

        if (LibXGetters._messageHashConsumed(_appStorage, _deliveryHash))
            revert Protocol__InvalidHash();
        _consumeMessageHash(_deliveryHash);

        ActionPayload memory payload = _decodeActionPayload(_payload);
        Action action = Action(payload.action);

        if (action == Action.Deposit) {
            TokenReceived memory token = _vetTokenAndUnwrap(_receivedTokens);
            _depositCollateral(
                token.tokenAddress,
                token.amount,
                payload.sender,
                _sourceChain
            );
        } else if (action == Action.CreateRequest) {
            _createLendingRequest(payload, _sourceChain);
        } else if (action == Action.ServiceRequest) {
            TokenReceived memory token = _vetTokenAndUnwrap(_receivedTokens);
            _serviceRequest(
                payload.id,
                token.tokenAddress,
                payload.sender,
                _sourceChain,
                token.amount
            );
        } else if (action == Action.Withdraw) {
            _withdrawCollateral(
                payload.assetAddress,
                payload.assetAmount,
                payload.sender,
                _sourceChain
            );
        } else if (action == Action.CreateListing) {
            TokenReceived memory token = _vetTokenAndUnwrap(_receivedTokens);
            _createLoanListing(
                token.amount,
                payload.min_amount,
                payload.max_amount,
                payload.returnDate,
                payload.interest,
                token.tokenAddress,
                payload.sender,
                _sourceChain
            );
        } else if (action == Action.RequestFromLoan) {
            _requestLoanFromListing(
                payload.id,
                payload.assetAmount,
                payload.assetAddress,
                _sourceChain
            );
        } else if (action == Action.Repay) {
            TokenReceived memory token = _vetTokenAndUnwrap(_receivedTokens);
            _repayLoan(
                payload.id,
                token.amount,
                token.tokenAddress,
                payload.sender,
                _sourceChain
            );
        }
    }
    function receivePayloadAndUSDC(
        bytes memory payload,
        uint256 amountUSDCReceived,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) internal override {
        TokenReceived[] memory _receivedTokens = new TokenReceived[](1);
        _receivedTokens[0] = TokenReceived(
            sourceAddress,
            sourceChain,
            Constants.USDC,
            amountUSDCReceived,
            amountUSDCReceived
        );

        receivePayloadAndTokens(
            payload,
            _receivedTokens,
            sourceAddress,
            sourceChain,
            deliveryHash
        );
    }
}
