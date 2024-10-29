// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {AppStorage} from "./AppStorage.sol";

contract XSetters is AppStorage {
    function _setChainId(uint16 chainId) internal {
        _appStorage.provider.chainId = chainId;
    }

    function _setWormhole(address wormholeAddress) internal {
        _appStorage.provider.wormhole = payable(wormholeAddress);
    }

    function _setTokenBridge(address tokenBridgeAddress) internal {
        _appStorage.provider.tokenBridge = tokenBridgeAddress;
    }

    function _setConsistencyLevel(uint8 consistencyLevel) internal {
        _appStorage.consistencyLevel = consistencyLevel;
    }

    function _registerSpokeContract(
        uint16 chainId,
        address spokeContractAddress
    ) internal {
        _appStorage.s_spokeProtocols[chainId] = spokeContractAddress;
    }

    function _consumeMessageHash(bytes32 vmHash) internal {
        _appStorage.s_consumedMessages[vmHash] = true;
    }
}
