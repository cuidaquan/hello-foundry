// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "./BaseScript.s.sol";
import "../src/MyToken.sol";

contract MyTokenScript is BaseScript {

    function run() public broadcaster {
        MyToken token = new MyToken("MyToken", "MT");
        console.log("MyToken deployed on %s", address(token));
        saveContract("MyToken", address(token));
    }
}
