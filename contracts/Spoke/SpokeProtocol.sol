// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "lib/wormhole-solidity-sdk/src/interfaces/IERC20.sol";
import "lib/wormhole-solidity-sdk/src/interfaces/IWormholeRelayer.sol";
import "lib/wormhole-solidity-sdk/src/WormholeRelayerSDK.sol";
import {Validator} from "../utils/validators/Validator.sol";
import {Constants} from "../utils/constants/Constant.sol";
import "../model/Protocol.sol";
import {Message} from "../utils/functions/Message.sol";
import "../utils/validators/Error.sol";
import "../model/Event.sol";

contract SpokeProtocol is TokenSender, Message {

    mapping(address => uint16 chainId) s_spokeProtocols;
    mapping(address spokeContractAddress => Provider) s_spokeProtocolProvider;
    mapping(address token => bool) isTokenValid;



    constructor(
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole, 
        address [] memory _tokens,
        uint16 chainId 
    ) TokenBase(_wormholeRelayer, _tokenBridge, _wormhole) {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);

        if(_tokens.length < 1) revert spoke__TokenArrayCantBeEmpty();
        for (uint8 i = 0; i < _tokens.length; i++) {
          isTokenValid[_tokens[i]] = true;
        }
        s_spokeProtocols[address(this)] = chainId;
    }
    


    modifier ValidateChainId(uint16 _chainId){
       uint16 currentChainId = _getChainId(address(this));
        if( currentChainId != _chainId) revert  spoke__InvalidSpokeChainId();
        _;
    }











    function depositCollateral(
        uint16 _targetChain,
        address _targetAddress,
        address _assetAddress,
        uint256 _amount
    ) external payable {

           Validator._valueMoreThanZero(
            _amount,
            _assetAddress,
            msg.value
        );

        uint256 cost = _quoteCrossChainCost(_targetChain);
        uint16 currentChainId = _getChainId(address(this));
        if(currentChainId < 1) revert spoke__InvalidSpokeChainId();

        

        if(msg.value < cost) revert spoke__InsufficientGasFee();

        if (_assetAddress == Constants.NATIVE_TOKEN) {
            _amount = msg.value;
            _assetAddress = Constants.WETH;
        } else {
            bool success = IERC20(_assetAddress).transferFrom(
                msg.sender,
                address(this),
                _amount
            );
            require(success, "Token transfer failed");
        }

        // Create and encode payload for cross-chain message
        ActionPayload memory payload;
        payload.action = Action.Deposit;
        payload.assetAddress = _assetAddress;
        payload.assetAmount = _amount;
        payload.sender = msg.sender;

        bytes memory _payload = Message._encodeActionPayload(payload);

        // Send the token with payload to the target chain
        sendTokenWithPayloadToEvm(
            _targetChain,
            _targetAddress,
            _payload,
            0, // No native tokens sent
            Constants.GAS_LIMIT,
            _assetAddress,
            _amount,
            currentChainId, // remember to change with the current chain it was sent
            msg.sender // Refund address is this contract
        );
        emit Spoke__DepositCollateral(
            _targetChain,
            _amount,
             msg.sender,
            _assetAddress
        );
    }



    function createLendingRequest(
        uint16 _targetChain,
        address _targetAddress,
        uint16 _interest,
        uint256 _returnDate,
        address _loanAddress,
        uint256 _amount
    ) external payable{
          Validator._moreThanZero(_amount);
          //todo check address zero and comment

         uint256 cost = _quoteCrossChainCost(_targetChain);
            
            uint16 currentChainId = _getChainId(address(this));
            if(currentChainId < 1) revert spoke__InvalidSpokeChainId();


        if(msg.value < cost) revert spoke__InsufficientGasFee();
     
           // Create and encode payload for cross-chain message
        ActionPayload memory payload;
        payload.action = Action.CreateRequest;
        payload.assetAddress = _loanAddress;
        payload.assetAmount = _amount;
        payload.sender = msg.sender;
        payload.interest = _interest;
        payload.returnDate = _returnDate;

        bytes memory _payload = Message._encodeActionPayload(payload);


         wormholeRelayer.sendPayloadToEvm{value: cost}
         (_targetChain,
          _targetAddress,
          _payload,
           0,
           Constants.GAS_LIMIT,
          currentChainId, 
          msg.sender);

      
        emit Spoke__CreateRequest(
            _targetChain,
            _amount,
            msg.sender,
            _loanAddress
        );



    }


    //   /**
    //  * @dev Registers a spoke contract for a specific chain ID.
    //  * Used to verify valid sending addresses for cross-chain interactions.
    //  * @param chainId The chain ID associated with the spoke contract.
    //  * @param spokeContractAddress The address of the spoke contract to register.
    //  */
    // function _registerSpokeContract(
    //     uint16 chainId,
    //     address spokeContractAddress
    // ) internal {
    //     s_spokeProtocols[chainId] = spokeContractAddress;
    // }




    function _getChainId(address _spokeContractAddress) private view returns (uint16 chainId_){
        chainId_ = s_spokeProtocols[_spokeContractAddress];
    }



    function registerSpokeContractProvider(
     uint16 _chainId,
    address payable _wormhole,
    address _tokenBridge,
    address _wormholeRelayer,
    address _circleTokenMessenger,
    address _circleMessageTransmitter)ValidateChainId(_chainId) external {

        Provider storage provider =  s_spokeProtocolProvider[address(this)];
        provider.chainId = _chainId;
        provider.wormhole = _wormhole;
        provider.tokenBridge = _tokenBridge;
        provider.wormholeRelayer = _wormholeRelayer;
        provider.circleTokenMessenger = _circleTokenMessenger;
        provider.circleMessageTransmitter = _circleMessageTransmitter;

    }




    function quoteCrossChainCost(uint16 _targetChain) 
    external 
    view 
    returns(
    uint256 deliveryCost){
    deliveryCost = _quoteCrossChainCost(_targetChain);
    } 


    function _quoteCrossChainCost(
        uint16 targetChain
    ) private view returns (uint256 cost) {
        uint256 deliveryCost;
        (deliveryCost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            0,
            Constants.GAS_LIMIT
        );

        cost = deliveryCost + wormhole.messageFee();
    }

    receive() external payable {}
}
