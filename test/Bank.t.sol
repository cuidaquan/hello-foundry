// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Bank} from "src/Bank.sol";

contract BankTest is Test {
    Bank internal bank;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");

    function setUp() public {
        // 用外部账户 admin 部署，使其成为合约管理员
        vm.prank(admin);
        bank = new Bank();

        // 为测试地址分配初始ETH
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        vm.deal(dave, 100 ether);
    }

    // 1) 断言检查存款前后余额更新
    function test_DepositUpdatesUserBalance() public {
        assertEq(bank.balances(alice), 0);

        vm.prank(alice);
        bank.deposit{value: 1 ether}();

        assertEq(bank.balances(alice), 1 ether, "Alice balance should be 1 ether after deposit");
        assertEq(address(bank).balance, 1 ether, "Contract balance should equal deposited amount");
    }

    // 2) 前3名存款用户 - 只有1个用户
    function test_TopDepositors_With1User() public {
        vm.prank(alice);
        bank.deposit{value: 5 ether}();

        Bank.TopDepositor[3] memory tds = bank.getTopDepositors();
        assertEq(tds[0].depositor, alice);
        assertEq(tds[0].amount, 5 ether);
        assertEq(tds[1].depositor, address(0));
        assertEq(tds[1].amount, 0);
        assertEq(tds[2].depositor, address(0));
        assertEq(tds[2].amount, 0);
    }

    // 2) 前3名存款用户 - 2个用户
    function test_TopDepositors_With2Users() public {
        vm.prank(alice);
        bank.deposit{value: 5 ether}();
        vm.prank(bob);
        bank.deposit{value: 3 ether}();

        Bank.TopDepositor[3] memory tds = bank.getTopDepositors();
        assertEq(tds[0].depositor, alice);
        assertEq(tds[0].amount, 5 ether);
        assertEq(tds[1].depositor, bob);
        assertEq(tds[1].amount, 3 ether);
        assertEq(tds[2].amount, 0);
    }

    // 2) 前3名存款用户 - 3个用户
    function test_TopDepositors_With3Users() public {
        vm.prank(alice);
        bank.deposit{value: 5 ether}();
        vm.prank(bob);
        bank.deposit{value: 3 ether}();
        vm.prank(carol);
        bank.deposit{value: 4 ether}();

        Bank.TopDepositor[3] memory tds = bank.getTopDepositors();
        assertEq(tds[0].depositor, alice);
        assertEq(tds[0].amount, 5 ether);
        assertEq(tds[1].depositor, carol);
        assertEq(tds[1].amount, 4 ether);
        assertEq(tds[2].depositor, bob);
        assertEq(tds[2].amount, 3 ether);
    }

    // 2) 前3名存款用户 - 4个用户（应只保留金额最高的3个）
    function test_TopDepositors_With4Users() public {
        vm.prank(alice);
        bank.deposit{value: 1 ether}(); // alice: 1
        vm.prank(bob);
        bank.deposit{value: 5 ether}(); // bob: 5
        vm.prank(carol);
        bank.deposit{value: 3 ether}(); // carol: 3
        vm.prank(dave);
        bank.deposit{value: 4 ether}(); // dave: 4

        Bank.TopDepositor[3] memory tds = bank.getTopDepositors();
        // 排序应为: bob(5), dave(4), carol(3); alice(1) 被挤出前三
        assertEq(tds[0].depositor, bob);
        assertEq(tds[0].amount, 5 ether);
        assertEq(tds[1].depositor, dave);
        assertEq(tds[1].amount, 4 ether);
        assertEq(tds[2].depositor, carol);
        assertEq(tds[2].amount, 3 ether);
    }

    // 2) 前3名存款用户 - 同一用户多次存款
    function test_TopDepositors_SameUserMultipleDeposits() public {
        vm.prank(alice);
        bank.deposit{value: 1 ether}(); // alice: 1
        vm.prank(bob);
        bank.deposit{value: 2 ether}(); // bob: 2
        vm.prank(alice);
        bank.deposit{value: 3 ether}(); // alice: 4

        Bank.TopDepositor[3] memory tds = bank.getTopDepositors();
        assertEq(tds[0].depositor, alice);
        assertEq(tds[0].amount, 4 ether);
        assertEq(tds[1].depositor, bob);
        assertEq(tds[1].amount, 2 ether);
    }

    // 3) 只有管理员可取款，其他人不可以
    function test_WithdrawOnlyByAdmin() public {
        // 先给合约里存入一些资金
        vm.prank(alice);
        bank.deposit{value: 10 ether}();

        // 非管理员尝试取款应当revert
        vm.prank(bob);
        vm.expectRevert(bytes("Only admin can call this function"));
        bank.withdraw(1 ether);
    }

    function test_AdminWithdrawSuccess() public {
        // 充入合约资金
        vm.prank(alice);
        bank.deposit{value: 10 ether}();

        uint256 adminBalBefore = admin.balance;
        uint256 bankBalBefore = address(bank).balance;

        vm.prank(admin);
        bank.withdraw(2 ether); // 由 admin 调用

        assertEq(address(bank).balance, bankBalBefore - 2 ether, "Bank balance should decrease by 2 ether");
        assertEq(admin.balance, adminBalBefore + 2 ether, "Admin should receive withdrawn funds");
    }
}

