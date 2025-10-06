// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "./BaseScript.s.sol";
import "../src/MemeFactory.sol";
import "../src/MemeToken.sol";

/**
 * @title LaunchPad Deployment Script
 * @dev Script to deploy the LaunchPad platform with 5% fees and Uniswap integration
 */
contract LaunchPadScript is BaseScript {
    // Sepolia testnet Uniswap V2 Router
    address constant UNISWAP_V2_ROUTER = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;

    function run() public broadcaster {
        console.log("Deploying LaunchPad platform...");
        console.log("Deployer address:", user);
        console.log("Deployer balance:", user.balance);

        // Deploy MemeToken implementation
        MemeToken implementation = new MemeToken();
        console.log("MemeToken implementation deployed at:", address(implementation));
        saveContract("MemeToken_Implementation", address(implementation));

        // Use Sepolia Uniswap V2 Router
        address uniswapRouter = UNISWAP_V2_ROUTER;

        // Deploy MemeFactory with 5% fees and Uniswap integration
        MemeFactory factory = new MemeFactory(
            address(implementation),
            user, // Project owner from BaseScript
            uniswapRouter
        );
        console.log("MemeFactory deployed at:", address(factory));
        saveContract("MemeFactory", address(factory));

        // Verify deployment
        console.log("Project fee rate:", factory.PROJECT_FEE_RATE(), "basis points (5%)");
        console.log("Project owner:", factory.projectOwner());
        console.log("Uniswap router:", factory.uniswapRouter());
        console.log("Implementation:", factory.implementation());

        console.log("LaunchPad platform deployed successfully!");
    }
    

}


