// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/AirdropMerkleNFTMarket.sol";
import "../src/CUIDAQUANToken.sol";
import "../src/MyNFT.sol";

/**
 * @title Deploy AirdropMerkleNFTMarket
 * @dev 部署脚本，包含token、NFT和市场合约的完整部署
 */
contract DeployAirdropMerkleNFTMarket is Script {
    
    // Merkle根（示例，实际使用时需要根据真实白名单生成）
    bytes32 constant MERKLE_ROOT = 0x1234567890123456789012345678901234567890123456789012345678901234;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. 部署支付代币 (支持permit的ERC20)
        CUIDAQUANToken token = new CUIDAQUANToken(1000000); // 100万代币
        console.log("Token deployed at:", address(token));
        
        // 2. 部署NFT合约
        MyNFT nft = new MyNFT();
        console.log("NFT deployed at:", address(nft));
        
        // 3. 部署AirdropMerkleNFTMarket
        AirdropMerkleNFTMarket market = new AirdropMerkleNFTMarket(
            address(token),
            address(nft),
            MERKLE_ROOT
        );
        console.log("AirdropMerkleNFTMarket deployed at:", address(market));
        
        // 4. Mint some test NFTs
        for (uint256 i = 1; i <= 5; i++) {
            string memory tokenURI = string(abi.encodePacked("https://example.com/token/", vm.toString(i)));
            nft.mint(vm.addr(deployerPrivateKey), tokenURI);
        }
        console.log("Minted 5 test NFTs");
        
        vm.stopBroadcast();
        
        // 记录部署信息到文件
        string memory deploymentInfo = string(abi.encodePacked(
            "{\n",
            '  "token": "', vm.toString(address(token)), '",\n',
            '  "nft": "', vm.toString(address(nft)), '",\n',
            '  "market": "', vm.toString(address(market)), '",\n',
            '  "merkleRoot": "', vm.toString(MERKLE_ROOT), '"\n',
            "}"
        ));
        
        vm.writeFile("./deployments/airdrop-merkle-nft-market.json", deploymentInfo);
        console.log("Deployment info saved to deployments/airdrop-merkle-nft-market.json");
    }
}