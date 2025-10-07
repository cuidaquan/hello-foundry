// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/TWAPOracle.sol";
import "../src/MemeFactory.sol";
import "../src/MemeToken.sol";
import "./mocks/MockUniswap.sol";

/**
 * @title TWAPOracleTest
 * @dev Test contract for TWAP Oracle functionality
 */
contract TWAPOracleTest is Test {
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
    address public owner = makeAddr("owner");
    
    address public testToken;
    
    // ============ Events ============
    
    event TokenAdded(address indexed token, address indexed pair);
    event ObservationUpdated(address indexed token, uint32 timestamp, uint256 price0Cumulative, uint256 price1Cumulative);
    event TWAPCalculated(address indexed token, uint256 twapPrice, uint256 period);

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
        
        // Deploy a test meme token
        testToken = memeFactory.deployMeme("TEST", 1000000 * 10**18, 1000 * 10**18, 0.001 ether);
        
        // Create mock pair
        mockPair = new MockUniswapV2Pair();
        mockPair.initialize(testToken, address(mockWETH));

        // Set up mock factory to return our pair
        mockFactory.setPair(address(mockPair));

        // Create the pair in the factory's mapping
        mockFactory.createPair(testToken, address(mockWETH));
        
        // Set initial reserves (1000 WETH : 1000000 TEST tokens)
        // This gives a price of 1 WETH = 1000 TEST tokens
        mockPair.setReserves(1000 * 10**18, 1000000 * 10**18); // WETH is token0, TEST is token1
        
        vm.stopPrank();
        
        // Give users some ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    // ============ Test Functions ============
    
    function test_addToken_Success() public {
        vm.prank(owner);
        
        vm.expectEmit(true, true, false, false);
        emit TokenAdded(testToken, address(mockPair));
        
        twapOracle.addToken(testToken);
        
        assertTrue(twapOracle.supportedTokens(testToken));
        
        // Check that an initial observation was created
        TWAPOracle.Observation memory obs = twapOracle.getLatestObservation(testToken);
        assertEq(obs.timestamp, block.timestamp);
    }
    
    function test_addToken_RevertWhenNotOwner() public {
        vm.prank(user1);
        
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        twapOracle.addToken(testToken);
    }
    
    function test_addToken_RevertWhenTokenAlreadySupported() public {
        vm.startPrank(owner);
        
        twapOracle.addToken(testToken);
        
        vm.expectRevert("TWAPOracle: token already supported");
        twapOracle.addToken(testToken);
        
        vm.stopPrank();
    }
    
    function test_updateObservation_Success() public {
        vm.prank(owner);
        twapOracle.addToken(testToken);
        
        // Simulate time passing and price change
        vm.warp(block.timestamp + 1 hours);
        mockPair.simulateTimeAndPriceChange(3600, 800 * 10**18, 1200000 * 10**18); // Price changed
        
        vm.expectEmit(true, false, false, false);
        emit ObservationUpdated(testToken, uint32(block.timestamp), 0, 0);
        
        twapOracle.updateObservation(testToken);
        
        // Check that we now have 2 observations
        TWAPOracle.Observation[] memory observations = twapOracle.getAllObservations(testToken);
        assertEq(observations.length, 2);
    }
    
    function test_getTWAP_Success() public {
        vm.prank(owner);
        twapOracle.addToken(testToken);
        
        // Wait and create multiple price observations
        _simulateMultipleTradesOverTime();
        
        // Get TWAP for 1 hour period
        uint256 twapPrice = twapOracle.getTWAP(testToken, 1 hours);
        
        // TWAP should be greater than 0
        assertGt(twapPrice, 0);
        
        console.log("TWAP Price (1 hour):", twapPrice);
    }
    
    function test_getTWAP_RevertWhenTokenNotSupported() public {
        address unsupportedToken = makeAddr("unsupported");
        
        vm.expectRevert(TWAPOracle.TokenNotSupported.selector);
        twapOracle.getTWAP(unsupportedToken, 1 hours);
    }
    
    function test_getTWAP_RevertWhenInvalidPeriod() public {
        vm.prank(owner);
        twapOracle.addToken(testToken);
        
        // Period too short
        vm.expectRevert(TWAPOracle.InvalidPeriod.selector);
        twapOracle.getTWAP(testToken, 5 minutes);
        
        // Period too long
        vm.expectRevert(TWAPOracle.InvalidPeriod.selector);
        twapOracle.getTWAP(testToken, 25 hours);
    }
    
    function test_getTWAP_RevertWhenInsufficientObservations() public {
        vm.prank(owner);
        twapOracle.addToken(testToken);
        
        // Try to get TWAP immediately after adding token (only 1 observation)
        vm.expectRevert(TWAPOracle.InsufficientObservations.selector);
        twapOracle.getTWAP(testToken, 1 hours);
    }
    
    function test_simulateMultipleTradesOverTime() public {
        vm.prank(owner);
        twapOracle.addToken(testToken);
        
        console.log("=== Simulating Multiple Trades Over Time ===");
        
        // Initial state
        TWAPOracle.Observation memory initialObs = twapOracle.getLatestObservation(testToken);
        console.log("Initial observation timestamp:", initialObs.timestamp);
        console.log("Initial price0Cumulative:", initialObs.price0Cumulative);
        console.log("Initial price1Cumulative:", initialObs.price1Cumulative);
        
        // Simulate trades at different times with different prices
        uint256 baseTime = block.timestamp;
        
        // Trade 1: After 15 minutes, price goes up (less WETH, more tokens)
        vm.warp(baseTime + 15 minutes);
        mockPair.simulateTimeAndPriceChange(15 * 60, 900 * 10**18, 1100000 * 10**18);
        twapOracle.updateObservation(testToken);
        console.log("Trade 1 (15min): 900 WETH : 1,100,000 TEST");
        
        // Trade 2: After 30 minutes, price goes down (more WETH, less tokens)
        vm.warp(baseTime + 30 minutes);
        mockPair.simulateTimeAndPriceChange(15 * 60, 1100 * 10**18, 900000 * 10**18);
        twapOracle.updateObservation(testToken);
        console.log("Trade 2 (30min): 1,100 WETH : 900,000 TEST");
        
        // Trade 3: After 45 minutes, price stabilizes
        vm.warp(baseTime + 45 minutes);
        mockPair.simulateTimeAndPriceChange(15 * 60, 1000 * 10**18, 1000000 * 10**18);
        twapOracle.updateObservation(testToken);
        console.log("Trade 3 (45min): 1,000 WETH : 1,000,000 TEST");
        
        // Trade 4: After 1 hour, another price change
        vm.warp(baseTime + 1 hours);
        mockPair.simulateTimeAndPriceChange(15 * 60, 950 * 10**18, 1050000 * 10**18);
        twapOracle.updateObservation(testToken);
        console.log("Trade 4 (60min): 950 WETH : 1,050,000 TEST");
        
        // Trade 5: After 1.5 hours
        vm.warp(baseTime + 90 minutes);
        mockPair.simulateTimeAndPriceChange(30 * 60, 1050 * 10**18, 950000 * 10**18);
        twapOracle.updateObservation(testToken);
        console.log("Trade 5 (90min): 1,050 WETH : 950,000 TEST");
        
        // Now we can calculate TWAP for different periods
        console.log("\n=== TWAP Calculations ===");
        
        try twapOracle.getTWAP(testToken, 30 minutes) returns (uint256 twap30min) {
            console.log("TWAP (30 minutes):", twap30min);
        } catch {
            console.log("TWAP (30 minutes): Failed to calculate");
        }
        
        try twapOracle.getTWAP(testToken, 1 hours) returns (uint256 twap1hour) {
            console.log("TWAP (1 hour):", twap1hour);
        } catch {
            console.log("TWAP (1 hour): Failed to calculate");
        }
        
        // Show all observations
        TWAPOracle.Observation[] memory allObs = twapOracle.getAllObservations(testToken);
        console.log("\n=== All Observations ===");
        for (uint i = 0; i < allObs.length; i++) {
            console.log("Observation", i, ":");
            console.log("  Timestamp:", allObs[i].timestamp);
            console.log("  Price0Cumulative:", allObs[i].price0Cumulative);
            console.log("  Price1Cumulative:", allObs[i].price1Cumulative);
        }
    }
    
    // ============ Helper Functions ============
    
    function _simulateMultipleTradesOverTime() internal {
        uint256 baseTime = block.timestamp;
        
        // Create multiple observations over time
        for (uint i = 1; i <= 5; i++) {
            vm.warp(baseTime + (i * 15 minutes));

            // Simulate different price levels
            uint112 wethReserve;
            uint112 tokenReserve;

            if (i % 2 == 0) {
                wethReserve = uint112(1000 * 10**18 + 100 * 10**18);
                tokenReserve = uint112(1000000 * 10**18 - 100000 * 10**18);
            } else {
                wethReserve = uint112(1000 * 10**18 - 100 * 10**18);
                tokenReserve = uint112(1000000 * 10**18 + 100000 * 10**18);
            }

            mockPair.simulateTimeAndPriceChange(15 * 60, wethReserve, tokenReserve);
            twapOracle.updateObservation(testToken);
        }
    }
}
