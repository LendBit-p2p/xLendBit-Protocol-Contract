// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {AppStorage} from "./AppStorage.sol";

/**
 * @title XSetters
 * @author Lendbit Finance
 *
 * @dev Contains setter functions for managing key configuration parameters in the AppStorage.
 * Enables internal updates to chain identifiers, Wormhole-related addresses, consistency levels,
 * spoke contract registration, and message hash tracking.
 */
contract XSetters is AppStorage {
    /**
     * @dev Sets the chain ID for the provider.
     * @param chainId The chain ID to be set.
     */
    function _setChainId(uint16 chainId) internal {
        _appStorage.provider.chainId = chainId;
    }

    /**
     * @dev Sets the Wormhole contract address for the provider.
     * The Wormhole address is set as payable to support ETH transfers if necessary.
     * @param wormholeAddress The address of the Wormhole contract.
     */
    function _setWormhole(address wormholeAddress) internal {
        _appStorage.provider.wormhole = payable(wormholeAddress);
    }

    /**
     * @dev Sets the Token Bridge contract address for the provider.
     * This contract handles cross-chain token transfers.
     * @param tokenBridgeAddress The address of the Token Bridge contract.
     */
    function _setTokenBridge(address tokenBridgeAddress) internal {
        _appStorage.provider.tokenBridge = tokenBridgeAddress;
    }

    /**
     * @dev Sets the consistency level for cross-chain messaging.
     * The consistency level dictates the security requirements for message confirmation on Wormhole.
     * @param consistencyLevel The level of consistency (e.g., 1, 2).
     */
    function _setConsistencyLevel(uint8 consistencyLevel) internal {
        _appStorage.consistencyLevel = consistencyLevel;
    }

    /**
     * @dev Registers a spoke contract for a specific chain ID.
     * Used to verify valid sending addresses for cross-chain interactions.
     * @param chainId The chain ID associated with the spoke contract.
     * @param spokeContractAddress The address of the spoke contract to register.
     */
    function _registerSpokeContract(
        uint16 chainId,
        address spokeContractAddress
    ) internal {
        _appStorage.s_spokeProtocols[chainId] = spokeContractAddress;
    }

    /**
     * @dev Marks a message hash as consumed, preventing reuse.
     * Helps prevent replay attacks by ensuring each message hash is only processed once.
     * @param vmHash The hash of the virtual machine (VM) message to be marked as consumed.
     */
    function _consumeMessageHash(bytes32 vmHash) internal {
        _appStorage.s_consumedMessages[vmHash] = true;
    }
}
