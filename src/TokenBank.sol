// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ExtendedERC20.sol";

/**
 * @title TokenBankV2
 * @dev 支持hook功能的代币银行合约V2
 */
contract TokenBank is ITokenReceiver {

    // 代币合约地址
    ExtendedERC20 public token;

    // 记录每个地址的存入数量
    mapping(address => uint256) public balances;
    
    // 事件
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);


    /**
     * @dev 构造函数
     * @param _token 扩展的ERC20代币合约地址
     */
    constructor(address _token) {
        require(_token != address(0), "Invalid token address");
        token = ExtendedERC20(_token);
    }

/**
     * @dev 存入代币 - 需要记录每个地址的存入数量
     */
    function deposit(uint256 amount) external {
        // 检查代币余额
        require(amount > 0, "Amount must be greater than 0");

        // 检查用户是否有足够的代币
        require(token.balanceOf(msg.sender) >= amount, "Insufficient token balance");

        // 授权转移代币
        require(token.approve(address(this), amount), "Approve failed");

        // 检查授权数量
        require(token.allowance(msg.sender, address(this)) >= amount, "Insufficient allowance");
        
        // 从用户转移代币到合约
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // 记录用户的存入数量
        balances[msg.sender] += amount;
        
        emit Deposit(msg.sender, amount);
    }
    
    /**
     * @dev 提取代币 - 用户可以提取自己之前存入的token
     */
    function withdraw(uint256 amount) external {
        // 检查提取金额
        require(amount > 0, "Amount must be greater than 0");

        // 检查用户是否有足够的余额
        require(balances[msg.sender] >= amount, "Insufficient balance");
        
        // 更新用户余额
        balances[msg.sender] -= amount;
        
        // 转移代币给用户
        require(token.transfer(msg.sender, amount), "Transfer failed");
        
        emit Withdraw(msg.sender, amount);
    }
    
    /**
     * @dev 获取用户存入的代币数量
     * @param user 用户地址
     * @return 用户存入的代币数量
     */
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }
    
    /**
     * @dev 获取合约持有的代币总量
     * @return 合约持有的代币总量
     */
    function getContractBalance() external view returns (uint256) {
        return token.balanceOf(address(token));
    }

    /**
     * @dev 实现tokensReceived接口，处理通过hook接收的代币
     * @param from 发送者地址
     * @param amount 代币数量
     */
    function tokensReceived(
        address from,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        // 确保调用者是我们支持的代币合约
        require(msg.sender == address(token), "Invalid token contract");
        require(amount > 0, "Amount must be greater than 0");

        // 记录用户的存入数量（累加到原有余额）
        balances[from] += amount;

        emit Deposit(from, amount);
        
        return true;
    }
}
