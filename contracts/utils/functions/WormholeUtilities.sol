// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibBytes} from "../../libraries/LibBytes.sol";
import {LibXGetters} from "../../libraries/LibXGetters.sol";
import {XSetters} from "./XSetters.sol";
import {IWormhole} from "../../interfaces/IWormhole.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {CCTPAndTokenSender} from "./Wormhole/CCTPAndTokenBase.sol";
import {CCTPSender} from "./Wormhole/CCTPBase.sol";
import {Message} from "./Message.sol";
import {Constants} from "../constants/Constant.sol";

import "../../model/Protocol.sol";

/**
 * @title WormholeUtilities
 * @author Lendbit Finance
 *
 * @dev Utility contract for facilitating interactions with the Wormhole protocol and Token Bridge.
 * Contains internal functions for token transfers, message publishing, payload handling, and
 * asset amount normalization for cross-chain token transfers.
 */
contract WormholeUtilities is XSetters, CCTPAndTokenSender, Message {
    using LibBytes for bytes;

    function _handleTokenTransfer(
        uint16 _targetChain,
        address _targetAddress,
        bytes memory _payload,
        address _token,
        uint256 _amount
    ) internal {
        uint256 receiverValue = _amount;
        uint32 gasLimit = 400_000;

        if (_token == Constants.NATIVE_TOKEN) {
            _token = Constants.WETH;
            IWETH(_token).deposit{value: _amount}();
            _amount = _normalizeAmountTokenBridge(_amount, 18, Round.DOWN);

            sendTokenWithPayloadToEvm(
                _targetChain,
                _targetAddress,
                _payload,
                receiverValue,
                gasLimit,
                _token,
                _amount,
                _appStorage.provider.chainId,
                address(this)
            );
        } else if (_token == Constants.USDC) {}
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
