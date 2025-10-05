// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 10000000 * 10 ** decimals()); // Mint 10 million tokens
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
