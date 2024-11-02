// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../model/Event.sol";
import "../model/Protocol.sol";
import "../utils/validators/Error.sol";
import "lib/wormhole-solidity-sdk/src/interfaces/IERC20.sol";
import "lib/wormhole-solidity-sdk/src/interfaces/IWormholeRelayer.sol";
import "lib/wormhole-solidity-sdk/src/WormholeRelayerSDK.sol";
import {Validator} from "../utils/validators/Validator.sol";
import {Constants} from "../utils/constants/Constant.sol";
import {Message} from "../utils/functions/Message.sol";
import {IWETH} from "../interfaces/IWETH.sol";

abstract contract SpokeInternals is CCTPAndTokenReceiver, Message {
    address immutable i_WETH;

    /**
     * @dev Sends an encoded payload to a specified `_targetChain` and `_targetAddress`.
     *
     * @param _targetChain The target chain ID for cross-chain message.
     * @param _targetAddress The address on the target chain to receive the payload.
     * @param _payload The encoded payload data to be sent.
     * @param _currentChainId The current chain ID where the function is executed.
     * @param _costFee The gas fee for cross-chain messaging.
     */
    function _sendPayloadToEvm(
        uint16 _targetChain,
        address _targetAddress,
        bytes memory _payload,
        uint16 _currentChainId,
        uint256 _costFee
    ) internal {
        wormholeRelayer.sendPayloadToEvm{value: _costFee}(
            _targetChain,
            _targetAddress,
            _payload,
            0,
            Constants.GAS_LIMIT,
            _currentChainId,
            msg.sender
        );
    }

    /**
     * @dev Private function to calculate the delivery cost for a cross-chain transaction,
     *      including the message fee for Wormhole.
     *
     * @param targetChain The target chain ID for the cross-chain transaction.
     * @return cost The total calculated cost of the transaction.
     */
    function _quoteCrossChainCost(
        uint16 targetChain
    ) internal view returns (uint256 cost) {
        uint256 deliveryCost;
        (deliveryCost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            0,
            Constants.GAS_LIMIT
        );

        cost = deliveryCost + wormhole.messageFee();
    }

    function receivePayloadAndTokens(
        bytes memory _payload,
        TokenReceived[] memory _receivedTokens,
        bytes32 _sourceAddress,
        uint16 _sourceChain,
        bytes32 _deliveryHash
    ) internal override {
        Validator._isWormholeRelayer(address(wormholeRelayer), msg.sender);

        ActionPayload memory payload = _decodeActionPayload(_payload);
        Action action = Action(payload.action);

        if (action == Action.Credit) {
            TokenReceived memory token = _vetTokenAndUnwrap(_receivedTokens);
            if (token.tokenAddress == Constants.NATIVE_TOKEN) {
                (bool _success, ) = payable(payload.sender).call{
                    value: token.amount
                }("");
                require(_success);
            } else {
                IERC20(token.tokenAddress).transfer(
                    payload.sender,
                    token.amount
                );
            }
        }
    }
    function receivePayloadAndUSDC(
        bytes memory payload,
        uint256 amountUSDCReceived,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) internal override {
        TokenReceived[] memory _receivedTokens = new TokenReceived[](1);
        _receivedTokens[0] = TokenReceived(
            sourceAddress,
            sourceChain,
            Constants.USDC,
            amountUSDCReceived,
            amountUSDCReceived
        );

        receivePayloadAndTokens(
            payload,
            _receivedTokens,
            sourceAddress,
            sourceChain,
            deliveryHash
        );
    }

    function _vetTokenAndUnwrap(
        TokenReceived[] memory _tokenReceived
    ) internal returns (TokenReceived memory _token) {
        if (_tokenReceived.length != 1) {
            revert Protocol__InvalidAction();
        }
        _token = _tokenReceived[0];

        if (_token.tokenAddress == i_WETH) {
            IWETH(i_WETH).withdraw(_token.amount);
            _token.tokenAddress = Constants.NATIVE_TOKEN;
        }
    }
}
