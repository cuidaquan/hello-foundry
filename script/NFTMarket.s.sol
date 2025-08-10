// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "./BaseScript.s.sol";
import "../src/NFTMarket.sol";

contract NFTMarketScript is BaseScript {

    function run() public broadcaster {
        NFTMarket market = new NFTMarket(0x89865AAF2251b10ffc80CE4A809522506BF10bA2, 0x08DcAA6dE0Ca584b8C5d810B027afE23D31C4AF1);
        console.log("NFTMarket deployed on %s", address(market));
        saveContract("NFTMarket", address(market));
    }
}
