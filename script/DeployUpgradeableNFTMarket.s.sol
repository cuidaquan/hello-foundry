// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "./BaseScript.s.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MyNFTUpgradeable} from "../src/MyNFTUpgradeable.sol";
import {NFTMarketUpgradeableV1} from "../src/NFTMarketUpgradeableV1.sol";
import {NFTMarketUpgradeableV2} from "../src/NFTMarketUpgradeableV2.sol";
import {ExtendedERC20} from "../src/ExtendedERC20.sol";

/**
 * @title DeployUpgradeableNFTMarket
 * @dev 部署可升级的 NFT Market 系统的脚本
 */
contract DeployUpgradeableNFTMarket is BaseScript {
    function run() external broadcaster {
        console.log("Deploying Upgradeable NFT Market System...");
        console.log("Deployer balance:", user.balance);

        // 1. 部署 ERC20 代币
        ExtendedERC20 token = new ExtendedERC20("Payment Token", "PAY", 0);
        console.log("Payment Token deployed at:", address(token));
        saveContract("PaymentToken", address(token));

        // 2. 部署可升级的 NFT 合约
        MyNFTUpgradeable nftImpl = new MyNFTUpgradeable();
        console.log("NFT Implementation deployed at:", address(nftImpl));
        saveContract("NFTImplementation", address(nftImpl));

        bytes memory nftInitData = abi.encodeCall(MyNFTUpgradeable.initialize, ());
        ERC1967Proxy nftProxy = new ERC1967Proxy(address(nftImpl), nftInitData);
        console.log("NFT Proxy deployed at:", address(nftProxy));
        saveContract("NFTProxy", address(nftProxy));

        // 3. 部署可升级的 NFT Market V1
        NFTMarketUpgradeableV1 marketImplV1 = new NFTMarketUpgradeableV1();
        console.log("Market V1 Implementation deployed at:", address(marketImplV1));
        saveContract("MarketV1Implementation", address(marketImplV1));

        bytes memory marketInitData =
            abi.encodeCall(NFTMarketUpgradeableV1.initialize, (address(token), address(nftProxy)));
        ERC1967Proxy marketProxy = new ERC1967Proxy(address(marketImplV1), marketInitData);
        console.log("Market Proxy deployed at:", address(marketProxy));
        saveContract("MarketProxy", address(marketProxy));

        console.log("\n=== Deployment Summary ===");
        console.log("Payment Token:", address(token));
        console.log("NFT Implementation:", address(nftImpl));
        console.log("NFT Proxy:", address(nftProxy));
        console.log("Market V1 Implementation:", address(marketImplV1));
        console.log("Market Proxy:", address(marketProxy));
    }
}

/**
 * @title UpgradeNFTMarketToV2
 * @dev 升级 NFT Market 到 V2 的脚本
 */
contract UpgradeNFTMarketToV2 is BaseScript {
    function run() external broadcaster {
        // 从环境变量读取代理合约地址
        address marketProxyAddress = vm.envAddress("MARKET_PROXY_ADDRESS");

        console.log("Upgrading Market Proxy at:", marketProxyAddress);

        // 部署新的 V2 实现合约
        NFTMarketUpgradeableV2 marketImplV2 = new NFTMarketUpgradeableV2();
        console.log("Market V2 Implementation deployed at:", address(marketImplV2));
        saveContract("MarketV2Implementation", address(marketImplV2));

        // 升级代理合约
        NFTMarketUpgradeableV1 marketProxy = NFTMarketUpgradeableV1(marketProxyAddress);
        marketProxy.upgradeToAndCall(address(marketImplV2), "");
        console.log("Market Proxy upgraded to V2");

        console.log("\n=== Upgrade Summary ===");
        console.log("Market V2 Implementation:", address(marketImplV2));
        console.log("Market Proxy:", marketProxyAddress);
    }
}
