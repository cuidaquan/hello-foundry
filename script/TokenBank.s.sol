// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "./BaseScript.s.sol";
import "../src/TokenBank.sol";

contract TokenBankScript is BaseScript {

    function run() public broadcaster {
        TokenBank token = new TokenBank(0x73f6DD16d0Aa5322560556605cf4c86Bd045Ee55);
        console.log("TokenBank deployed on %s", address(token));
        saveContract("TokenBank", address(token));
    }
}
