// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {BankV2} from "src/BankV2.sol";

contract BankV2Test is Test {
    BankV2 internal bankV2;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");
    address internal eve = makeAddr("eve");
    address internal frank = makeAddr("frank");
    address internal grace = makeAddr("grace");
    address internal henry = makeAddr("henry");
    address internal iris = makeAddr("iris");
    address internal jack = makeAddr("jack");
    address internal kate = makeAddr("kate");
    address internal leo = makeAddr("leo");

    function setUp() public {
        bankV2 = new BankV2();

        // 为测试地址分配初始ETH
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        vm.deal(dave, 100 ether);
        vm.deal(eve, 100 ether);
        vm.deal(frank, 100 ether);
        vm.deal(grace, 100 ether);
        vm.deal(henry, 100 ether);
        vm.deal(iris, 100 ether);
        vm.deal(jack, 100 ether);
        vm.deal(kate, 100 ether);
        vm.deal(leo, 100 ether);
    }

    // 测试基本存款功能
    function test_Deposit() public {
        assertEq(bankV2.getBalance(alice), 0);
        assertEq(bankV2.getTotalDeposits(), 0);

        vm.prank(alice);
        bankV2.deposit{value: 5 ether}();

        assertEq(bankV2.getBalance(alice), 5 ether, "Alice balance should be 5 ether");
        assertEq(bankV2.getTotalDeposits(), 5 ether, "Total deposits should be 5 ether");
    }

    // 测试通过receive函数直接转账
    function test_ReceiveDirectTransfer() public {
        assertEq(bankV2.getBalance(alice), 0);

        vm.prank(alice);
        (bool success,) = address(bankV2).call{value: 3 ether}("");
        require(success, "Transfer should succeed");

        assertEq(bankV2.getBalance(alice), 3 ether, "Alice balance should be 3 ether");
        assertEq(bankV2.getTotalDeposits(), 3 ether, "Total deposits should be 3 ether");
    }

    // 测试多次存款
    function test_MultipleDeposits() public {
        vm.prank(alice);
        bankV2.deposit{value: 2 ether}();

        vm.prank(alice);
        bankV2.deposit{value: 3 ether}();

        assertEq(bankV2.getBalance(alice), 5 ether, "Alice total balance should be 5 ether");
    }

    // 测试排行榜基本功能 - 单个用户
    function test_LeaderboardSingleUser() public {
        vm.prank(alice);
        bankV2.deposit{value: 5 ether}();

        (address[] memory users, uint256[] memory amounts) = bankV2.getLeaderboard();
        
        assertEq(users.length, 1, "Should have 1 user in leaderboard");
        assertEq(users[0], alice, "Alice should be first");
        assertEq(amounts[0], 5 ether, "Amount should be 5 ether");
        
        (uint256 rank, bool inLeaderboard) = bankV2.getUserRank(alice);
        assertTrue(inLeaderboard, "Alice should be in leaderboard");
        assertEq(rank, 1, "Alice should be rank 1");
    }

    // 测试排行榜功能 - 多个用户
    function test_LeaderboardMultipleUsers() public {
        vm.prank(alice);
        bankV2.deposit{value: 5 ether}();
        vm.prank(bob);
        bankV2.deposit{value: 3 ether}();
        vm.prank(carol);
        bankV2.deposit{value: 7 ether}();

        (address[] memory users, uint256[] memory amounts) = bankV2.getLeaderboard();
        
        assertEq(users.length, 3, "Should have 3 users");
        assertEq(users[0], carol, "Carol should be first with 7 ether");
        assertEq(amounts[0], 7 ether);
        assertEq(users[1], alice, "Alice should be second with 5 ether");
        assertEq(amounts[1], 5 ether);
        assertEq(users[2], bob, "Bob should be third with 3 ether");
        assertEq(amounts[2], 3 ether);

        (uint256 rank, bool inLeaderboard) = bankV2.getUserRank(carol);
        assertTrue(inLeaderboard);
        assertEq(rank, 1, "Carol should be rank 1");
    }

    // 测试排行榜最大10个用户限制
    function test_LeaderboardMaxSize() public {
        // 添加12个用户，但排行榜应只保留前10名
        address[] memory users = new address[](12);
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;
        users[3] = dave;
        users[4] = eve;
        users[5] = frank;
        users[6] = grace;
        users[7] = henry;
        users[8] = iris;
        users[9] = jack;
        users[10] = kate;
        users[11] = leo;

        // 按不同金额存款
        for (uint256 i = 0; i < 12; i++) {
            vm.prank(users[i]);
            bankV2.deposit{value: (i + 1) * 1 ether}();
        }

        assertEq(bankV2.getLeaderboardSize(), 10, "Leaderboard should have exactly 10 users");
        
        (address[] memory topUsers, uint256[] memory topAmounts) = bankV2.getLeaderboard();
        
        assertEq(topUsers.length, 10, "Should return 10 users");
        
        // 验证排序（最高的应该是leo: 12 ether）
        assertEq(topUsers[0], leo, "Leo should be first with 12 ether");
        assertEq(topAmounts[0], 12 ether);
        
        // 验证最低的应该是第3名用户（carol: 3 ether）
        assertEq(topUsers[9], carol, "Carol should be last in top 10 with 3 ether");
        assertEq(topAmounts[9], 3 ether);

        // 验证alice和bob不在排行榜中（金额太低）
        (,bool aliceInBoard) = bankV2.getUserRank(alice);
        (,bool bobInBoard) = bankV2.getUserRank(bob);
        assertFalse(aliceInBoard, "Alice should not be in leaderboard");
        assertFalse(bobInBoard, "Bob should not be in leaderboard");
    }

    // 测试用户多次存款后排名更新
    function test_LeaderboardUpdateAfterMultipleDeposits() public {
        vm.prank(alice);
        bankV2.deposit{value: 1 ether}();
        vm.prank(bob);
        bankV2.deposit{value: 2 ether}();
        vm.prank(carol);
        bankV2.deposit{value: 3 ether}();

        // 初始排序: carol(3), bob(2), alice(1)
        (address[] memory users,) = bankV2.getLeaderboard();
        assertEq(users[0], carol);
        assertEq(users[1], bob);
        assertEq(users[2], alice);

        // Alice再存款，总计变为5 ether
        vm.prank(alice);
        bankV2.deposit{value: 4 ether}();

        // 新排序应为: alice(5), carol(3), bob(2)
        (users,) = bankV2.getLeaderboard();
        assertEq(users[0], alice, "Alice should now be first");
        assertEq(users[1], carol, "Carol should be second");
        assertEq(users[2], bob, "Bob should be third");
    }

    // 测试零值存款应该失败
    function test_DepositZeroValueFails() public {
        vm.prank(alice);
        vm.expectRevert("Deposit must be greater than 0");
        bankV2.deposit{value: 0}();
    }

    // 测试事件发出
    function test_DepositEvent() public {
        vm.expectEmit(true, false, false, true);
        emit BankV2.Deposit(alice, 5 ether, 5 ether);
        
        vm.prank(alice);
        bankV2.deposit{value: 5 ether}();
    }

    // 测试排行榜更新事件
    function test_LeaderboardUpdateEvent() public {
        vm.expectEmit(true, false, false, true);
        emit BankV2.LeaderboardUpdated(alice, 5 ether, 1);
        
        vm.prank(alice);
        bankV2.deposit{value: 5 ether}();
    }

    // Fuzz测试：随机金额存款
    function testFuzz_Deposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        
        vm.deal(alice, amount);
        vm.prank(alice);
        bankV2.deposit{value: amount}();

        assertEq(bankV2.getBalance(alice), amount);
        assertEq(bankV2.getTotalDeposits(), amount);
    }
}