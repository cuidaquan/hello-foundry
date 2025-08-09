// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "./BaseScript.s.sol";
import "../src/ExtendedERC20.sol";

contract ExtendedERC20Script is BaseScript {

    function run() public broadcaster {
        ExtendedERC20 token = new ExtendedERC20("ExtendedERC20", "EE", 0);
        console.log("ExtendedERC20 deployed on %s", address(token));
        saveContract("ExtendedERC20", address(token));
    }
}
