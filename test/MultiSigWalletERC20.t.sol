// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @dev 用于测试的模拟ERC20代币
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, 1000000 * 10**decimals_);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

/**
 * @title MultiSigWallet ERC20测试合约
 * @dev 测试多签钱包的ERC20代币操作功能
 */
contract MultiSigWalletERC20Test is Test {
    MultiSigWallet public wallet;
    MockERC20 public token;
    
    address public owner1 = address(0x1);
    address public owner2 = address(0x2);
    address public owner3 = address(0x3);
    address public recipient = address(0x456);
    
    address[] public owners;
    uint256 public constant REQUIRED = 2;

    function setUp() public {
        owners.push(owner1);
        owners.push(owner2);
        owners.push(owner3);
        
        wallet = new MultiSigWallet(owners, REQUIRED);
        token = new MockERC20("Test Token", "TEST", 18);
        
        // 给钱包转入一些代币
        token.mint(address(wallet), 1000 * 10**18);
        
        // 给测试账户一些ETH
        vm.deal(owner1, 10 ether);
        vm.deal(owner2, 10 ether);
        vm.deal(owner3, 10 ether);
    }

    // ============ ERC20转账测试 ============
    
    function testERC20Transfer() public {
        uint256 transferAmount = 100 * 10**18;
        uint256 walletBalanceBefore = token.balanceOf(address(wallet));
        uint256 recipientBalanceBefore = token.balanceOf(recipient);
        
        // 编码ERC20转账调用
        bytes memory data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            recipient,
            transferAmount
        );
        
        // 1. 提交交易
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(token), 0, data);
        
        // 2. 确认交易
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        // 3. 执行交易
        vm.prank(owner3);
        wallet.executeTransaction(txId);
        
        // 4. 验证结果
        assertEq(token.balanceOf(address(wallet)), walletBalanceBefore - transferAmount);
        assertEq(token.balanceOf(recipient), recipientBalanceBefore + transferAmount);
        
        // 验证交易状态
        (, , , MultiSigWallet.TransactionStatus status, ,) = wallet.getTransaction(txId);
        assertEq(uint256(status), uint256(MultiSigWallet.TransactionStatus.Executed));
    }

    function testERC20TransferInsufficientBalance() public {
        uint256 transferAmount = 2000 * 10**18; // 超过钱包余额
        
        bytes memory data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            recipient,
            transferAmount
        );
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(token), 0, data);
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        vm.prank(owner3);
        wallet.executeTransaction(txId);
        
        // 交易应该失败
        (, , , MultiSigWallet.TransactionStatus status, ,) = wallet.getTransaction(txId);
        assertEq(uint256(status), uint256(MultiSigWallet.TransactionStatus.Failed));
    }

    // ============ ERC20授权测试 ============
    
    function testERC20Approve() public {
        uint256 approveAmount = 500 * 10**18;
        address spender = address(0x789);
        
        // 编码ERC20授权调用
        bytes memory data = abi.encodeWithSignature(
            "approve(address,uint256)",
            spender,
            approveAmount
        );
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(token), 0, data);
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        vm.prank(owner3);
        wallet.executeTransaction(txId);
        
        // 验证授权
        assertEq(token.allowance(address(wallet), spender), approveAmount);
        
        (, , , MultiSigWallet.TransactionStatus status, ,) = wallet.getTransaction(txId);
        assertEq(uint256(status), uint256(MultiSigWallet.TransactionStatus.Executed));
    }

    // ============ 批量ERC20操作测试 ============
    
    function testMultipleERC20Transfers() public {
        address recipient1 = address(0x111);
        address recipient2 = address(0x222);
        uint256 amount1 = 50 * 10**18;
        uint256 amount2 = 75 * 10**18;
        
        // 第一笔转账
        bytes memory data1 = abi.encodeWithSignature(
            "transfer(address,uint256)",
            recipient1,
            amount1
        );
        
        vm.prank(owner1);
        uint256 txId1 = wallet.submitTransaction(address(token), 0, data1);
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId1);
        
        // 第二笔转账
        bytes memory data2 = abi.encodeWithSignature(
            "transfer(address,uint256)",
            recipient2,
            amount2
        );
        
        vm.prank(owner1);
        uint256 txId2 = wallet.submitTransaction(address(token), 0, data2);
        
        vm.prank(owner3);
        wallet.confirmTransaction(txId2);
        
        // 执行两笔交易
        vm.prank(owner1);
        wallet.executeTransaction(txId1);
        
        vm.prank(owner2);
        wallet.executeTransaction(txId2);
        
        // 验证结果
        assertEq(token.balanceOf(recipient1), amount1);
        assertEq(token.balanceOf(recipient2), amount2);
        
        // 验证交易状态
        (, , , MultiSigWallet.TransactionStatus status1, ,) = wallet.getTransaction(txId1);
        (, , , MultiSigWallet.TransactionStatus status2, ,) = wallet.getTransaction(txId2);
        assertEq(uint256(status1), uint256(MultiSigWallet.TransactionStatus.Executed));
        assertEq(uint256(status2), uint256(MultiSigWallet.TransactionStatus.Executed));
    }

    // ============ 混合操作测试 ============
    
    function testMixedETHAndERC20Operations() public {
        uint256 ethAmount = 1 ether;
        uint256 tokenAmount = 100 * 10**18;
        
        // 给钱包一些ETH
        vm.deal(address(wallet), 5 ether);
        
        // 1. ETH转账
        vm.prank(owner1);
        uint256 ethTxId = wallet.submitTransaction(recipient, ethAmount, "");
        
        vm.prank(owner2);
        wallet.confirmTransaction(ethTxId);
        
        // 2. ERC20转账
        bytes memory tokenData = abi.encodeWithSignature(
            "transfer(address,uint256)",
            recipient,
            tokenAmount
        );
        
        vm.prank(owner1);
        uint256 tokenTxId = wallet.submitTransaction(address(token), 0, tokenData);
        
        vm.prank(owner3);
        wallet.confirmTransaction(tokenTxId);
        
        // 记录执行前余额
        uint256 recipientETHBefore = recipient.balance;
        uint256 recipientTokenBefore = token.balanceOf(recipient);
        
        // 3. 执行两笔交易
        vm.prank(owner1);
        wallet.executeTransaction(ethTxId);
        
        vm.prank(owner2);
        wallet.executeTransaction(tokenTxId);
        
        // 4. 验证结果
        assertEq(recipient.balance, recipientETHBefore + ethAmount);
        assertEq(token.balanceOf(recipient), recipientTokenBefore + tokenAmount);
        
        // 验证交易状态
        (, , , MultiSigWallet.TransactionStatus ethStatus, ,) = wallet.getTransaction(ethTxId);
        (, , , MultiSigWallet.TransactionStatus tokenStatus, ,) = wallet.getTransaction(tokenTxId);
        assertEq(uint256(ethStatus), uint256(MultiSigWallet.TransactionStatus.Executed));
        assertEq(uint256(tokenStatus), uint256(MultiSigWallet.TransactionStatus.Executed));
    }

    // ============ 错误处理测试 ============
    
    function testERC20TransferToInvalidAddress() public {
        // 尝试转账到零地址（某些ERC20实现会拒绝）
        bytes memory data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            address(0),
            100 * 10**18
        );
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(token), 0, data);
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        vm.prank(owner3);
        wallet.executeTransaction(txId);
        
        // 根据ERC20实现，这可能成功或失败
        // 这里主要测试钱包能正确处理各种情况
        (, , , MultiSigWallet.TransactionStatus status, ,) = wallet.getTransaction(txId);
        assertTrue(
            uint256(status) == uint256(MultiSigWallet.TransactionStatus.Executed) ||
            uint256(status) == uint256(MultiSigWallet.TransactionStatus.Failed)
        );
    }

    function testInvalidERC20Call() public {
        // 调用不存在的函数
        bytes memory invalidData = abi.encodeWithSignature(
            "nonExistentFunction(uint256)",
            123
        );
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(token), 0, invalidData);
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        vm.prank(owner3);
        wallet.executeTransaction(txId);
        
        // 交易应该失败
        (, , , MultiSigWallet.TransactionStatus status, ,) = wallet.getTransaction(txId);
        assertEq(uint256(status), uint256(MultiSigWallet.TransactionStatus.Failed));
    }

    // ============ Gas 消耗测试 ============
    
    function testGasConsumption() public {
        bytes memory data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            recipient,
            100 * 10**18
        );
        
        // 测试提交交易的Gas消耗
        uint256 gasBefore = gasleft();
        vm.prank(owner1);
        wallet.submitTransaction(address(token), 0, data);
        uint256 gasAfter = gasleft();
        
        uint256 submitGasUsed = gasBefore - gasAfter;
        console.log("Submit ERC20 transaction gas used:", submitGasUsed);
        
        // Gas消耗应该在合理范围内
        assertLt(submitGasUsed, 250000);
    }
}
