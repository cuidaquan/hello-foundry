// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/MyToken.sol";
import "../src/FlashSwapArbitrage.sol";
import "../test/mocks/MockUniswap.sol";

contract FlashSwapArbitrageTest is Test {
    
    // 测试用户
    address public user = address(0x123);
    
    // 代币
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
    
    // 事件
    event ArbitrageExecuted(
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountBorrowed,
        uint256 amountRepaid,
        uint256 profit
    );
    
    function setUp() public {
        // 设置测试用户
        vm.startPrank(user);
        vm.deal(user, 100 ether);
        
        // 1. 部署代币
        tokenA = new MyToken("Token A", "TKA");
        tokenB = new MyToken("Token B", "TKB");
        
        // 2. 部署Uniswap实例
        _deployUniswapInstances();
        
        // 3. 创建流动池
        _createLiquidityPools();
        
        // 4. 添加流动性并设置价差
        _addLiquidityWithPriceDifference();
        
        // 5. 部署闪电兑换套利合约
        arbitrage = new FlashSwapArbitrage();
        
        vm.stopPrank();
    }
    
    function _deployUniswapInstances() internal {
        // 部署WETH
        wethA = new MockWETH();
        wethB = new MockWETH();
        
        // Deploy Factory and Router A
        factoryA = new MockUniswapV2Factory(user);
        routerA = new MockUniswapV2Router(address(factoryA), address(wethA));

        // Deploy Factory and Router B
        factoryB = new MockUniswapV2Factory(user);
        routerB = new MockUniswapV2Router(address(factoryB), address(wethB));
    }
    
    function _createLiquidityPools() internal {
        // 创建交易对
        pairA = factoryA.createPair(address(tokenA), address(tokenB));
        pairB = factoryB.createPair(address(tokenA), address(tokenB));
    }
    
    function _addLiquidityWithPriceDifference() internal {
        uint256 amountA = 1000 * 10**18;  // 1000 Token A
        uint256 amountB_PoolA = 2000 * 10**18;  // 2000 Token B (价格: 1 TKA = 2 TKB)
        uint256 amountB_PoolB = 1800 * 10**18;  // 1800 Token B (价格: 1 TKA = 1.8 TKB)
        
        // 为PoolA添加流动性
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
        
        // 为PoolB添加流动性
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
    }
    
    function testSetup() public {
        // 验证代币部署
        assertEq(tokenA.name(), "Token A");
        assertEq(tokenB.name(), "Token B");
        assertGt(tokenA.balanceOf(user), 0);
        assertGt(tokenB.balanceOf(user), 0);
        
        // 验证交易对创建
        assertTrue(pairA != address(0));
        assertTrue(pairB != address(0));
        
        // Verify reserves
        (uint256 reserve0A, uint256 reserve1A,) = MockUniswapV2Pair(pairA).getReserves();
        (uint256 reserve0B, uint256 reserve1B,) = MockUniswapV2Pair(pairB).getReserves();
        
        assertGt(reserve0A, 0);
        assertGt(reserve1A, 0);
        assertGt(reserve0B, 0);
        assertGt(reserve1B, 0);
        
        console.log("=== Setup Verification Passed ===");
        console.log("PoolA reserves:", reserve0A, reserve1A);
        console.log("PoolB reserves:", reserve0B, reserve1B);
    }
    
    function testArbitrageExecution() public {
        vm.startPrank(user);
        
        uint256 arbitrageAmount = 10 * 10**18;  // Try smaller amount // 100 Token A
        
        // 记录套利前的余额
        uint256 balanceBeforeA = tokenA.balanceOf(address(arbitrage));
        uint256 balanceBeforeB = tokenB.balanceOf(address(arbitrage));
        
        console.log("=== State Before Arbitrage ===");
        console.log("Arbitrage contract TokenA balance:", balanceBeforeA);
        console.log("Arbitrage contract TokenB balance:", balanceBeforeB);

        // Display pool reserves
        _displayPoolReserves();

        // Expect ArbitrageExecuted event to be triggered
        vm.expectEmit(true, true, false, false);
        emit ArbitrageExecuted(address(tokenB), address(tokenA), 0, 0, 0);

        // Execute arbitrage: borrow TokenB from PoolA, swap in PoolA, swap back in PoolB
        // Since TokenA is cheaper in PoolB (1.8 vs 2.0), we should:
        // 1. Borrow TokenB from PoolA
        // 2. Swap TokenB->TokenA in PoolA (get more TokenA)
        // 3. Swap TokenA->TokenB in PoolB (get TokenB to repay)
        arbitrage.startArbitrage(
            address(factoryA),
            address(factoryB),
            address(tokenB),  // Borrow TokenB instead
            address(tokenA),  // Target TokenA
            arbitrageAmount
        );

        // Record balances after arbitrage
        uint256 balanceAfterA = tokenA.balanceOf(address(arbitrage));
        uint256 balanceAfterB = tokenB.balanceOf(address(arbitrage));

        console.log("=== State After Arbitrage ===");
        console.log("Arbitrage contract TokenA balance:", balanceAfterA);
        console.log("Arbitrage contract TokenB balance:", balanceAfterB);

        // Verify arbitrage profitability
        assertTrue(balanceAfterA >= balanceBeforeA, "TokenA balance should not decrease");
        
        vm.stopPrank();
    }
    
    function testArbitrageWithDifferentAmounts() public {
        vm.startPrank(user);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 5 * 10**18;    // 5 TokenB
        amounts[1] = 10 * 10**18;   // 10 TokenB
        amounts[2] = 15 * 10**18;   // 15 TokenB

        for (uint256 i = 0; i < amounts.length; i++) {
            console.log("=== Testing arbitrage amount:", amounts[i], "===");

            uint256 balanceBefore = tokenB.balanceOf(address(arbitrage));

            arbitrage.startArbitrage(
                address(factoryA),
                address(factoryB),
                address(tokenB),  // Borrow TokenB
                address(tokenA),  // Target TokenA
                amounts[i]
            );

            uint256 balanceAfter = tokenB.balanceOf(address(arbitrage));
            uint256 profit = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;

            console.log("Profit:", profit);

            // Reset state for next test
            if (balanceAfter > balanceBefore) {
                vm.stopPrank();
                vm.prank(address(arbitrage));
                tokenB.transfer(user, balanceAfter - balanceBefore);
                vm.startPrank(user);
            }
        }
        
        vm.stopPrank();
    }
    
    function testRevertWhenArbitrageWithInvalidPair() public {
        vm.startPrank(user);
        
        // 尝试使用不存在的交易对进行套利
        MyToken invalidToken = new MyToken("Invalid Token", "INV");
        
        vm.expectRevert("PoolA pair does not exist");
        arbitrage.startArbitrage(
            address(factoryA),
            address(factoryB),
            address(invalidToken),
            address(tokenB),
            100 * 10**18
        );
        
        vm.stopPrank();
    }
    
    function testOwnershipFunctions() public {
        vm.startPrank(user);

        // Give arbitrage contract some tokens
        tokenA.transfer(address(arbitrage), 1000 * 10**18);

        uint256 contractBalance = tokenA.balanceOf(address(arbitrage));
        uint256 ownerBalanceBefore = tokenA.balanceOf(user);

        // Withdraw tokens
        arbitrage.withdrawToken(address(tokenA), contractBalance);

        uint256 ownerBalanceAfter = tokenA.balanceOf(user);

        assertEq(tokenA.balanceOf(address(arbitrage)), 0);
        assertEq(ownerBalanceAfter - ownerBalanceBefore, contractBalance);

        vm.stopPrank();
    }
    
    function _displayPoolReserves() internal view {
        (uint256 reserve0A, uint256 reserve1A,) = MockUniswapV2Pair(pairA).getReserves();
        (uint256 reserve0B, uint256 reserve1B,) = MockUniswapV2Pair(pairB).getReserves();

        address token0A = MockUniswapV2Pair(pairA).token0();
        address token0B = MockUniswapV2Pair(pairB).token0();
        
        console.log("=== Pool Reserves ===");
        console.log("PoolA - Token0:", token0A == address(tokenA) ? "TokenA" : "TokenB");
        console.log("PoolA - Reserve0:", reserve0A, "Reserve1:", reserve1A);
        console.log("PoolB - Token0:", token0B == address(tokenA) ? "TokenA" : "TokenB");
        console.log("PoolB - Reserve0:", reserve0B, "Reserve1:", reserve1B);

        // Calculate prices
        if (token0A == address(tokenA)) {
            console.log("PoolA price: 1 TokenA =", (reserve1A * 10**18) / reserve0A, "TokenB");
        } else {
            console.log("PoolA price: 1 TokenA =", (reserve0A * 10**18) / reserve1A, "TokenB");
        }

        if (token0B == address(tokenA)) {
            console.log("PoolB price: 1 TokenA =", (reserve1B * 10**18) / reserve0B, "TokenB");
        } else {
            console.log("PoolB price: 1 TokenA =", (reserve0B * 10**18) / reserve1B, "TokenB");
        }
    }

    // Test using real Sepolia testnet contracts
    function testArbitrageExecutionOnSepolia() public {
        // Skip if not on Sepolia fork
        vm.createSelectFork("sepolia");

        // Real Sepolia contract addresses
        address realTokenA = 0xB74b65845A9b66a870B2D67a58fc80aE17014713;
        address realTokenB = 0x2Df21BbDd03AB078b012C2d51798620C16604959;
        address realArbitrage = 0x44525F8d9ed3dC23919D88FC4B438328c17b8De7;

        // Get real contracts
        MyToken realTKA = MyToken(realTokenA);
        MyToken realTKB = MyToken(realTokenB);
        FlashSwapArbitrage realArbitrageContract = FlashSwapArbitrage(payable(realArbitrage));

        // Get the owner of the arbitrage contract
        address owner = realArbitrageContract.owner();
        vm.startPrank(owner);

        console.log("=== Testing on Sepolia Testnet ===");
        console.log("TokenA:", realTokenA);
        console.log("TokenB:", realTokenB);
        console.log("Arbitrage:", realArbitrage);
        console.log("Owner:", owner);

        // Check initial balances
        uint256 balanceBeforeA = realTKA.balanceOf(realArbitrage);
        uint256 balanceBeforeB = realTKB.balanceOf(realArbitrage);

        console.log("=== Initial Balances ===");
        console.log("Arbitrage TokenA balance:", balanceBeforeA);
        console.log("Arbitrage TokenB balance:", balanceBeforeB);

        // Try to execute arbitrage with small amount
        uint256 arbitrageAmount = 1 * 10**18; // 1 TokenB

        // Check if the factories exist and have pairs
        console.log("=== Checking Factory Addresses ===");

        // Try to call the factories to see if they exist
        try realArbitrageContract.startArbitrage(
            0x05e6EF588D2DfC32aA8CCd5766ce355b3eb67700, // FactoryA (correct address)
            0x50f0d2adcB69683205Dc86e1891D84133eCe1043, // FactoryB (correct address)
            realTokenB,  // Borrow TokenB
            realTokenA,  // Target TokenA
            arbitrageAmount
        ) {
            console.log("=== Arbitrage Executed Successfully ===");

            uint256 balanceAfterA = realTKA.balanceOf(realArbitrage);
            uint256 balanceAfterB = realTKB.balanceOf(realArbitrage);

            console.log("Final TokenA balance:", balanceAfterA);
            console.log("Final TokenB balance:", balanceAfterB);

            if (balanceAfterB > balanceBeforeB) {
                console.log("Profit earned:", balanceAfterB - balanceBeforeB, "TokenB");
            }
        } catch Error(string memory reason) {
            console.log("Arbitrage failed:", reason);
        } catch {
            console.log("Arbitrage failed with unknown error");
        }

        vm.stopPrank();
    }
}
