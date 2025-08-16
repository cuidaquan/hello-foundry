// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TokenBankWithPermit
 * @dev 支持 EIP2612 permit 功能的代币银行合约
 */
contract TokenBankWithPermit is ReentrancyGuard {

    // 代币合约地址
    IERC20 public token;
    IERC20Permit public permitToken;

    // 记录每个地址的存入数量
    mapping(address => uint256) public balances;
    
    // 事件
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event PermitDeposit(address indexed user, uint256 amount);

    /**
     * @dev 构造函数
     * @param _token 支持 EIP2612 的 ERC20 代币合约地址
     */
    constructor(address _token) {
        require(_token != address(0), "Invalid token address");
        token = IERC20(_token);
        permitToken = IERC20Permit(_token);
    }

    /**
     * @dev 传统存入代币方式 - 需要预先调用 approve
     * @param amount 存入数量
     */
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(token.balanceOf(msg.sender) >= amount, "Insufficient token balance");
        require(token.allowance(msg.sender, address(this)) >= amount, "Insufficient allowance");
        
        // 从用户转移代币到合约
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // 记录用户的存入数量
        balances[msg.sender] += amount;
        
        emit Deposit(msg.sender, amount);
    }
    
    /**
     * @dev 使用 permit 签名进行存款 - 无需预先调用 approve
     * @param amount 存入数量
     * @param deadline permit 签名的截止时间
     * @param v 签名的 v 参数
     * @param r 签名的 r 参数
     * @param s 签名的 s 参数
     */
    function permitDeposit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(token.balanceOf(msg.sender) >= amount, "Insufficient token balance");
        
        // 使用 permit 进行授权
        permitToken.permit(msg.sender, address(this), amount, deadline, v, r, s);
        
        // 从用户转移代币到合约
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // 记录用户的存入数量
        balances[msg.sender] += amount;
        
        emit PermitDeposit(msg.sender, amount);
    }
    
    /**
     * @dev 提取代币 - 用户可以提取自己之前存入的token
     * @param amount 提取数量
     */
    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
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
        return token.balanceOf(address(this));
    }
}
