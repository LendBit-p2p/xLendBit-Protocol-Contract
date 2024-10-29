// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {LibBytes} from "../../libraries/LibBytes.sol";
import "../../model/Protocol.sol";

/**
 * @title Message
 * @author LendBit Finance
 *
 * @dev Provides utility functions to encode and decode action payloads for cross-contract communication.
 * This contract uses the `LibBytes` library to help with encoding and decoding data in `bytes` format.
 * It is designed to handle payload data structures and facilitate actions between contracts in the protocol.
 */
contract Message {
    using LibBytes for bytes;

    /**
     * @dev Encodes an `ActionPayload` struct into a bytes format.
     * This function prepares the payload for cross-contract or cross-chain communication.
     *
     * @param payload The `ActionPayload` struct containing the action type, sender, asset address, and asset amount.
     * @return A `bytes` memory containing the packed action payload.
     *
     * Encodes:
     * - `payload.action` as a uint8 to represent the type of action.
     * - `payload.sender` as the sender’s address.
     * - `payload.assetAddress` as the address of the asset involved.
     * - `payload.assetAmount` as the amount of the asset involved in the action.
     */
    function encodeActionPayload(
        ActionPayload memory payload
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(payload.action),
                payload.sender,
                payload.assetAddress,
                payload.assetAmount
            );
    }

    /**
     * @dev Decodes a serialized `bytes` payload into an `ActionPayload` struct.
     * This function extracts the data from a `bytes` array to reconstruct the `ActionPayload` structure.
     *
     * @param serialized The encoded `bytes` array containing the serialized `ActionPayload`.
     * @return params The decoded `ActionPayload` struct with all fields populated.
     *
     * Decodes:
     * - `action` as the action type represented by a uint8.
     * - `sender` as the address that initiated the action.
     * - `assetAddress` as the address of the asset.
     * - `assetAmount` as the amount of the asset.
     */
    function decodeActionPayload(
        bytes memory serialized
    ) internal pure returns (ActionPayload memory params) {
        uint256 index = 0;

        // Decode each part of the payload in sequence and update the index
        params.action = Action(serialized.toUint8(index));
        index += 1;

        params.sender = serialized.toAddress(index);
        index += 20;

        params.assetAddress = serialized.toAddress(index);
        index += 20;

        params.assetAmount = serialized.toUint256(index);
    }
}
