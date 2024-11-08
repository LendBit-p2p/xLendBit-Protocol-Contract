// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.9;

interface IWormhole {
    struct Signature {
        bytes32 r;
        bytes32 s;
        uint8 v;
        uint8 guardianIndex;
    }

    struct VM {
        uint8 version;
        uint32 timestamp;
        uint32 nonce;
        uint16 emitterChainId;
        bytes32 emitterAddress;
        uint64 sequence;
        uint8 consistencyLevel;
        bytes payload;
        uint32 guardianSetIndex;
        Signature[] signatures;
        bytes32 hash;
    }

    struct WormholeBodyParams {
        uint32 timestamp;
        uint32 nonce;
        uint16 emitterChainId;
        bytes32 emitterAddress;
        uint64 sequence;
        uint8 consistencyLevel;
    }

    event LogMessagePublished(
        address indexed sender,
        uint64 sequence,
        uint32 nonce,
        bytes payload,
        uint8 consistencyLevel
    );

    function publishMessage(
        uint32 nonce,
        bytes memory payload,
        uint8 consistencyLevel
    ) external payable returns (uint64 sequence);

    function parseAndVerifyVM(
        bytes calldata encodedVM
    ) external view returns (VM memory vm, bool valid, string memory reason);

    function chainId() external view returns (uint16);

    function messageFee() external view returns (uint256);

    // added due to WormholeSimulator need
    function getCurrentGuardianSetIndex() external view returns (uint32);

    struct GuardianSet {
        address[] keys;
        uint32 expirationTime;
    }

    function getGuardianSet(
        uint32 guardianSetIndex
    ) external view returns (GuardianSet memory guardians);

    function parseVM(
        bytes memory encodedVM
    ) external pure returns (VM memory vm);
}
