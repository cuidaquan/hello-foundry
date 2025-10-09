// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/MyToken.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract CheckSepoliaStateScript is Script {
    // Real Sepolia contract addresses
    address constant TOKEN_A = 0xB74b65845A9b66a870B2D67a58fc80aE17014713;
    address constant TOKEN_B = 0x2Df21BbDd03AB078b012C2d51798620C16604959;
    address constant FLASH_SWAP_ARBITRAGE = 0x44525F8d9ed3dC23919D88FC4B438328c17b8De7;
    
    // Factory addresses from deployment (correct addresses)
    address constant FACTORY_A = 0x05e6EF588D2DfC32aA8CCd5766ce355b3eb67700;
    address constant FACTORY_B = 0x50f0d2adcB69683205Dc86e1891D84133eCe1043;

    function run() external view {
        console.log("=== Sepolia State Check ===");
        console.log("Token A:", TOKEN_A);
        console.log("Token B:", TOKEN_B);
        console.log("FlashSwapArbitrage:", FLASH_SWAP_ARBITRAGE);
        console.log("Factory A:", FACTORY_A);
        console.log("Factory B:", FACTORY_B);
        
        // Get pair addresses
        IUniswapV2Factory factoryA = IUniswapV2Factory(FACTORY_A);
        IUniswapV2Factory factoryB = IUniswapV2Factory(FACTORY_B);
        
        address pairA = factoryA.getPair(TOKEN_A, TOKEN_B);
        address pairB = factoryB.getPair(TOKEN_A, TOKEN_B);
        
        console.log("=== Pair Addresses ===");
        console.log("Pair A:", pairA);
        console.log("Pair B:", pairB);
        
        if (pairA != address(0)) {
            IUniswapV2Pair pairAContract = IUniswapV2Pair(pairA);
            (uint112 reserve0A, uint112 reserve1A,) = pairAContract.getReserves();
            address token0A = pairAContract.token0();
            address token1A = pairAContract.token1();
            
            console.log("=== Pair A Reserves ===");
            console.log("Token0:", token0A);
            console.log("Token1:", token1A);
            console.log("Reserve0:", reserve0A);
            console.log("Reserve1:", reserve1A);
            
            if (token0A == TOKEN_A) {
                console.log("Pair A: TokenA =", reserve0A, "TokenB =", reserve1A);
                console.log("Pair A Price: 1 TokenA =", (uint256(reserve1A) * 1e18) / reserve0A, "TokenB");
            } else {
                console.log("Pair A: TokenB =", reserve0A, "TokenA =", reserve1A);
                console.log("Pair A Price: 1 TokenA =", (uint256(reserve0A) * 1e18) / reserve1A, "TokenB");
            }
        }
        
        if (pairB != address(0)) {
            IUniswapV2Pair pairBContract = IUniswapV2Pair(pairB);
            (uint112 reserve0B, uint112 reserve1B,) = pairBContract.getReserves();
            address token0B = pairBContract.token0();
            address token1B = pairBContract.token1();
            
            console.log("=== Pair B Reserves ===");
            console.log("Token0:", token0B);
            console.log("Token1:", token1B);
            console.log("Reserve0:", reserve0B);
            console.log("Reserve1:", reserve1B);
            
            if (token0B == TOKEN_A) {
                console.log("Pair B: TokenA =", reserve0B, "TokenB =", reserve1B);
                console.log("Pair B Price: 1 TokenA =", (uint256(reserve1B) * 1e18) / reserve0B, "TokenB");
            } else {
                console.log("Pair B: TokenB =", reserve0B, "TokenA =", reserve1B);
                console.log("Pair B Price: 1 TokenA =", (uint256(reserve0B) * 1e18) / reserve1B, "TokenB");
            }
        }
        
        // Check token balances
        MyToken tokenA = MyToken(TOKEN_A);
        MyToken tokenB = MyToken(TOKEN_B);
        
        console.log("=== Token Balances ===");
        console.log("Arbitrage TokenA balance:", tokenA.balanceOf(FLASH_SWAP_ARBITRAGE));
        console.log("Arbitrage TokenB balance:", tokenB.balanceOf(FLASH_SWAP_ARBITRAGE));
        
        if (pairA != address(0)) {
            console.log("PairA TokenA balance:", tokenA.balanceOf(pairA));
            console.log("PairA TokenB balance:", tokenB.balanceOf(pairA));
        }
        
        if (pairB != address(0)) {
            console.log("PairB TokenA balance:", tokenA.balanceOf(pairB));
            console.log("PairB TokenB balance:", tokenB.balanceOf(pairB));
        }
    }
}
