// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "./BaseScript.s.sol";
import "../src/MyToken.sol";
import "../src/FlashSwapArbitrage.sol";
import "../test/mocks/MockUniswap.sol";

contract FlashSwapArbitrageScript is BaseScript {
    
    // 部署的合约地址
    MyToken public tokenA;
    MyToken public tokenB;
    
    // Uniswap A (PoolA)
    MockUniswapV2Factory public factoryA;
    MockUniswapV2Router public routerA;
    MockWETH public wethA;
    address public pairA;

    // Uniswap B (PoolB)
    MockUniswapV2Factory public factoryB;
    MockUniswapV2Router public routerB;
    MockWETH public wethB;
    address public pairB;
    
    // 闪电兑换套利合约
    FlashSwapArbitrage public arbitrage;
    
    function run() public broadcaster {
        console.log("=== Starting Flash Swap Arbitrage System Deployment ===");

        // 1. Deploy two ERC20 tokens
        _deployTokens();

        // 2. Deploy two Uniswap instances
        _deployUniswapInstances();

        // 3. Create liquidity pools
        _createLiquidityPools();

        // 4. Add liquidity and set price difference
        _addLiquidityWithPriceDifference();

        // 5. Deploy flash swap arbitrage contract
        _deployArbitrageContract();

        // 6. Save contract addresses
        _saveContracts();

        console.log("=== Deployment Complete ===");
    }
    
    function _deployTokens() internal {
        console.log("1. Deploying tokens...");

        tokenA = new MyToken("Token A", "TKA");
        tokenB = new MyToken("Token B", "TKB");

        console.log("Token A deployed at:", address(tokenA));
        console.log("Token B deployed at:", address(tokenB));
        console.log("Token A balance:", tokenA.balanceOf(user));
        console.log("Token B balance:", tokenB.balanceOf(user));
    }
    
    function _deployUniswapInstances() internal {
        console.log("2. Deploying Uniswap instances...");

        // Deploy WETH
        wethA = new MockWETH();
        wethB = new MockWETH();

        // Deploy Factory A
        factoryA = new MockUniswapV2Factory(user);
        console.log("Factory A deployed at:", address(factoryA));

        // Deploy Router A
        routerA = new MockUniswapV2Router(address(factoryA), address(wethA));
        console.log("Router A deployed at:", address(routerA));

        // Deploy Factory B
        factoryB = new MockUniswapV2Factory(user);
        console.log("Factory B deployed at:", address(factoryB));

        // Deploy Router B
        routerB = new MockUniswapV2Router(address(factoryB), address(wethB));
        console.log("Router B deployed at:", address(routerB));
    }
    
    function _createLiquidityPools() internal {
        console.log("3. Creating liquidity pools...");

        // Create PoolA
        pairA = factoryA.createPair(address(tokenA), address(tokenB));
        console.log("Pair A created at:", pairA);

        // Create PoolB
        pairB = factoryB.createPair(address(tokenA), address(tokenB));
        console.log("Pair B created at:", pairB);
    }
    
    function _addLiquidityWithPriceDifference() internal {
        console.log("4. Adding liquidity and setting price difference...");

        uint256 amountA = 1000 * 10**18;  // 1000 Token A
        uint256 amountB_PoolA = 2000 * 10**18;  // 2000 Token B (Price: 1 TKA = 2 TKB)
        uint256 amountB_PoolB = 1800 * 10**18;  // 1800 Token B (Price: 1 TKA = 1.8 TKB)

        // Add liquidity to PoolA
        tokenA.approve(address(routerA), amountA);
        tokenB.approve(address(routerA), amountB_PoolA);

        routerA.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB_PoolA,
            0,
            0,
            user,
            block.timestamp + 300
        );

        console.log("PoolA liquidity added - Price: 1 TKA = 2 TKB");

        // Add liquidity to PoolB
        tokenA.approve(address(routerB), amountA);
        tokenB.approve(address(routerB), amountB_PoolB);

        routerB.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB_PoolB,
            0,
            0,
            user,
            block.timestamp + 300
        );

        console.log("PoolB liquidity added - Price: 1 TKA = 1.8 TKB");

        // Display reserves
        _displayReserves();
    }
    
    function _displayReserves() internal view {
        (uint256 reserve0A, uint256 reserve1A,) = MockUniswapV2Pair(pairA).getReserves();
        (uint256 reserve0B, uint256 reserve1B,) = MockUniswapV2Pair(pairB).getReserves();

        console.log("=== Pool Reserves ===");
        console.log("PoolA - Reserve0:", reserve0A, "Reserve1:", reserve1A);
        console.log("PoolB - Reserve0:", reserve0B, "Reserve1:", reserve1B);

        address token0A = MockUniswapV2Pair(pairA).token0();
        console.log("Token0 in PoolA:", token0A);
        console.log("TokenA address:", address(tokenA));
    }
    
    function _deployArbitrageContract() internal {
        console.log("5. Deploying flash swap arbitrage contract...");

        arbitrage = new FlashSwapArbitrage();
        console.log("FlashSwapArbitrage deployed at:", address(arbitrage));

        // Give arbitrage contract some initial funds for gas fees
        payable(address(arbitrage)).transfer(0.1 ether);
    }

    function _saveContracts() internal {
        console.log("6. Saving contract addresses...");

        saveContract("TokenA", address(tokenA));
        saveContract("TokenB", address(tokenB));
        saveContract("FactoryA", address(factoryA));
        saveContract("FactoryB", address(factoryB));
        saveContract("RouterA", address(routerA));
        saveContract("RouterB", address(routerB));
        saveContract("PairA", pairA);
        saveContract("PairB", pairB);
        saveContract("FlashSwapArbitrage", address(arbitrage));
        saveContract("WETHA", address(wethA));
        saveContract("WETHB", address(wethB));
    }

    // Function to execute arbitrage
    function executeArbitrage() public broadcaster {
        console.log("=== Executing Flash Swap Arbitrage ===");

        // Load deployed contracts
        _loadContracts();

        uint256 arbitrageAmount = 100 * 10**18; // 100 Token A

        console.log("Arbitrage amount:", arbitrageAmount);
        console.log("TokenA balance before arbitrage:", tokenA.balanceOf(address(arbitrage)));
        console.log("TokenB balance before arbitrage:", tokenB.balanceOf(address(arbitrage)));

        // Execute arbitrage
        arbitrage.startArbitrage(
            address(factoryA),
            address(factoryB),
            address(tokenA),
            address(tokenB),
            arbitrageAmount
        );

        console.log("TokenA balance after arbitrage:", tokenA.balanceOf(address(arbitrage)));
        console.log("TokenB balance after arbitrage:", tokenB.balanceOf(address(arbitrage)));

        console.log("=== Arbitrage Execution Complete ===");
    }

    function _loadContracts() internal {
        // Here we need to load contract addresses from deployment files
        // For simplicity, we redeploy (in actual use should load from JSON files)
        console.log("Loading deployed contracts...");
    }
}
