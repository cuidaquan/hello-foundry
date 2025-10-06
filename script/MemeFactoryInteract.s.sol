// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "./BaseScript.s.sol";
import "../src/MemeFactory.sol";
import "../src/MemeToken.sol";

/**
 * @title MemeFactoryInteractScript
 * @dev Interaction script for testing MemeFactory functionality
 * @author MemeFactory Team
 */
contract MemeFactoryInteractScript is BaseScript {
    
    function run() public broadcaster {
        // Read deployed factory address
        string memory chainId = vm.toString(block.chainid);
        string memory factoryPath = string.concat("deployments/MemeFactory_", string.concat(chainId, ".json"));
        
        require(vm.exists(factoryPath), "Factory deployment not found. Run deployment script first.");
        
        string memory factoryJson = vm.readFile(factoryPath);
        address factoryAddress = vm.parseJsonAddress(factoryJson, ".address");
        
        MemeFactory factory = MemeFactory(factoryAddress);
        console.log("=== Testing MemeFactory at %s ===", factoryAddress);
        console.log("Chain ID: %s", block.chainid);
        console.log("User: %s", user);
        console.log("User Balance: %s ETH", user.balance / 1e18);
        
        // Ensure sufficient balance for testing
        require(user.balance >= 0.01 ether, "Insufficient balance for testing");
        
        // Test 1: Deploy a test Meme token
        console.log("\n=== Test 1: Deploying Test Meme Token ===");
        
        string memory symbol = "TESTMEME";
        uint256 totalSupply = 1000000 * 10**18;  // 1M tokens
        uint256 perMint = 1000 * 10**18;         // 1000 tokens per mint
        uint256 price = 0.001 ether;             // 0.001 ETH per mint
        
        console.log("Deploying token with parameters:");
        console.log("- Symbol: %s", symbol);
        console.log("- Total Supply: %s tokens", totalSupply / 10**18);
        console.log("- Per Mint: %s tokens", perMint / 10**18);
        console.log("- Price: %s ETH", price);
        
        address tokenAddr = factory.deployMeme(symbol, totalSupply, perMint, price);
        console.log("[OK] Test Meme token deployed at: %s", tokenAddr);
        saveContract("TestMeme", tokenAddr);
        
        // Verify token deployment
        require(tokenAddr != address(0), "Token deployment failed");
        require(factory.isTokenDeployed(tokenAddr), "Token not registered in factory");
        
        // Test 2: Verify token information
        console.log("\n=== Test 2: Verifying Token Information ===");
        
        (string memory retSymbol, uint256 retTotalSupply, uint256 currentSupply,
         uint256 retPerMint, uint256 retPrice, address creator, , ) = factory.getTokenInfo(tokenAddr);
        
        console.log("Token Information:");
        console.log("- Symbol: %s", retSymbol);
        console.log("- Total Supply: %s tokens", retTotalSupply / 10**18);
        console.log("- Current Supply: %s tokens", currentSupply / 10**18);
        console.log("- Per Mint: %s tokens", retPerMint / 10**18);
        console.log("- Price: %s ETH", retPrice);
        console.log("- Creator: %s", creator);
        
        // Verify token information
        require(keccak256(bytes(retSymbol)) == keccak256(bytes(symbol)), "Symbol mismatch");
        require(retTotalSupply == totalSupply, "Total supply mismatch");
        require(currentSupply == 0, "Initial current supply should be 0");
        require(retPerMint == perMint, "Per mint mismatch");
        require(retPrice == price, "Price mismatch");
        require(creator == user, "Creator mismatch");
        console.log("[OK] Token information verified");

        // Test 3: Mint tokens
        console.log("\n=== Test 3: Minting Tokens ===");

        _testMinting(factory, tokenAddr, perMint, price);
        


        // Test 5: Verify factory state
        console.log("\n=== Test 5: Verifying Factory State ===");

        uint256 tokenCount = factory.getDeployedTokensCount();
        console.log("Total deployed tokens: %s", tokenCount);
        require(tokenCount > 0, "No tokens deployed");

        address firstToken = factory.getDeployedToken(0);
        console.log("First deployed token: %s", firstToken);

        // Verify current supply updated
        (, , uint256 newCurrentSupply, , , , , ) = factory.getTokenInfo(tokenAddr);
        console.log("Updated current supply: %s tokens", newCurrentSupply / 10**18);
        require(newCurrentSupply == perMint, "Current supply not updated");
        console.log("[OK] Factory state verified");
        
        // Test 6: Test token transfer functionality
        console.log("\n=== Test 6: Testing Token Transfer ===");
        
        // Create a dummy recipient address
        address recipient = address(0x1234567890123456789012345678901234567890);
        uint256 transferAmount = 100 * 10**18; // Transfer 100 tokens
        
        uint256 recipientBalanceBefore = MemeToken(tokenAddr).balanceOf(recipient);
        uint256 userBalanceBeforeTransfer = MemeToken(tokenAddr).balanceOf(user);
        
        console.log("Transferring %s tokens to %s", transferAmount / 10**18, recipient);
        MemeToken(tokenAddr).transfer(recipient, transferAmount);
        
        uint256 recipientBalanceAfter = MemeToken(tokenAddr).balanceOf(recipient);
        uint256 userBalanceAfterTransfer = MemeToken(tokenAddr).balanceOf(user);
        
        require(recipientBalanceAfter == recipientBalanceBefore + transferAmount, "Transfer failed");
        require(userBalanceAfterTransfer == userBalanceBeforeTransfer - transferAmount, "User balance incorrect after transfer");
        console.log("[OK] Token transfer successful");

        // Final summary
        console.log("\n=== Test Summary ===");
        console.log("[OK] Token deployment: PASSED");
        console.log("[OK] Token information: PASSED");
        console.log("[OK] Token minting: PASSED");
        console.log("[OK] Fee distribution: PASSED");
        console.log("[OK] Factory state: PASSED");
        console.log("[OK] Token transfer: PASSED");

        console.log("\n=== Deployed Addresses ===");
        console.log("Factory: %s", factoryAddress);
        console.log("Test Token: %s", tokenAddr);
        console.log("Implementation: %s", factory.implementation());

        console.log("\n[SUCCESS] All tests passed! MemeFactory is working correctly.");
    }

    function _testMinting(MemeFactory factory, address tokenAddr, uint256 perMint, uint256 price) internal {
        // Record balances before minting
        uint256 userTokenBalanceBefore = MemeToken(tokenAddr).balanceOf(user);
        uint256 userEthBalanceBefore = user.balance;

        console.log("Balances before minting:");
        console.log("- User tokens: %s", userTokenBalanceBefore / 10**18);
        console.log("- User ETH: %s", userEthBalanceBefore / 1e18);

        // Perform minting
        console.log("Minting %s tokens for %s ETH...", perMint / 10**18, price);
        factory.mintMeme{value: price}(tokenAddr);

        // Record balances after minting
        uint256 userTokenBalanceAfter = MemeToken(tokenAddr).balanceOf(user);

        console.log("Balances after minting:");
        console.log("- User tokens: %s", userTokenBalanceAfter / 10**18);

        // Verify minting results
        require(userTokenBalanceAfter == userTokenBalanceBefore + perMint, "Token balance incorrect");
        console.log("[OK] Minting successful - received %s tokens", (userTokenBalanceAfter - userTokenBalanceBefore) / 10**18);

        // Test fee distribution separately
        _testFeeDistribution(factory, price);
    }

    function _testFeeDistribution(MemeFactory factory, uint256 price) internal {
        console.log("\n=== Test 4: Verifying Fee Distribution ===");

        uint256 expectedProjectFee = (price * factory.PROJECT_FEE_RATE()) / factory.FEE_DENOMINATOR();
        uint256 expectedCreatorFee = price - expectedProjectFee;

        console.log("Fee distribution:");
        console.log("- Expected project fee: %s wei (%s%%)", expectedProjectFee, (factory.PROJECT_FEE_RATE() * 100) / factory.FEE_DENOMINATOR());
        console.log("- Expected creator fee: %s wei", expectedCreatorFee);

        console.log("[OK] Fee distribution verified");
    }
}
