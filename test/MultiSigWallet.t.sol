// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";

/**
 * @title MultiSigWallet测试合约
 * @dev 全面测试多签钱包的所有功能
 */
contract MultiSigWalletTest is Test {
    MultiSigWallet public wallet;
    
    address public owner1 = address(0x1);
    address public owner2 = address(0x2);
    address public owner3 = address(0x3);
    address public nonOwner = address(0x999);
    
    address[] public owners;
    uint256 public constant REQUIRED = 2;

    event Deposit(address indexed sender, uint256 value, uint256 balance);
    event TransactionSubmitted(uint256 indexed txId, address indexed submitter, address indexed to, uint256 value, bytes data);
    event TransactionConfirmed(uint256 indexed txId, address indexed confirmer, uint256 confirmations);
    event TransactionExecuted(uint256 indexed txId, address indexed executor, bool success, bytes returnData);

    function setUp() public {
        owners.push(owner1);
        owners.push(owner2);
        owners.push(owner3);
        
        wallet = new MultiSigWallet(owners, REQUIRED);
        
        // 给测试账户一些ETH
        vm.deal(owner1, 10 ether);
        vm.deal(owner2, 10 ether);
        vm.deal(owner3, 10 ether);
        vm.deal(address(wallet), 5 ether);
    }

    // ============ 构造函数测试 ============
    
    function testConstructorSuccess() public {
        assertEq(wallet.required(), REQUIRED);
        assertEq(wallet.getOwners().length, 3);
        assertTrue(wallet.isOwner(owner1));
        assertTrue(wallet.isOwner(owner2));
        assertTrue(wallet.isOwner(owner3));
        assertFalse(wallet.isOwner(nonOwner));
    }

    function testConstructorInvalidOwners() public {
        address[] memory emptyOwners = new address[](0);
        
        vm.expectRevert("Owners required");
        new MultiSigWallet(emptyOwners, 1);
    }

    function testConstructorInvalidRequired() public {
        vm.expectRevert("Invalid required number");
        new MultiSigWallet(owners, 0);
        
        vm.expectRevert("Invalid required number");
        new MultiSigWallet(owners, 4);
    }

    function testConstructorDuplicateOwner() public {
        address[] memory duplicateOwners = new address[](2);
        duplicateOwners[0] = owner1;
        duplicateOwners[1] = owner1;
        
        vm.expectRevert("Owner not unique");
        new MultiSigWallet(duplicateOwners, 1);
    }

    function testConstructorZeroAddress() public {
        address[] memory invalidOwners = new address[](2);
        invalidOwners[0] = owner1;
        invalidOwners[1] = address(0);
        
        vm.expectRevert("Invalid owner");
        new MultiSigWallet(invalidOwners, 1);
    }

    // ============ 接收ETH测试 ============
    
    function testReceiveETH() public {
        uint256 amount = 1 ether;
        uint256 balanceBefore = address(wallet).balance;
        
        vm.expectEmit(true, false, false, true);
        emit Deposit(owner1, amount, balanceBefore + amount);
        
        vm.prank(owner1);
        (bool success,) = address(wallet).call{value: amount}("");
        assertTrue(success);
        
        assertEq(address(wallet).balance, balanceBefore + amount);
        assertEq(wallet.getBalance(), balanceBefore + amount);
    }

    function testFallbackWithETH() public {
        uint256 amount = 1 ether;
        uint256 balanceBefore = address(wallet).balance;
        
        vm.expectEmit(true, false, false, true);
        emit Deposit(owner1, amount, balanceBefore + amount);
        
        vm.prank(owner1);
        (bool success,) = address(wallet).call{value: amount}("0x1234");
        assertTrue(success);
        
        assertEq(address(wallet).balance, balanceBefore + amount);
    }

    // ============ 交易提交测试 ============
    
    function testSubmitTransaction() public {
        address to = address(0x123);
        uint256 value = 1 ether;
        bytes memory data = "";
        
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmitted(0, owner1, to, value, data);
        
        vm.expectEmit(true, true, false, true);
        emit TransactionConfirmed(0, owner1, 1);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(to, value, data);
        
        assertEq(txId, 0);
        assertEq(wallet.getTransactionCount(), 1);
        
        (address txTo, uint256 txValue, bytes memory txData, MultiSigWallet.TransactionStatus status, uint256 confirmations, uint256 timestamp) = wallet.getTransaction(txId);
        
        assertEq(txTo, to);
        assertEq(txValue, value);
        assertEq(txData, data);
        assertEq(uint256(status), uint256(MultiSigWallet.TransactionStatus.Pending));
        assertEq(confirmations, 1);
        assertGt(timestamp, 0);
    }

    function testSubmitTransactionNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Not an owner");
        wallet.submitTransaction(address(0x123), 1 ether, "");
    }

    // ============ 交易确认测试 ============
    
    function testConfirmTransaction() public {
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(0x123), 1 ether, "");
        
        vm.expectEmit(true, true, false, true);
        emit TransactionConfirmed(txId, owner2, 2);
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        assertTrue(wallet.isConfirmed(txId, owner2));
        
        (, , , MultiSigWallet.TransactionStatus status, uint256 confirmations,) = wallet.getTransaction(txId);
        assertEq(confirmations, 2);
        assertEq(uint256(status), uint256(MultiSigWallet.TransactionStatus.Ready));
    }

    function testConfirmTransactionTwice() public {
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(0x123), 1 ether, "");
        
        vm.prank(owner1);
        vm.expectRevert("Transaction already confirmed");
        wallet.confirmTransaction(txId);
    }

    function testConfirmTransactionNotOwner() public {
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(0x123), 1 ether, "");
        
        vm.prank(nonOwner);
        vm.expectRevert("Not an owner");
        wallet.confirmTransaction(txId);
    }

    // ============ 交易执行测试 ============
    
    function testExecuteTransaction() public {
        address to = address(0x123);
        uint256 value = 1 ether;
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(to, value, "");
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        uint256 balanceBefore = to.balance;
        uint256 walletBalanceBefore = address(wallet).balance;
        
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txId, owner3, true, "");
        
        vm.prank(owner3);
        wallet.executeTransaction(txId);
        
        assertEq(to.balance, balanceBefore + value);
        assertEq(address(wallet).balance, walletBalanceBefore - value);
        
        (, , , MultiSigWallet.TransactionStatus status, ,) = wallet.getTransaction(txId);
        assertEq(uint256(status), uint256(MultiSigWallet.TransactionStatus.Executed));
    }

    function testExecuteTransactionNotEnoughConfirmations() public {
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(0x123), 1 ether, "");
        
        vm.prank(owner1);
        vm.expectRevert("Not enough confirmations");
        wallet.executeTransaction(txId);
    }

    function testExecuteTransactionInsufficientBalance() public {
        // 创建一个余额不足的钱包
        MultiSigWallet poorWallet = new MultiSigWallet(owners, REQUIRED);
        
        vm.prank(owner1);
        uint256 txId = poorWallet.submitTransaction(address(0x123), 1 ether, "");
        
        vm.prank(owner2);
        poorWallet.confirmTransaction(txId);
        
        vm.prank(owner3);
        poorWallet.executeTransaction(txId);
        
        // 检查交易状态为Failed
        (, , , MultiSigWallet.TransactionStatus status, ,) = poorWallet.getTransaction(txId);
        assertEq(uint256(status), uint256(MultiSigWallet.TransactionStatus.Failed));
    }

    // ============ 撤销确认测试 ============
    
    function testRevokeConfirmation() public {
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(0x123), 1 ether, "");
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        // 状态应该是Ready
        (, , , MultiSigWallet.TransactionStatus status, uint256 confirmations,) = wallet.getTransaction(txId);
        assertEq(uint256(status), uint256(MultiSigWallet.TransactionStatus.Ready));
        assertEq(confirmations, 2);
        
        vm.prank(owner2);
        wallet.revokeConfirmation(txId);
        
        assertFalse(wallet.isConfirmed(txId, owner2));
        
        // 状态应该变回Pending
        (, , , status, confirmations,) = wallet.getTransaction(txId);
        assertEq(uint256(status), uint256(MultiSigWallet.TransactionStatus.Pending));
        assertEq(confirmations, 1);
    }

    function testRevokeConfirmationNotConfirmed() public {
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(0x123), 1 ether, "");
        
        vm.prank(owner2);
        vm.expectRevert("Transaction not confirmed");
        wallet.revokeConfirmation(txId);
    }

    // ============ 查询函数测试 ============
    
    function testGetConfirmations() public {
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(0x123), 1 ether, "");
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        address[] memory confirmers = wallet.getConfirmations(txId);
        assertEq(confirmers.length, 2);
        assertEq(confirmers[0], owner1);
        assertEq(confirmers[1], owner2);
    }

    function testGetTransactionNonExistent() public {
        vm.expectRevert("Transaction does not exist");
        wallet.getTransaction(999);
    }

    // ============ 完整流程测试 ============
    
    function testCompleteMultiSigFlow() public {
        address recipient = address(0x456);
        uint256 amount = 2 ether;
        
        // 1. 提交交易
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, amount, "");
        
        // 2. 其他持有人确认
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        vm.prank(owner3);
        wallet.confirmTransaction(txId);
        
        // 3. 执行交易
        uint256 recipientBalanceBefore = recipient.balance;
        
        vm.prank(owner1);
        wallet.executeTransaction(txId);
        
        // 4. 验证结果
        assertEq(recipient.balance, recipientBalanceBefore + amount);
        
        (, , , MultiSigWallet.TransactionStatus status, ,) = wallet.getTransaction(txId);
        assertEq(uint256(status), uint256(MultiSigWallet.TransactionStatus.Executed));
    }
}
