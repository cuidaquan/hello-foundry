// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

contract Bank {
    // 管理员地址
    address public admin;
    
    // 记录每个地址的存款金额
    mapping(address => uint256) public balances;
    
    // 存款金额前3名用户的结构体
    struct TopDepositor {
        address depositor;
        uint256 amount;
    }
    
    // 存款金额前3名用户数组
    TopDepositor[3] public topDepositors;
    
    // 事件
    event Deposit(address indexed depositor, uint256 amount);
    event Withdraw(address indexed admin, uint256 amount);
    event TopDepositorsUpdated();
    
    // 修饰符：只有管理员可以调用
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function");
        _;
    }
    
    // 构造函数，设置部署者为管理员
    constructor() {
        admin = msg.sender;
    }
    
    // 接收以太币的函数（当有人直接向合约地址转账时调用）
    receive() external payable {
        deposit();
    }
    
    // 回退函数
    fallback() external payable {
        deposit();
    }
    
    // 存款函数
    function deposit() public payable {
        require(msg.value > 0, "Deposit amount must be greater than 0");
        
        // 更新用户余额
        balances[msg.sender] += msg.value;
        
        // 更新前3名存款用户
        updateTopDepositors(msg.sender, balances[msg.sender]);
        
        // 触发存款事件
        emit Deposit(msg.sender, msg.value);
    }
    
    // 更新前3名存款用户的内部函数
    function updateTopDepositors(address depositor, uint256 newAmount) internal {
        // 检查是否已经在前3名中
        for (uint i = 0; i < 3; i++) {
            if (topDepositors[i].depositor == depositor) {
                topDepositors[i].amount = newAmount;
                sortTopDepositors();
                emit TopDepositorsUpdated();
                return;
            }
        }
        
        // 如果不在前3名中，检查是否应该加入
        if (newAmount > topDepositors[2].amount) {
            topDepositors[2] = TopDepositor(depositor, newAmount);
            sortTopDepositors();
            emit TopDepositorsUpdated();
        }
    }
    
    // 对前3名存款用户进行排序（降序）
    function sortTopDepositors() internal {
        for (uint i = 0; i < 2; i++) {
            for (uint j = i + 1; j < 3; j++) {
                if (topDepositors[i].amount < topDepositors[j].amount) {
                    TopDepositor memory temp = topDepositors[i];
                    topDepositors[i] = topDepositors[j];
                    topDepositors[j] = temp;
                }
            }
        }
    }
    
    // 管理员提取资金函数
    function withdraw(uint256 amount) external onlyAdmin {
        require(amount > 0, "Withdraw amount must be greater than 0");
        require(address(this).balance >= amount, "Insufficient contract balance");
        
        // 转账给管理员
        payable(admin).transfer(amount);
        
        // 触发提取事件
        emit Withdraw(admin, amount);
    }
    
    // 管理员提取所有资金
    function withdrawAll() external onlyAdmin {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        
        payable(admin).transfer(balance);
        emit Withdraw(admin, balance);
    }
    
    // 获取合约总余额
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    // 获取指定地址的存款余额
    function getBalance(address depositor) external view returns (uint256) {
        return balances[depositor];
    }
    
    // 获取前3名存款用户信息
    function getTopDepositors() external view returns (TopDepositor[3] memory) {
        return topDepositors;
    }
    
    // 更改管理员（只有当前管理员可以调用）
    function changeAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "New admin cannot be zero address");
        admin = newAdmin;
    }
}