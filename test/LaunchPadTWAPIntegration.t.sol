// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/TWAPOracle.sol";
import "../src/MemeFactory.sol";
import "../src/MemeToken.sol";
import "./mocks/MockUniswap.sol";

/**
 * @title LaunchPadTWAPIntegration
 * @dev Integration test showing TWAP Oracle working with LaunchPad platform
 */
contract LaunchPadTWAPIntegration is Test {
    // ============ State Variables ============
    
    TWAPOracle public twapOracle;
    MemeFactory public memeFactory;
    MemeToken public memeTokenImplementation;
    
    MockUniswapV2Factory public mockFactory;
    MockUniswapV2Router public mockRouter;
    MockWETH public mockWETH;
    MockUniswapV2Pair public mockPair;
    
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public owner = makeAddr("owner");
    
    address public memeToken;
    
    // ============ Setup ============
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mock contracts
        mockWETH = new MockWETH();
        mockFactory = new MockUniswapV2Factory(owner);
        mockRouter = new MockUniswapV2Router(address(mockFactory), address(mockWETH));
        
        // Deploy MemeFactory
        memeTokenImplementation = new MemeToken();
        memeFactory = new MemeFactory(
            address(memeTokenImplementation),
            owner,
            address(mockRouter)
        );
        
        // Deploy TWAP Oracle
        twapOracle = new TWAPOracle(address(mockFactory), address(mockWETH));
        
        // Deploy a meme token through LaunchPad
        memeToken = memeFactory.deployMeme("DOGE", 1000000 * 10**18, 1000 * 10**18, 0.001 ether);
        
        // Create and set up mock pair
        mockPair = new MockUniswapV2Pair();
        mockPair.initialize(memeToken, address(mockWETH));
        mockFactory.setPair(address(mockPair));
        mockFactory.createPair(memeToken, address(mockWETH));
        
        // Set initial reserves (1000 WETH : 1000000 DOGE tokens)
        mockPair.setReserves(1000 * 10**18, 1000000 * 10**18);
        
        // Add token to TWAP Oracle
        twapOracle.addToken(memeToken);
        
        vm.stopPrank();
        
        // Give users some ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
    }

    // ============ Integration Tests ============
    
    function test_completeWorkflowWithTWAP() public {
        console.log("=== LaunchPad + TWAP Oracle Integration Test ===");
        
        // Step 1: Users mint tokens through LaunchPad
        console.log("\n--- Step 1: Users mint tokens ---");
        
        // Get token price directly from tokenInfos mapping
        (, , , , uint256 tokenPrice, , , , ,) = memeFactory.tokenInfos(memeToken);
        console.log("Token mint price:", tokenPrice);

        vm.prank(user1);
        memeFactory.mintMeme{value: tokenPrice}(memeToken);
        console.log("User1 minted DOGE tokens for", tokenPrice, "wei");

        vm.prank(user2);
        memeFactory.mintMeme{value: tokenPrice}(memeToken);
        console.log("User2 minted DOGE tokens for", tokenPrice, "wei");
        
        // Step 2: Simulate price changes and track TWAP
        console.log("\n--- Step 2: Simulate trading and price changes ---");
        
        uint256 baseTime = block.timestamp;
        
        // Trade 1: Price goes up (15 minutes later)
        vm.warp(baseTime + 15 minutes);
        mockPair.simulateTimeAndPriceChange(15 * 60, 900 * 10**18, 1100000 * 10**18);
        twapOracle.updateObservation(memeToken);
        console.log("Trade 1 (15min): Price increased - 900 WETH : 1,100,000 DOGE");
        
        // Trade 2: Price goes down (30 minutes later)
        vm.warp(baseTime + 30 minutes);
        mockPair.simulateTimeAndPriceChange(15 * 60, 1200 * 10**18, 800000 * 10**18);
        twapOracle.updateObservation(memeToken);
        console.log("Trade 2 (30min): Price decreased - 1,200 WETH : 800,000 DOGE");
        
        // Trade 3: Price stabilizes (45 minutes later)
        vm.warp(baseTime + 45 minutes);
        mockPair.simulateTimeAndPriceChange(15 * 60, 1000 * 10**18, 1000000 * 10**18);
        twapOracle.updateObservation(memeToken);
        console.log("Trade 3 (45min): Price stabilized - 1,000 WETH : 1,000,000 DOGE");
        
        // Trade 4: Another price movement (1 hour later)
        vm.warp(baseTime + 1 hours);
        mockPair.simulateTimeAndPriceChange(15 * 60, 950 * 10**18, 1050000 * 10**18);
        twapOracle.updateObservation(memeToken);
        console.log("Trade 4 (60min): Price up slightly - 950 WETH : 1,050,000 DOGE");
        
        // Step 3: Calculate TWAP prices
        console.log("\n--- Step 3: TWAP Price Analysis ---");
        
        uint256 twap30min = twapOracle.getTWAP(memeToken, 30 minutes);
        uint256 twap1hour = twapOracle.getTWAP(memeToken, 1 hours);
        
        console.log("TWAP (30 minutes):", twap30min);
        console.log("TWAP (1 hour):", twap1hour);
        
        // Convert TWAP to human-readable format (WETH per DOGE)
        uint256 wethPerDoge30min = (twap30min * 1e18) >> 112; // Convert from UQ112x112
        uint256 wethPerDoge1hour = (twap1hour * 1e18) >> 112;
        
        console.log("TWAP Price (30min): 1 DOGE =", wethPerDoge30min, "wei WETH");
        console.log("TWAP Price (1hour): 1 DOGE =", wethPerDoge1hour, "wei WETH");
        
        // Step 4: More users interact based on TWAP
        console.log("\n--- Step 4: Users trade based on TWAP ---");
        
        vm.prank(user3);
        memeFactory.mintMeme{value: tokenPrice}(memeToken);
        console.log("User3 minted DOGE tokens for", tokenPrice, "wei (based on TWAP analysis)");
        
        // Step 5: Final price update and TWAP calculation
        vm.warp(baseTime + 90 minutes);
        mockPair.simulateTimeAndPriceChange(30 * 60, 1100 * 10**18, 900000 * 10**18);
        twapOracle.updateObservation(memeToken);
        console.log("Final trade (90min): Price increased - 1,100 WETH : 900,000 DOGE");
        
        uint256 finalTWAP = twapOracle.getTWAP(memeToken, 1 hours);
        uint256 finalWethPerDoge = (finalTWAP * 1e18) >> 112;
        console.log("Final TWAP (1 hour):", finalTWAP);
        console.log("Final TWAP Price: 1 DOGE =", finalWethPerDoge, "wei WETH");
        
        // Step 6: Verify token balances and factory state
        console.log("\n--- Step 6: Final State Verification ---");
        
        uint256 user1Balance = MemeToken(memeToken).balanceOf(user1);
        uint256 user2Balance = MemeToken(memeToken).balanceOf(user2);
        uint256 user3Balance = MemeToken(memeToken).balanceOf(user3);
        
        console.log("User1 DOGE balance:", user1Balance / 10**18);
        console.log("User2 DOGE balance:", user2Balance / 10**18);
        console.log("User3 DOGE balance:", user3Balance / 10**18);
        
        (, , uint256 currentSupply, , , , ,) = memeFactory.getTokenInfo(memeToken);
        console.log("Total DOGE supply:", currentSupply / 10**18);
        
        // Verify TWAP Oracle has all observations
        TWAPOracle.Observation[] memory observations = twapOracle.getAllObservations(memeToken);
        console.log("Total TWAP observations:", observations.length);
        
        // Assertions
        assertEq(user1Balance, 1000 * 10**18);
        assertEq(user2Balance, 1000 * 10**18);
        assertEq(user3Balance, 1000 * 10**18);
        assertEq(observations.length, 6); // Initial + 5 updates
        assertGt(finalTWAP, 0);
        
        console.log("\n[SUCCESS] Integration test completed successfully!");
    }
    
    function test_twapOracleWithLaunchPadTokens() public {
        console.log("=== Testing TWAP Oracle with Multiple LaunchPad Tokens ===");
        
        // Deploy second meme token
        vm.prank(owner);
        address memeToken2 = memeFactory.deployMeme("SHIB", 2000000 * 10**18, 2000 * 10**18, 0.0005 ether);
        
        // Create pair for second token
        MockUniswapV2Pair mockPair2 = new MockUniswapV2Pair();
        mockPair2.initialize(memeToken2, address(mockWETH));
        mockPair2.setReserves(500 * 10**18, 2000000 * 10**18); // Different initial price

        // Set up factory to return the second pair
        mockFactory.setPair(address(mockPair2));
        mockFactory.createPair(memeToken2, address(mockWETH));

        // Add second token to oracle
        vm.prank(owner);
        twapOracle.addToken(memeToken2);
        
        // Simulate trades for both tokens
        uint256 baseTime = block.timestamp;
        
        // Update both tokens at different times
        vm.warp(baseTime + 20 minutes);
        mockPair.simulateTimeAndPriceChange(20 * 60, 1050 * 10**18, 950000 * 10**18);
        twapOracle.updateObservation(memeToken);
        
        mockPair2.simulateTimeAndPriceChange(20 * 60, 450 * 10**18, 2200000 * 10**18);
        twapOracle.updateObservation(memeToken2);
        
        vm.warp(baseTime + 40 minutes);
        mockPair.simulateTimeAndPriceChange(20 * 60, 980 * 10**18, 1020000 * 10**18);
        twapOracle.updateObservation(memeToken);
        
        mockPair2.simulateTimeAndPriceChange(20 * 60, 520 * 10**18, 1800000 * 10**18);
        twapOracle.updateObservation(memeToken2);
        
        // Calculate TWAP for both tokens
        uint256 twapDOGE = twapOracle.getTWAP(memeToken, 30 minutes);
        uint256 twapSHIB = twapOracle.getTWAP(memeToken2, 30 minutes);
        
        console.log("DOGE TWAP (30min):", twapDOGE);
        console.log("SHIB TWAP (30min):", twapSHIB);
        
        // Verify both tokens are supported
        assertTrue(twapOracle.supportedTokens(memeToken));
        assertTrue(twapOracle.supportedTokens(memeToken2));
        
        // Verify different TWAP values
        assertNotEq(twapDOGE, twapSHIB);
        assertGt(twapDOGE, 0);
        assertGt(twapSHIB, 0);
        
        console.log("SUCCESS: Multi-token TWAP test completed!");
    }
}
