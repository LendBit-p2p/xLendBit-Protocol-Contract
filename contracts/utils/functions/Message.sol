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
    function _encodeActionPayload(
        ActionPayload memory payload
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                uint8(payload.action),
                payload.interest,
                payload.id,
                payload.sender,
                payload.assetAddress,
                payload.assetAmount,
                payload.returnDate,
                payload.min_amount,
                payload.max_amount
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
    function _decodeActionPayload(
        bytes memory serialized
    ) internal pure returns (ActionPayload memory params) {
        (
            uint8 action,
            uint16 interest,
            uint96 id,
            address payable sender,
            address assetAddress,
            uint256 assetAmount,
            uint256 returnDate,
            uint256 min_amount,
            uint256 max_amount
        ) = abi.decode(
                serialized,
                (uint8, uint16, uint96, address, address, uint256, uint256)
            );
        params = ActionPayload(
            Action(action),
            interest,
            id,
            sender,
            assetAddress,
            assetAmount,
            returnDate,
            min_amount,
            max_amount
        );
    }
}
