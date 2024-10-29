// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibBytes} from "../../libraries/LibBytes.sol";
import {LibXGetters} from "../../libraries/LibXGetters.sol";
import {XSetters} from "./XSetters.sol";
import {IWormhole} from "../../interfaces/IWormhole.sol";
import "../../model/Protocol.sol";

/**
 * @title WormholeUtilities
 * @author Lendbit Finance
 *
 * @dev Utility contract for facilitating interactions with the Wormhole protocol and Token Bridge.
 * Contains internal functions for token transfers, message publishing, payload handling, and
 * asset amount normalization for cross-chain token transfers.
 */
contract WormholeUtilities is XSetters {
    using LibBytes for bytes;

    /**
     * @dev Transfers tokens across chains using the Wormhole Token Bridge.
     * Approves and initiates a token transfer to the specified receiver on a different chain.
     *
     * @param receiver The address on the recipient chain to receive the tokens.
     * @param assetAddress The address of the token contract.
     * @param amount The amount of tokens to be transferred.
     * @param recipientChain The chain ID of the recipient chain.
     * @return sequence The sequence number of the transfer transaction.
     */
    function _transferTokens(
        address receiver,
        address assetAddress,
        uint256 amount,
        uint16 recipientChain
    ) internal returns (uint64 sequence) {
        IERC20(assetAddress).approve(
            LibXGetters._tokenBridgeAddress(_appStorage),
            amount
        );
        sequence = LibXGetters._tokenBridge(_appStorage).transferTokens(
            assetAddress,
            amount,
            recipientChain,
            bytes32(uint256(uint160(receiver))),
            0,
            0
        );
    }

    /**
     * @dev Publishes a message to the Wormhole network.
     * This function allows sending arbitrary payloads across chains via Wormhole.
     *
     * @param payload The data payload to be sent in the message.
     * @return sequence The sequence number of the message.
     */
    function _sendWormholeMessage(
        bytes memory payload
    ) internal returns (uint64 sequence) {
        sequence = LibXGetters._wormhole(_appStorage).publishMessage(
            0, // nonce
            payload,
            LibXGetters._consistencyLevel(_appStorage)
        );
    }

    /**
     * @dev Extracts the action payload from an encoded transfer message.
     * Parses and verifies the Wormhole VM message and checks if the sender is the correct spoke contract.
     *
     * @param encodedMessage The encoded message to parse and verify.
     * @return payload The extracted action payload.
     */
    function _getTransferPayload(
        bytes memory encodedMessage
    ) internal returns (bytes memory payload) {
        (IWormhole.VM memory parsed, , ) = LibXGetters
            ._wormhole(_appStorage)
            .parseAndVerifyVM(encodedMessage);

        _verifySenderIsSpoke(
            parsed.emitterChainId,
            address(
                uint160(
                    uint256(parsed.payload.toBytes32(1 + 32 + 32 + 2 + 32 + 2))
                )
            )
        );

        payload = LibXGetters
            ._tokenBridge(_appStorage)
            .completeTransferWithPayload(encodedMessage);
    }

    /**
     * @dev Parses and verifies an encoded message to retrieve the Wormhole VM data.
     * Ensures the message is valid and has not been previously consumed.
     *
     * @param encodedMessage The encoded message to parse and verify.
     * @return parsed The parsed and verified VM data.
     */
    function _getWormholeParsed(
        bytes memory encodedMessage
    ) internal returns (IWormhole.VM memory) {
        (
            IWormhole.VM memory parsed,
            bool valid,
            string memory reason
        ) = LibXGetters._wormhole(_appStorage).parseAndVerifyVM(encodedMessage);
        require(valid, reason);

        require(
            !LibXGetters._messageHashConsumed(_appStorage, parsed.hash),
            "message already consumed"
        );
        _consumeMessageHash(parsed.hash);

        return parsed;
    }

    /**
     * @dev Extracts the payload from the TransferWithPayload message for further processing.
     * Skips metadata and focuses on the serialized data in the message.
     *
     * @param encodedVM The encoded VM message containing the transfer payload.
     * @return serialized The extracted serialized payload data.
     */
    function _extractPayloadFromTransferPayload(
        bytes memory encodedVM
    ) internal pure returns (bytes memory serialized) {
        uint256 index = 0;
        uint256 end = encodedVM.length;

        // Pass through TransferWithPayload metadata to arbitrary serialized bytes
        index += 1 + 32 + 32 + 2 + 32 + 2 + 32;

        return encodedVM.slice(index, end - index);
    }

    /**
     * @dev Verifies that the sender of the message is the authorized spoke contract on the given chain.
     *
     * @param chainId The chain ID of the sender's network.
     * @param sender The address of the sender to verify.
     */
    function _verifySenderIsSpoke(
        uint16 chainId,
        address sender
    ) internal view {
        require(
            LibXGetters._getSpokeContract(_appStorage, chainId) == sender,
            "Invalid spoke"
        );
    }

    /**
     * @dev Normalizes the token amount to meet the Wormhole Token Bridge standard of 8 decimals.
     * Adjusts the asset's amount to 8 decimals for compatibility with Token Bridge.
     *
     * @param amount The amount of the asset.
     * @param decimals The decimals of the asset.
     * @param round Determines rounding direction in case of remainder.
     * @return The normalized amount with up to 8 decimals.
     */
    function _normalizeAmountTokenBridge(
        uint256 amount,
        uint8 decimals,
        Round round
    ) internal pure returns (uint256) {
        uint256 newAmount = amount;
        if (decimals > 8) {
            newAmount /= 10 ** (decimals - 8);
        }
        if (amount % (10 ** (decimals - 8)) != 0 && round == Round.UP) {
            newAmount += 1;
        }
        return newAmount;
    }

    /**
     * @dev Denormalizes a normalized token amount from 8 decimals to the asset's true decimals.
     * Converts from Token Bridge’s standardized 8 decimals to the original decimals.
     *
     * @param amount The normalized amount.
     * @param decimals The original decimals of the asset.
     * @return The denormalized amount.
     */
    function _denormalizeAmountTokenBridge(
        uint256 amount,
        uint8 decimals
    ) internal pure returns (uint256) {
        if (decimals > 8) {
            amount *= 10 ** (decimals - 8);
        }
        return amount;
    }
}
