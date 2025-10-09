// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FlashSwapArbitrage.sol";
import "../src/MyToken.sol";

contract ExecuteSepoliaArbitrageScript is Script {
    // Real Sepolia contract addresses
    address constant TOKEN_A = 0xB74b65845A9b66a870B2D67a58fc80aE17014713;
    address constant TOKEN_B = 0x2Df21BbDd03AB078b012C2d51798620C16604959;
    address constant FLASH_SWAP_ARBITRAGE = 0x44525F8d9ed3dC23919D88FC4B438328c17b8De7;

    // Factory addresses from deployment (correct addresses)
    address constant FACTORY_A = 0x05e6EF588D2DfC32aA8CCd5766ce355b3eb67700;
    address constant FACTORY_B = 0x50f0d2adcB69683205Dc86e1891D84133eCe1043;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== Flash Swap Arbitrage Execution on Sepolia ===");
        console.log("Deployer:", deployer);
        console.log("Token A:", TOKEN_A);
        console.log("Token B:", TOKEN_B);
        console.log("FlashSwapArbitrage:", FLASH_SWAP_ARBITRAGE);
        
        FlashSwapArbitrage arbitrage = FlashSwapArbitrage(payable(FLASH_SWAP_ARBITRAGE));
        MyToken tokenA = MyToken(TOKEN_A);
        MyToken tokenB = MyToken(TOKEN_B);
        
        // Check if deployer is the owner
        address owner = arbitrage.owner();
        console.log("Contract owner:", owner);
        console.log("Is deployer owner?", owner == deployer);
        
        // Check initial balances
        console.log("=== Initial State ===");
        console.log("Arbitrage contract TokenA balance:", tokenA.balanceOf(FLASH_SWAP_ARBITRAGE));
        console.log("Arbitrage contract TokenB balance:", tokenB.balanceOf(FLASH_SWAP_ARBITRAGE));
        console.log("Deployer TokenA balance:", tokenA.balanceOf(deployer));
        console.log("Deployer TokenB balance:", tokenB.balanceOf(deployer));
        
        // Execute arbitrage with smaller amount to avoid overflow
        uint256 arbitrageAmount = 1 * 10**17; // 0.1 TokenB
        console.log("=== Executing Arbitrage ===");
        console.log("Borrowing amount:", arbitrageAmount, "TokenB");
        
        try arbitrage.startArbitrage(
            FACTORY_A,
            FACTORY_B,
            TOKEN_B,  // Borrow TokenB
            TOKEN_A,  // Target TokenA
            arbitrageAmount
        ) {
            console.log("=== Arbitrage Executed Successfully! ===");
            
            // Check final balances
            uint256 finalTokenABalance = tokenA.balanceOf(FLASH_SWAP_ARBITRAGE);
            uint256 finalTokenBBalance = tokenB.balanceOf(FLASH_SWAP_ARBITRAGE);
            
            console.log("=== Final State ===");
            console.log("Arbitrage contract TokenA balance:", finalTokenABalance);
            console.log("Arbitrage contract TokenB balance:", finalTokenBBalance);
            
            // Calculate profit
            if (finalTokenBBalance > 0) {
                console.log("=== ARBITRAGE SUCCESSFUL ===");
                console.log("Profit earned:", finalTokenBBalance, "TokenB");
                console.log("Profit in decimal:", finalTokenBBalance / 10**18, "TokenB");
            } else {
                console.log("No profit earned");
            }
        } catch Error(string memory reason) {
            console.log("Arbitrage failed:", reason);
        } catch {
            console.log("Arbitrage failed with unknown error");
        }
        
        vm.stopBroadcast();
    }
}
