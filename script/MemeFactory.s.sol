// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "./BaseScript.s.sol";
import "../src/MemeFactory.sol";
import "../src/MemeToken.sol";

/**
 * @title MemeFactoryScript
 * @dev Deployment script for MemeFactory system
 * @author MemeFactory Team
 */
contract MemeFactoryScript is BaseScript {
    
    function run() public broadcaster {
        console.log("=== Starting MemeFactory Deployment ===");
        console.log("Chain ID: %s", block.chainid);
        console.log("Deployer: %s", user);
        console.log("Deployer Balance: %s ETH", user.balance / 1e18);
        
        // Ensure sufficient balance for deployment
        require(user.balance >= 0.01 ether, "Insufficient balance for deployment");
        
        // 1. Deploy MemeToken implementation contract
        console.log("\n1. Deploying MemeToken implementation...");
        MemeToken implementation = new MemeToken();
        console.log("MemeToken implementation deployed at: %s", address(implementation));
        saveContract("MemeToken_Implementation", address(implementation));
        
        // Verify implementation deployment
        require(address(implementation) != address(0), "Implementation deployment failed");
        console.log("[OK] Implementation deployment verified");
        
        // 2. Deploy MemeFactory contract
        console.log("\n2. Deploying MemeFactory...");
        MemeFactory factory = new MemeFactory(
            address(implementation),
            user, // Use deployer as project owner
            address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D) // Uniswap V2 Router
        );
        console.log("MemeFactory deployed at: %s", address(factory));
        saveContract("MemeFactory", address(factory));
        
        // Verify factory deployment
        require(address(factory) != address(0), "Factory deployment failed");
        require(factory.implementation() == address(implementation), "Implementation mismatch");
        require(factory.projectOwner() == user, "Project owner mismatch");
        console.log("[OK] Factory deployment verified");
        
        // 3. Verify system configuration
        console.log("\n3. Verifying system configuration...");
        uint256 feeRate = factory.PROJECT_FEE_RATE();
        uint256 feeDenominator = factory.FEE_DENOMINATOR();
        console.log("Project fee rate: %s basis points (%s%%)", feeRate, (feeRate * 100) / feeDenominator);
        console.log("Fee denominator: %s", feeDenominator);
        
        require(feeRate == 100, "Incorrect fee rate"); // 1%
        require(feeDenominator == 10000, "Incorrect fee denominator");
        console.log("[OK] System configuration verified");
        
        // 4. Output deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Network: %s", _getNetworkName(block.chainid));
        console.log("Chain ID: %s", block.chainid);
        console.log("Deployer: %s", user);
        console.log("Implementation: %s", address(implementation));
        console.log("Factory: %s", address(factory));
        console.log("Project Owner: %s", factory.projectOwner());
        console.log("Project Fee Rate: %s%% (%s basis points)", (feeRate * 100) / feeDenominator, feeRate);
        
        // 5. Calculate deployment costs
        uint256 finalBalance = user.balance;
        uint256 deploymentCost = (user.balance < finalBalance) ? 0 : finalBalance - user.balance;
        console.log("Deployment Cost: %s ETH", deploymentCost / 1e18);
        
        // 6. Output next steps
        console.log("\n=== Next Steps ===");
        console.log("1. Verify contracts on Etherscan (if --verify flag was used)");
        console.log("2. Run interaction script: forge script script/MemeFactoryInteract.s.sol --rpc-url <RPC_URL> --broadcast");
        console.log("3. Update frontend configuration with new addresses");
        console.log("4. Test token deployment and minting functionality");
        
        // 7. Output useful commands
        console.log("\n=== Useful Commands ===");
        console.log("# Read factory address:");
        console.log("FACTORY_ADDRESS=$(jq -r '.address' deployments/MemeFactory_%s.json)", block.chainid);
        console.log("# Read implementation address:");
        console.log("IMPL_ADDRESS=$(jq -r '.address' deployments/MemeToken_Implementation_%s.json)", block.chainid);
        console.log("# Check factory status:");
        console.log("cast call $FACTORY_ADDRESS \"getDeployedTokensCount()\" --rpc-url <RPC_URL>");
        
        console.log("\n[SUCCESS] MemeFactory deployment completed successfully!");
    }
    
    /**
     * @dev Get network name from chain ID
     * @param chainId Chain ID
     * @return name Network name
     */
    function _getNetworkName(uint256 chainId) internal pure returns (string memory name) {
        if (chainId == 1) return "Mainnet";
        if (chainId == 11155111) return "Sepolia";
        if (chainId == 5) return "Goerli";
        if (chainId == 137) return "Polygon";
        if (chainId == 80001) return "Mumbai";
        if (chainId == 31337) return "Localhost";
        return "Unknown";
    }
}
