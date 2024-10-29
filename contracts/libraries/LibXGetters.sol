// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {LibAppStorage} from "./LibAppStorage.sol";

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
}
