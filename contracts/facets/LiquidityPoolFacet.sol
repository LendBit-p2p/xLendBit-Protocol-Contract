// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.9;

import {AppStorage} from "../utils/functions/AppStorage.sol";
import {LibGettersImpl} from "../libraries/LibGetters.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {Constants} from "../utils/constants/Constant.sol";
import {ProtocolPool} from "../model/Protocol.sol";
import "../model/Event.sol";
import "../utils/validators/Error.sol";

/**
 * @title LiquidityPoolFacet
 * @notice Handles deposits, withdrawals, and interest accrual in liquidity pools
 * @author Claude
 */
contract LiquidityPoolFacet is AppStorage {
    using SafeERC20 for IERC20;

    /**
     * @notice Initializes the protocol pool with the given parameters
     * @dev Only callable by contract owner
     * @param _token The address of the token to be used in the protocol pool
     * @param reserveFactor The reserve factor for the protocol pool (percentage of interest that goes to reserves)
     * @param optimalUtilization The optimal utilization rate for the protocol pool (in basis points, 10000 = 100%)
     * @param baseRate The base interest rate for the protocol pool (in basis points)
     * @param slopeRate The slope rate for the protocol pool (determines how quickly interest rates increase)
     */
    function initializeProtocolPool(
        address _token,
        uint256 reserveFactor,
        uint256 optimalUtilization,
        uint256 baseRate,
        uint256 slopeRate,
        uint256 initialSupply
    ) external payable {
        // Check caller is contract owner
        LibDiamond.enforceIsContractOwner();

        // Validate protocol state
        if (_appStorage.s_protocolPool[_token].isActive)
            revert ProtocolPool__IsNotActive();
        if (_appStorage.s_protocolPool[_token].initialize)
            revert ProtocolPool__AlreadyInitialized();
        if (!_appStorage.s_isLoanable[_token])
            revert ProtocolPool__TokenNotSupported();

        // Validate parameters
        require(
            reserveFactor <= Constants.MAX_RESERVE_FACTOR,
            "Reserve factor too high"
        );
        require(optimalUtilization <= 9000, "Optimal utilization too high");
        require(baseRate <= 1000, "Base rate too high");

        if (_token == Constants.NATIVE_TOKEN) {
            require(msg.value == initialSupply, "Incorrect ETH amount");
        } else {
            require(
                IERC20(_token).balanceOf(msg.sender) >= initialSupply,
                "Insufficient token balance"
            );
            require(
                IERC20(_token).allowance(msg.sender, address(this)) >=
                    initialSupply,
                "Insufficient token allowance"
            );
            IERC20(_token).safeTransferFrom(
                msg.sender,
                address(this),
                initialSupply
            );
        }

        ProtocolPool storage _protocolPool = _appStorage.s_protocolPool[_token];

        // Set protocol pool parameters
        _protocolPool.token = _token;
        _protocolPool.reserveFactor = reserveFactor;
        _protocolPool.optimalUtilization = optimalUtilization;
        _protocolPool.baseRate = baseRate;
        _protocolPool.slopeRate = slopeRate;
        _protocolPool.isActive = true;
        _protocolPool.initialize = true;

        // Initialize token data
        _appStorage.s_tokenData[_token].lastUpdateTimestamp = block.timestamp;
        if (_appStorage.s_tokenData[_token].normalizedPoolDebt == 0) {
            _appStorage.s_tokenData[_token].normalizedPoolDebt = 1e18; // Initialize normalized debt to 1
        }

        emit ProtocolPoolInitialized(_token, reserveFactor);
    }

    /**
     * @notice Gets the configuration of the protocol pool
     * @return token The token address used in the pool
     * @return totalSupply The total supply of tokens in the pool
     * @return totalBorrows The total amount borrowed from the pool
     * @return reserveFactor The reserve factor of the pool
     * @return optimalUtilization The optimal utilization rate
     * @return baseRate The base interest rate
     * @return slopeRate The slope rate for interest calculation
     * @return isActive Whether the pool is active
     * @return initialize Whether the pool is initialized
     */
    function getProtocolPoolConfig(
        address _token
    )
        external
        view
        returns (
            address token,
            uint256 totalSupply,
            uint256 totalBorrows,
            uint256 reserveFactor,
            uint256 optimalUtilization,
            uint256 baseRate,
            uint256 slopeRate,
            bool isActive,
            bool initialize
        )
    {
        return (
            _appStorage.s_protocolPool[_token].token,
            _appStorage.s_protocolPool[_token].totalSupply,
            _appStorage.s_protocolPool[_token].totalBorrows,
            _appStorage.s_protocolPool[_token].reserveFactor,
            _appStorage.s_protocolPool[_token].optimalUtilization,
            _appStorage.s_protocolPool[_token].baseRate,
            _appStorage.s_protocolPool[_token].slopeRate,
            _appStorage.s_protocolPool[_token].isActive,
            _appStorage.s_protocolPool[_token].initialize
        );
    }

    /**
     * @notice Allows users to deposit tokens into the liquidity pool
     * @dev Handles both native token (ETH) and ERC20 deposits
     * @param token The address of the token to deposit
     * @param amount The amount of tokens to deposit
     * @return shares The number of LP shares minted for the deposit
     */
    function deposit(
        address token,
        uint256 amount
    ) external payable returns (uint256 shares) {
        // Validate deposit
        if (!_appStorage.s_protocolPool[token].initialize)
            revert ProtocolPool__NotInitialized();

        if (amount == 0) revert ProtocolPool__ZeroAmount();
        if (!_appStorage.s_isLoanable[token])
            revert ProtocolPool__TokenNotSupported();
        if (!_appStorage.s_protocolPool[token].isActive)
            revert ProtocolPool__IsNotActive();

        // Handle deposit based on token type
        if (token == Constants.NATIVE_TOKEN) {
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            require(msg.value == 0, "ETH sent with token deposit");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        // Calculate shares based on the amount deposited
        // calculate user interest

        // Update state variables
        _appStorage.s_tokenData[token].poolLiquidity += amount;
        _appStorage.s_tokenData[token].lastUpdateTimestamp = block.timestamp;
        _appStorage.s_addressToUserPoolDeposit[msg.sender][token] += amount;

        emit Deposit(msg.sender, token, amount, shares);
    }

    function getUserPoolDeposit(
        address user,
        address token
    ) external view returns (uint256) {
        return _appStorage.s_addressToUserPoolDeposit[user][token];
    }
}
