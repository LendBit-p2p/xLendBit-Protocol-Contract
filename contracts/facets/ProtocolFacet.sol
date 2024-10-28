// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.9;
import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Constants} from "../utils/constants/Constant.sol";
import {Validator} from "../utils/validators/Validator.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../utils/validators/Error.sol";
import {Operations} from "../utils/functions/Operations.sol";
import {Getters} from "../utils/functions/Getters.sol";
import "../model/Event.sol";
import "../model/Protocol.sol";
import "../interfaces/IUniswapV2Router02.sol";

import "../utils/functions/Utils.sol";

/// @title ProtocolFacet Contract
/// @author Chukwuma Emmanuel(@ebukizy1). Favour Aniogor (@SuperDevFavour)
contract ProtocolFacet is Operations, Getters {
    /**
     * @notice Retrieves all the requests stored in the system
     * @dev Returns an array of all requests
     * @return An array of `Request` structs representing all stored requests
     */
    function getAllRequest() external view returns (Request[] memory) {
        return _appStorage.s_requests;
    }

    // /// @notice This checks the health factor to see if  it is broken if it is it reverts
    // /// @param _user a parameter for the address we want to check the health factor for
    // function _revertIfHealthFactorIsBroken(address _user) internal view {
    //     uint256 _userHealthFactor = _healthFactor(_user, 0);
    //     if (_userHealthFactor < Constants.MIN_HEALTH_FACTOR) {
    //         revert Protocol__BreaksHealthFactor();
    //     }
    // }

    fallback() external {
        revert("ProtocolFacet: fallback");
    }
}
