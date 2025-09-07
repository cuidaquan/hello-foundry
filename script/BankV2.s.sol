// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./BaseScript.s.sol";
import "../src/BankV2.sol";

contract BankV2Script is BaseScript {

    function run() public broadcaster {
        BankV2 bankV2 = new BankV2();
        console.log("BankV2 deployed on %s", address(bankV2));
        saveContract("BankV2", address(bankV2));
    }
}