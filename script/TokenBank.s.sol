// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "./BaseScript.s.sol";
import "../src/TokenBank.sol";

contract TokenBankScript is BaseScript {

    function run() public broadcaster {
        TokenBank token = new TokenBank(0x89865AAF2251b10ffc80CE4A809522506BF10bA2);
        console.log("TokenBank deployed on %s", address(token));
        saveContract("TokenBank", address(token));
    }
}
