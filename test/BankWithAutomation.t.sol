// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {BankWithAutomation} from "../src/BankWithAutomation.sol";

contract BankWithAutomationTest is Test {
    BankWithAutomation public bank;
    address public owner;
    address public user1;
    address public user2;

    uint256 public threshold = 1 ether;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        bank = new BankWithAutomation(threshold);

        // 给测试用户一些 ETH
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }

    function test_Deployment() public view {
        assertEq(bank.owner(), owner);
        assertEq(bank.threshold(), threshold);
    }

    function test_Deposit() public {
        vm.prank(user1);
        bank.deposit{value: 0.5 ether}();

        assertEq(bank.getUserDeposit(user1), 0.5 ether);
        assertEq(bank.getBalance(), 0.5 ether);
    }

    function test_DepositViaReceive() public {
        vm.prank(user1);
        (bool success,) = address(bank).call{value: 0.3 ether}("");
        require(success, "Transfer failed");

        assertEq(bank.getUserDeposit(user1), 0.3 ether);
        assertEq(bank.getBalance(), 0.3 ether);
    }

    function test_CheckUpkeepReturnsFalseWhenBelowThreshold() public {
        vm.prank(user1);
        bank.deposit{value: 0.5 ether}();

        (bool upkeepNeeded,) = bank.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function test_CheckUpkeepReturnsTrueWhenAboveThreshold() public {
        vm.prank(user1);
        bank.deposit{value: 1.5 ether}();

        (bool upkeepNeeded,) = bank.checkUpkeep("");
        assertTrue(upkeepNeeded);
    }

    function test_PerformUpkeepTransfersHalfToOwner() public {
        // 存款超过阈值
        vm.prank(user1);
        bank.deposit{value: 2 ether}();

        uint256 ownerBalanceBefore = owner.balance;
        uint256 bankBalanceBefore = bank.getBalance();

        // 执行 upkeep
        bank.performUpkeep("");

        uint256 ownerBalanceAfter = owner.balance;
        uint256 bankBalanceAfter = bank.getBalance();

        // 验证转账了一半
        assertEq(ownerBalanceAfter - ownerBalanceBefore, 1 ether);
        assertEq(bankBalanceBefore - bankBalanceAfter, 1 ether);
        assertEq(bankBalanceAfter, 1 ether);
    }

    function test_PerformUpkeepDoesNothingWhenBelowThreshold() public {
        vm.prank(user1);
        bank.deposit{value: 0.5 ether}();

        uint256 ownerBalanceBefore = owner.balance;
        uint256 bankBalanceBefore = bank.getBalance();

        bank.performUpkeep("");

        uint256 ownerBalanceAfter = owner.balance;
        uint256 bankBalanceAfter = bank.getBalance();

        // 验证没有转账
        assertEq(ownerBalanceAfter, ownerBalanceBefore);
        assertEq(bankBalanceAfter, bankBalanceBefore);
    }

    function test_SetThreshold() public {
        uint256 newThreshold = 2 ether;
        bank.setThreshold(newThreshold);
        assertEq(bank.threshold(), newThreshold);
    }

    function test_SetThresholdOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Only owner can call");
        bank.setThreshold(2 ether);
    }

    function test_MultipleDeposits() public {
        vm.prank(user1);
        bank.deposit{value: 0.5 ether}();

        vm.prank(user2);
        bank.deposit{value: 0.3 ether}();

        vm.prank(user1);
        bank.deposit{value: 0.4 ether}();

        assertEq(bank.getUserDeposit(user1), 0.9 ether);
        assertEq(bank.getUserDeposit(user2), 0.3 ether);
        assertEq(bank.getBalance(), 1.2 ether);
    }

    function test_FullWorkflow() public {
        // 1. 第一次存款，低于阈值
        vm.prank(user1);
        bank.deposit{value: 0.6 ether}();

        (bool upkeepNeeded,) = bank.checkUpkeep("");
        assertFalse(upkeepNeeded);

        // 2. 第二次存款，超过阈值
        vm.prank(user2);
        bank.deposit{value: 0.6 ether}();

        (upkeepNeeded,) = bank.checkUpkeep("");
        assertTrue(upkeepNeeded);

        // 3. 执行自动转账
        uint256 ownerBalanceBefore = owner.balance;
        bank.performUpkeep("");

        assertEq(owner.balance - ownerBalanceBefore, 0.6 ether);
        assertEq(bank.getBalance(), 0.6 ether);

        // 4. 再次检查，现在低于阈值
        (upkeepNeeded,) = bank.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    receive() external payable {}
}
