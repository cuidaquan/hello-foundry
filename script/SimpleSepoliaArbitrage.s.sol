// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/MyToken.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract SimpleSepoliaArbitrageScript is Script {
    // Real Sepolia contract addresses
    address constant TOKEN_A = 0xB74b65845A9b66a870B2D67a58fc80aE17014713;
    address constant TOKEN_B = 0x2Df21BbDd03AB078b012C2d51798620C16604959;
    address constant FLASH_SWAP_ARBITRAGE = 0x44525F8d9ed3dC23919D88FC4B438328c17b8De7;
    
    // Pair addresses
    address constant PAIR_A = 0xF4732250201c043c44dF641f2c93c05bF429A81B;
    address constant PAIR_B = 0xE8efACF8555A3eb89f8CDC7A6C13837E4705E3c0;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== Simple Flash Swap Test on Sepolia ===");
        console.log("Deployer:", deployer);
        console.log("PairA:", PAIR_A);
        console.log("PairB:", PAIR_B);
        
        MyToken tokenA = MyToken(TOKEN_A);
        MyToken tokenB = MyToken(TOKEN_B);
        IUniswapV2Pair pairA = IUniswapV2Pair(PAIR_A);
        IUniswapV2Pair pairB = IUniswapV2Pair(PAIR_B);
        
        // Check current reserves
        (uint112 reserve0A, uint112 reserve1A,) = pairA.getReserves();
        (uint112 reserve0B, uint112 reserve1B,) = pairB.getReserves();
        
        console.log("=== Current Reserves ===");
        console.log("PairA - TokenB:", reserve0A, "TokenA:", reserve1A);
        console.log("PairB - TokenB:", reserve0B, "TokenA:", reserve1B);
        
        // Calculate prices
        uint256 priceA = (uint256(reserve0A) * 1e18) / reserve1A; // TokenB per TokenA in PairA
        uint256 priceB = (uint256(reserve0B) * 1e18) / reserve1B; // TokenB per TokenA in PairB
        
        console.log("PairA price: 1 TokenA =", priceA, "TokenB");
        console.log("PairB price: 1 TokenA =", priceB, "TokenB");
        
        if (priceA > priceB) {
            console.log("Arbitrage opportunity: Buy TokenA in PairB, sell in PairA");
            console.log("Price difference:", priceA - priceB, "TokenB per TokenA");
        } else if (priceB > priceA) {
            console.log("Arbitrage opportunity: Buy TokenA in PairA, sell in PairB");
            console.log("Price difference:", priceB - priceA, "TokenB per TokenA");
        } else {
            console.log("No arbitrage opportunity");
        }
        
        // Check deployer balances
        console.log("=== Deployer Balances ===");
        console.log("TokenA balance:", tokenA.balanceOf(deployer));
        console.log("TokenB balance:", tokenB.balanceOf(deployer));
        
        // Try a simple swap in PairB (buy TokenA with TokenB)
        uint256 swapAmount = 1 * 10**17; // 0.1 TokenB
        console.log("=== Attempting Simple Swap ===");
        console.log("Swapping", swapAmount, "TokenB for TokenA in PairB");
        
        // Calculate expected output using constant product formula
        uint256 amountInWithFee = swapAmount * 997;
        uint256 numerator = amountInWithFee * reserve1B;
        uint256 denominator = (uint256(reserve0B) * 1000) + amountInWithFee;
        uint256 expectedOut = numerator / denominator;
        
        console.log("Expected TokenA output:", expectedOut);
        
        // Check if we have enough TokenB
        uint256 deployerTokenB = tokenB.balanceOf(deployer);
        if (deployerTokenB >= swapAmount) {
            console.log("Sufficient TokenB balance for swap");
            
            // Approve PairB to spend TokenB
            tokenB.approve(PAIR_B, swapAmount);
            console.log("Approved PairB to spend", swapAmount, "TokenB");
            
            // Transfer TokenB to PairB
            tokenB.transfer(PAIR_B, swapAmount);
            console.log("Transferred", swapAmount, "TokenB to PairB");
            
            // Execute swap
            try pairB.swap(0, expectedOut, deployer, "") {
                console.log("=== Swap Successful! ===");
                console.log("Received approximately", expectedOut, "TokenA");
                
                // Check new balances
                console.log("New TokenA balance:", tokenA.balanceOf(deployer));
                console.log("New TokenB balance:", tokenB.balanceOf(deployer));
            } catch Error(string memory reason) {
                console.log("Swap failed:", reason);
            } catch {
                console.log("Swap failed with unknown error");
            }
        } else {
            console.log("Insufficient TokenB balance for swap");
            console.log("Required:", swapAmount, "Available:", deployerTokenB);
        }
        
        vm.stopBroadcast();
    }
}
