// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../src/MultiSigWallet.sol";
import "./BaseScript.s.sol";

/**
 * @title MultiSigWallet部署脚本
 * @dev 用于部署多签钱包合约
 */
contract MultiSigWalletScript is BaseScript {

    function run() public broadcaster{
        // 设置多签持有人（示例地址，实际使用时需要替换）
        address[] memory owners = new address[](3);
        owners[0] = 0x86d8B686964fddd33c62B9277788c21a5805E854;
        owners[1] = 0x6cc3Aac8a7d769B5fe464b406849392539f22bf5;
        owners[2] = 0x3dD6BA106b13cB6538A9eD9fE1a51E115f9EE664;
        
        uint256 required = 2; // 需要2个签名

        // 部署合约
        MultiSigWallet multiSigWallet = new MultiSigWallet(owners, required);
        console.log("MultiSigWallet deployed on %s", address(multiSigWallet));

        // 保存部署信息
        saveContract("MultiSigWallet", address(multiSigWallet));
        
    }

}
