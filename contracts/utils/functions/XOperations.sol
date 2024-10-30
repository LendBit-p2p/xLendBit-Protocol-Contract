// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {XOperationsImpl} from "./XOperationsImpl.sol";
import {LibDiamond} from "../../libraries/LibDiamond.sol";
import {IWormhole} from "../../interfaces/IWormhole.sol";
import {Validator} from "../validators/Validator.sol";
import "../../model/Protocol.sol";

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
        } esle if (action == Action.ServiceRequest) {
            TokenReceived memory token = _vetTokenAndUnwrap(_receivedTokens);
            _serviceRequest(payload.id, token.tokenAddress, payload.sender, _sourceChain, token.amount);
        }
    }
}
