// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibBytes} from "../../libraries/LibBytes.sol";
import {LibXGetters} from "../../libraries/LibXGetters.sol";
import {AppStorage} from "./AppStorage.sol";
import {IWormhole} from "../../interfaces/IWormhole.sol";
import "../../model/Protocol.sol";

contract WormholeUtilities is AppStorage {
    using LibBytes for bytes;

    function transferTokens(
        address receiver,
        address assetAddress,
        uint256 amount,
        uint16 recipientChain
    ) internal returns (uint64 sequence) {
        SafeERC20.safeApprove(
            IERC20(assetAddress),
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

    function sendWormholeMessage(
        bytes memory payload
    ) internal returns (uint64 sequence) {
        sequence = LibXGetters._wormhole(_appStorage).publishMessage(
            0, // nonce
            payload,
            LibXGetters._consistencyLevel(_appStorage)
        );
    }

    function getTransferPayload(
        bytes memory encodedMessage
    ) internal returns (bytes memory payload) {
        (IWormhole.VM memory parsed, , ) = LibXGetters
            ._wormhole(_appStorage)
            .parseAndVerifyVM(encodedMessage);

        verifySenderIsSpoke(
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

    function getWormholeParsed(
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
        consumeMessageHash(parsed.hash);

        return parsed;
    }

    function extractPayloadFromTransferPayload(
        bytes memory encodedVM
    ) internal pure returns (bytes memory serialized) {
        uint256 index = 0;
        uint256 end = encodedVM.length;

        // pass through TransferWithPayload metadata to arbitrary serialized bytes
        index += 1 + 32 + 32 + 2 + 32 + 2 + 32;

        return encodedVM.slice(index, end - index);
    }

    function verifySenderIsSpoke(uint16 chainId, address sender) internal view {
        require(
            LibXGetters._getSpokeContract(_appStorage, chainId) == sender,
            "Invalid spoke"
        );
    }

    /**
     * @notice Normalize the amount passed into Token Bridge to get the mantissa outputted. Token Bridge filters all tokens to decimals no larger than 8.
     *
     * @param amount - The amount of an asset intended to be transferred via the Token Bridge
     * @param decimals - The decimals of the asset
     * @param round - Whether to round up or round down, in case the remainder is nonzero
     * @return {uint256} The normalized amount of the asset
     */
    function normalizeAmountTokenBridge(
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
     * @notice Denormalize the amount passed into Token Bridge by converting from decimals=8 to true decimals of the asset.
     *
     * @param amount - The amount of an asset normalized by the Token Bridge
     * @param decimals - The decimals of the asset
     * @return {uint256} The denormalized amount of the asset
     */
    function denormalizeAmountTokenBridge(
        uint256 amount,
        uint8 decimals
    ) internal pure returns (uint256) {
        if (decimals > 8) {
            amount *= 10 ** (decimals - 8);
        }
        return amount;
    }
}
