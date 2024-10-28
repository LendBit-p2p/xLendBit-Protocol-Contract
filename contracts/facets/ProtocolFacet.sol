// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.9;

import {Operations} from "../utils/functions/Operations.sol";
import {Getters} from "../utils/functions/Getters.sol";

/// @title ProtocolFacet Contract
/// @author Chukwuma Emmanuel(@ebukizy1). Favour Aniogor (@SuperDevFavour)
contract ProtocolFacet is Operations, Getters {
    fallback() external {
        revert("ProtocolFacet: fallback");
    }
}
