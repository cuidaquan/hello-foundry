// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "./BaseScript.s.sol";
import "../src/BankWithAutomation.sol";

contract DeployBankWithAutomation is BaseScript {

    function run() public broadcaster {
        // 设置触发阈值为 0.1 ETH (可根据需要调整)
        uint256 threshold = 0.1 ether;

        BankWithAutomation bank = new BankWithAutomation(threshold);
        console.log("BankWithAutomation deployed on %s", address(bank));
        console.log("Threshold set to: %s wei", threshold);
        saveContract("BankWithAutomation", address(bank));
    }
}
