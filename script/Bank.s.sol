// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./BaseScript.s.sol";
import "../src/Bank.sol";

contract BankScript is BaseScript {

    function run() public broadcaster {
        Bank bank = new Bank();
        console.log("Bank deployed on %s", address(bank));
        saveContract("Bank", address(bank));
    }
}
