
// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.9;

interface IUniswapV2Router02 {
    

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapTokensForExactETH(
        uint amountOut, uint amountInMax,
        address[] calldata path,
        address to, uint deadline
    ) external returns (uint[] memory amounts);

}