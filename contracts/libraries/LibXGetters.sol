// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {LibAppStorage} from "./LibAppStorage.sol";
import "../interfaces/IWormhole.sol";
import "../interfaces/IWormholeRelayer.sol";
import "../interfaces/ITokenBridge.sol";
import "../interfaces/ITokenMessenger.sol";
import "../interfaces/IMessageTransmitter.sol";

library LibXGetters {
    function _chainId(
        LibAppStorage.Layout storage _appStorage
    ) internal view returns (uint16) {
        return _appStorage.provider.chainId;
    }

    function _wormhole(
        LibAppStorage.Layout storage _appStorage
    ) internal view returns (IWormhole) {
        return IWormhole(_appStorage.provider.wormhole);
    }

    function _tokenBridge(
        LibAppStorage.Layout storage _appStorage
    ) public view returns (ITokenBridge) {
        return ITokenBridge(payable(_appStorage.provider.tokenBridge));
    }

    function _wormholeRelayer(
        LibAppStorage.Layout storage _appStorage
    ) public view returns (IWormholeRelayer) {
        return IWormholeRelayer(_appStorage.provider.wormholeRelayer);
    }

    function _circleTokenMessenger(
        LibAppStorage.Layout storage _appStorage
    ) public view returns (ITokenMessenger) {
        return ITokenMessenger(_appStorage.provider.circleTokenMessenger);
    }

    function _circleMessageTransmitter(
        LibAppStorage.Layout storage _appStorage
    ) public view returns (IMessageTransmitter) {
        return
            IMessageTransmitter(_appStorage.provider.circleMessageTransmitter);
    }

    function _tokenBridgeAddress(
        LibAppStorage.Layout storage _appStorage
    ) public view returns (address) {
        return _appStorage.provider.tokenBridge;
    }

    function _consistencyLevel(
        LibAppStorage.Layout storage _appStorage
    ) internal view returns (uint8) {
        return _appStorage.consistencyLevel;
    }

    function _getSpokeContract(
        LibAppStorage.Layout storage _appStorage,
        uint16 chainId
    ) internal view returns (address) {
        return _appStorage.s_spokeProtocols[chainId];
    }

    function _messageHashConsumed(
        LibAppStorage.Layout storage _appStorage,
        bytes32 vmHash
    ) internal view returns (bool) {
        return _appStorage.s_consumedMessages[vmHash];
    }
}
