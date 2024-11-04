// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Script, console} from "forge-std/Script.sol";
import "../contracts/Spoke/SpokeProtocol.sol";

contract DeployScript is Script {
    // Returns the address of the newly deployed contract
    bytes32 salt =
        keccak256("LendBits_WormHole_hackathon_Winners_2024_BY_A_MILE");
    uint16 chainIdOP = 10005;
    uint16 chainIdARB = 10003;
    uint32 cctpDomainOP = 2;
    uint32 cctpDomainARB = 3;
    string rpcOP = "https://sepolia.optimism.io";
    string rpcARB =
        "https://arb-sepolia.g.alchemy.com/v2/5m9xH9cHObhTWGsyCSv6Pu3FgoWNRiGG";
    address tokenBridgeOP = 0x99737Ec4B815d816c49A385943baf0380e75c0Ac;
    address tokenBridgeARB = 0xC7A204bDBFe983FCD8d8E61D02b475D4073fF97e;
    address wormholeRelayerOP = 0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE;
    address wormholeRelayerARB = 0x7B1bD7a6b4E61c2a123AC6BC2cbfC614437D0470;
    address wormholeOP = 0x31377888146f3253211EFEf5c676D41ECe7D58Fe;
    address wormholeARB = 0x6b9C8671cdDC8dEab9c719bB87cBd3e782bA6a35;
    address circleMessageTransmitterOP =
        0x7865fAfC2db2093669d92c0F33AeEF291086BEFD;
    address circleMessageTransmitterARB =
        0xC30362313FBBA5cf9163F0bb16a0e01f01A896ca;
    address circleTokenMessengerOP = 0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5;
    address circleTokenMessengerARB =
        0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5;
    address USDCOP = 0x5fd84259d66Cd46123540766Be93DFE6D43130D7;
    address USDCARB = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    address WETHOP = 0x4200000000000000000000000000000000000006;
    address WETHARB = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
    address ETH = address(1);
    address[] tokensOP;
    address[] tokensARB;

    function setUp() external {
        tokensOP.push(USDCOP);
        tokensOP.push(WETHOP);
        tokensOP.push(ETH);
        tokensARB.push(USDCARB);
        tokensARB.push(WETHARB);
        tokensARB.push(ETH);
    }

    function run() external {
        uint256 OP = vm.createFork(rpcOP);
        // uint256 ARB = vm.createFork(rpcARB);
        vm.selectFork(OP);
        vm.startBroadcast();
        // address op = deployOP(
        //     wormholeRelayerOP,
        //     tokenBridgeOP,
        //     wormholeOP,
        //     tokensOP,
        //     circleTokenMessengerOP,
        //     circleMessageTransmitterOP,
        //     chainIdOP,
        //     USDCOP,
        //     WETHOP
        // );
        // console.log("This OP: ", op);
        SpokeProtocol _spokeProtocol = SpokeProtocol(
            payable(0xD93eBB95196AF1D9FdD1dD970fAC1d2BFfDb8046)
        );
        // _spokeProtocol.setHub(
        //     10004,
        //     0x05AE831342A66bA3640F5342eeBb50352fC6A4B0
        // );
        // _spokeProtocol.setSpokeToHub(address(1), address(1));
        // _spokeProtocol.setSpokeToHub(
        //     0x4200000000000000000000000000000000000006,
        //     address(1)
        // );
        // _spokeProtocol.setSpokeToHub(
        //     0x5fd84259d66Cd46123540766Be93DFE6D43130D7,
        //     0x036CbD53842c5426634e7929541eC2318f3dCF7e
        // );
        IERC20(USDCOP).approve(address(_spokeProtocol), 2E6);
        _spokeProtocol.depositCollateral{value: 0.05 ether}(USDCOP, 2E6);

        vm.stopBroadcast();

        // vm.selectFork(ARB);
        // address arb = deployARB(
        //     wormholeRelayerARB,
        //     tokenBridgeARB,
        //     wormholeARB,
        //     tokensARB,
        //     circleTokenMessengerARB,
        //     circleMessageTransmitterARB,
        //     chainIdARB,
        //     USDCARB,
        //     WETHARB
        // );
    }

    function deployOP(
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole,
        address[] memory _tokens,
        address _circleTM,
        address _circleMT,
        uint16 _chainId,
        address _USDC,
        address _WETH
    ) public payable returns (address) {
        // This syntax is a newer way to invoke create2 without assembly, you just need to pass salt
        // https://docs.soliditylang.org/en/latest/control-structures.html#salted-contract-creations-create2
        return
            address(
                new SpokeProtocol(
                    _wormholeRelayer,
                    _tokenBridge,
                    _wormhole,
                    _tokens,
                    _circleTM,
                    _circleMT,
                    _chainId,
                    _USDC,
                    _WETH
                )
            );
    }

    function deployARB(
        address _wormholeRelayer,
        address _tokenBridge,
        address _wormhole,
        address[] memory _tokens,
        address _circleTM,
        address _circleMT,
        uint16 _chainId,
        address _USDC,
        address _WETH
    ) public payable returns (address) {
        // This syntax is a newer way to invoke create2 without assembly, you just need to pass salt
        // https://docs.soliditylang.org/en/latest/control-structures.html#salted-contract-creations-create2
        return
            address(
                new SpokeProtocol{salt: salt}(
                    _wormholeRelayer,
                    _tokenBridge,
                    _wormhole,
                    _tokens,
                    _circleTM,
                    _circleMT,
                    _chainId,
                    _USDC,
                    _WETH
                )
            );
    }
}
