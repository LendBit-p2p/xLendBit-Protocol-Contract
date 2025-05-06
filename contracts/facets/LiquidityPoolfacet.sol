// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.9;

import {AppStorage} from "../utils/functions/AppStorage.sol";
import {LibGettersImpl} from "../libraries/LibGetters.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {Constants} from "../utils/constants/Constant.sol";

/**
 * @title LiquidityPoolFacet
 * @notice Handles deposits, withdrawals, and interest accrual in liquidity pools
 * @author Claude
 */
contract LiquidityPoolFacet is AppStorage {
    using SafeERC20 for IERC20;

    /**
     * @notice Emitted when a protocol pool is initialized
     * @param token The address of the token used for the pool
     * @param reserveFactor The reserve factor set for the pool
     */
    event ProtocolPoolInitialized(address indexed token, uint256 reserveFactor);

    
    
    /**
     * @notice Emitted when a user deposits into a liquidity pool
     * @param user The address of the user making the deposit
     * @param token The address of the token deposited
     * @param amount The amount of tokens deposited
     * @param sharesMinted The amount of LP shares minted to the user
     */
    event Deposit(address indexed user, address indexed token, uint256 amount, uint256 sharesMinted);
    
    /**
     * @notice Emitted when a user withdraws from a liquidity pool
     * @param user The address of the user making the withdrawal
     * @param token The address of the token withdrawn
     * @param amount The amount of tokens withdrawn
     * @param sharesBurned The amount of LP shares burned
     */
    event Withdraw(address indexed user, address indexed token, uint256 amount, uint256 sharesBurned);
    
    /**
     * @notice Emitted when interest is accrued in a pool
     * @param token The address of the token for which interest was accrued
     * @param interestAccrued The amount of interest accrued
     */
    event InterestAccrued(address indexed token, uint256 interestAccrued);

    // Custom errors
    /// @notice Thrown when trying to interact with a protocol pool that is not active
    error ProtocolPool__IsNotActive();
    /// @notice Thrown when trying to initialize an already initialized protocol pool
    error ProtocolPool__AlreadyInitialized();
    /// @notice Thrown when trying to use a token that is not supported by the protocol
    error ProtocolPool__TokenNotSupported();
    /// @notice Thrown when attempting an operation with zero amount
    error ProtocolPool__ZeroAmount();
    /// @notice Thrown when trying to use a protocol pool that has not been initialized
    error ProtocolPool__NotInitialized();
    /// @notice Thrown when a user tries to withdraw more than their balance
    error ProtocolPool__InsufficientBalance();
    /// @notice Thrown when a withdrawal is not possible due to insufficient liquidity
    error ProtocolPool__InsufficientLiquidity();

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
    ) external payable{
        // Check caller is contract owner
        LibDiamond.enforceIsContractOwner();
        
        // Validate protocol state
        if(_appStorage.s_protocolPool.isActive) revert ProtocolPool__IsNotActive();
        if(_appStorage.s_protocolPool.initialize) revert ProtocolPool__AlreadyInitialized();
        if(!_appStorage.s_isLoanable[_token]) revert ProtocolPool__TokenNotSupported();
        
        // Validate parameters
        require(reserveFactor <= Constants.MAX_RESERVE_FACTOR, "Reserve factor too high");
        require(optimalUtilization <= 9000, "Optimal utilization too high");
        require(baseRate <= 1000, "Base rate too high");


        if (_token == Constants.NATIVE_TOKEN) {
            require(msg.value == initialSupply, "Incorrect ETH amount");
        } else {
            require(IERC20(_token).balanceOf(msg.sender) >= initialSupply, "Insufficient token balance");
            require(IERC20(_token).allowance(msg.sender, address(this)) >= initialSupply, "Insufficient token allowance");
            IERC20(_token).safeTransferFrom(msg.sender, address(this), initialSupply);
        }

        // Set protocol pool parameters
        _appStorage.s_protocolPool.token = _token;
        _appStorage.s_protocolPool.reserveFactor = reserveFactor;
        _appStorage.s_protocolPool.optimalUtilization = optimalUtilization;
        _appStorage.s_protocolPool.baseRate = baseRate;
        _appStorage.s_protocolPool.slopeRate = slopeRate;
        _appStorage.s_protocolPool.isActive = true;
        _appStorage.s_protocolPool.initialize = true;

        // Initialize token data
        _appStorage.s_tokenData[_token].lastUpdateTimestamp = block.timestamp;
        if (_appStorage.s_tokenData[_token].normalizedPoolDebt == 0) {
            _appStorage.s_tokenData[_token].normalizedPoolDebt = 1e18; // Initialize normalized debt to 1
        }

        _appStorage.s_isProtocolPoolInitialized = true; 
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
    function getProtocolPoolConfig() external view returns (
        address token,
        uint256 totalSupply,
        uint256 totalBorrows,
        uint256 reserveFactor,
        uint256 optimalUtilization,
        uint256 baseRate,
        uint256 slopeRate,
        bool isActive,
        bool initialize
    ) {
        // LibAppStorage.Layout storage s = _appStorage();
        return (
            _appStorage.s_protocolPool.token,
            _appStorage.s_protocolPool.totalSupply,
            _appStorage.s_protocolPool.totalBorrows,
            _appStorage.s_protocolPool.reserveFactor,
            _appStorage.s_protocolPool.optimalUtilization,
            _appStorage.s_protocolPool.baseRate,
            _appStorage.s_protocolPool.slopeRate,
            _appStorage.s_protocolPool.isActive,
            _appStorage.s_protocolPool.initialize
        );
    }





    // /**
    //  * @notice Allows users to deposit tokens into the liquidity pool
    //  * @dev Handles both native token (ETH) and ERC20 deposits
    //  * @param token The address of the token to deposit
    //  * @param amount The amount of tokens to deposit
    //  * @return shares The number of LP shares minted for the deposit
    //  */
    // function deposit(address token, uint256 amount) external payable returns (uint256 shares) {
    //     // Validate deposit
    //     if(!_appStorage.s_isProtocolPoolInitialized) revert ProtocolPool__NotInitialized();

    //     if(amount == 0) revert ProtocolPool__ZeroAmount();
    //     if(!_appStorage.s_isLoanable[token]) revert ProtocolPool__TokenNotSupported();

    //     // Update pool state before the deposit to accrue any pending interest
    //     // _updatePoolState(token);

    //     // Handle deposit based on token type
    //     if (token == Constants.NATIVE_TOKEN) {
    //         require(msg.value == amount, "Incorrect ETH amount");
    //     } else {
    //         require(msg.value == 0, "ETH sent with token deposit");
    //         IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    //     }

    //     // Calculate shares to mint based on current pool state
    //     // shares = _calculateSharesToMint(token, amount);
        
    //     // Update state variables
    //     _appStorage.s_tokenData[token].totalSupply += shares;
    //     _appStorage.s_tokenData[token].poolLiquidity += amount;
    //     _appStorage.s_userShares[msg.sender][token] += shares;

    //     emit Deposit(msg.sender, token, amount, shares);
    //     // return shares;
    // }

    // /**
    //  * @notice Allows users to withdraw tokens from the liquidity pool
    //  * @dev Burns LP shares and returns the corresponding amount of tokens
    //  * @param token The address of the token to withdraw
    //  * @param shares The amount of LP shares to burn
    //  * @return amount The amount of tokens received
    //  */
    // function withdraw(address token, uint256 shares) external returns (uint256 amount) {
    //     // Validate withdrawal
    //     if(!_appStorage.s_isProtocolPoolInitialized) revert ProtocolPool__NotInitialized();
    //     if(shares == 0) revert ProtocolPool__ZeroAmount();
    //     if(_appStorage.s_userShares[msg.sender][token] < shares) revert ProtocolPool__InsufficientBalance();

    //     // Update pool state before withdrawal to accrue any pending interest
    //     _updatePoolState(token);

    //     // Calculate tokens to withdraw based on shares
    //     amount = _calculateAmountToWithdraw(token, shares);
        
    //     // Verify there is enough liquidity in the pool
    //     if(_appStorage.s_tokenData[token].poolLiquidity < amount) revert ProtocolPool__InsufficientLiquidity();
        
    //     // Update state before transfer
    //     _appStorage.s_tokenData[token].totalSupply -= shares;
    //     _appStorage.s_tokenData[token].poolLiquidity -= amount;
    //     _appStorage.s_userShares[msg.sender][token] -= shares;

    //     // Transfer tokens to user
    //     if (token == Constants.NATIVE_TOKEN) {
    //         (bool success, ) = payable(msg.sender).call{value: amount}("");
    //         require(success, "ETH transfer failed");
    //     } else {
    //         IERC20(token).safeTransfer(msg.sender, amount);
    //     }

    //     emit Withdraw(msg.sender, token, amount, shares);
    //     return amount;
    // }

    // /**
    //  * @notice Updates the pool state, including interest accrual
    //  * @dev Called before any deposit or withdrawal to ensure accurate accounting
    //  * @param token The token address to update
    //  */
    // function _updatePoolState(address token) internal {
    //     uint256 currentTimestamp = block.timestamp;
    //     uint256 lastUpdateTimestamp = _appStorage.s_tokenData[token].lastUpdateTimestamp;
        
    //     if (currentTimestamp > lastUpdateTimestamp) {
    //         uint256 timeElapsed = currentTimestamp - lastUpdateTimestamp;
            
    //         // Calculate interest rate based on utilization
    //         uint256 utilization = _calculateUtilization(token);
    //         uint256 interestRate = _calculateInterestRate(
    //             utilization,
    //             _appStorage.s_protocolPool.baseRate,
    //             _appStorage.s_protocolPool.slopeRate,
    //             _appStorage.s_protocolPool.optimalUtilization
    //         );
            
    //         // Update normalized debt with accumulated interest
    //         if (_appStorage.s_tokenData[token].totalBorrows > 0) {
    //             // Calculate interest factor based on time elapsed and annual rate
    //             uint256 interestFactor = 1e18 + ((interestRate * timeElapsed) / 365 days);
                
    //             // Calculate old and new total debt
    //             uint256 oldNormalizedDebt = _appStorage.s_tokenData[token].normalizedPoolDebt;
    //             uint256 newNormalizedDebt = (oldNormalizedDebt * interestFactor) / 1e18;
                
    //             // Update normalized debt
    //             _appStorage.s_tokenData[token].normalizedPoolDebt = newNormalizedDebt;
                
    //             // Calculate and emit actual interest accrued
    //             uint256 totalDebtBefore = _appStorage.s_tokenData[token].totalBorrows;
    //             uint256 totalDebtAfter = (totalDebtBefore * newNormalizedDebt) / oldNormalizedDebt;
    //             uint256 interestAccrued = totalDebtAfter - totalDebtBefore;
                
    //             // Emit interest accrual event
    //             emit InterestAccrued(token, interestAccrued);
    //         }
            
    //         // Update last update timestamp
    //         _appStorage.s_tokenData[token].lastUpdateTimestamp = currentTimestamp;
    //     }
    // }

 

    // /**
    //  * @notice Gets user's share balance for a specific token
    //  * @param user The user address
    //  * @param token The token address
    //  * @return The user's share balance
    //  */
    // function getUserShares(address user, address token) external view returns (uint256) {
    //     return _appStorage.s_userShares[user][token];
    // }

    // /**
    //  * @notice Gets the current pool data for a token
    //  * @param token The token address
    //  * @return totalSupply Total supply of shares
    //  * @return poolLiquidity Available liquidity in the pool
    //  * @return totalBorrows Total amount borrowed from the pool
    //  * @return utilization Current utilization rate (scaled by 10000)
    //  * @return interestRate Current annual interest rate (scaled by 1e18)
    //  */
    // function getPoolData(address token) external view returns (
    //     uint256 totalSupply,
    //     uint256 poolLiquidity,
    //     uint256 totalBorrows,
    //     uint256 utilization,
    //     uint256 interestRate
    // ) {
    //     totalSupply = _appStorage.s_tokenData[token].totalSupply;
    //     poolLiquidity = _appStorage.s_tokenData[token].poolLiquidity;
    //     totalBorrows = _appStorage.s_tokenData[token].totalBorrows;
    //     utilization = _calculateUtilization(token);
    //     interestRate = _calculateInterestRate(
    //         utilization,
    //         _appStorage.s_protocolPool.baseRate,
    //         _appStorage.s_protocolPool.slopeRate,
    //         _appStorage.s_protocolPool.optimalUtilization
    //     );
        
    //     return (totalSupply, poolLiquidity, totalBorrows, utilization, interestRate);
    // }
    
    // /**
    //  * @notice Gets the amount of underlying tokens that a given amount of shares represents
    //  * @dev This is useful for users to know how much they can withdraw with their shares
    //  * @param token The token address
    //  * @param shares The number of shares
    //  * @return The amount of tokens the shares represent
    //  */
    // function getTokenAmountFromShares(address token, uint256 shares) external view returns (uint256) {
    //     return _calculateAmountToWithdraw(token, shares);
    // }
    
    // /**
    //  * @notice Gets the amount of shares needed to withdraw a specific token amount
    //  * @dev Inverse of getTokenAmountFromShares
    //  * @param token The token address
    //  * @param amount The token amount
    //  * @return The number of shares needed
    //  */
    // function getSharesForTokenAmount(address token, uint256 amount) external view returns (uint256) {
    //     uint256 totalSupply = _appStorage.s_tokenData[token].totalSupply;
    //     uint256 poolLiquidity = _appStorage.s_tokenData[token].poolLiquidity;
        
    //     if (poolLiquidity == 0) return 0;
        
    //     return (amount * totalSupply) / poolLiquidity;
    // }
}