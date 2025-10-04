// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

/**
 * @title BankWithAutomation
 * @dev Bank contract with ChainLink Automation integration
 * Automatically transfers half of the balance to owner when total deposits exceed threshold
 */
contract BankWithAutomation is AutomationCompatibleInterface {
    address public owner;
    uint256 public threshold; // 触发自动转账的阈值

    // 记录每个用户的存款
    mapping(address => uint256) public deposits;

    // 事件
    event Deposited(address indexed user, uint256 amount);
    event AutoTransfer(address indexed to, uint256 amount);
    event ThresholdUpdated(uint256 newThreshold);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call");
        _;
    }

    constructor(uint256 _threshold) {
        owner = msg.sender;
        threshold = _threshold;
    }

    /**
     * @dev 存款函数
     */
    function deposit() external payable {
        require(msg.value > 0, "Must deposit something");
        deposits[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @dev 接收 ETH
     */
    receive() external payable {
        deposits[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @dev ChainLink Automation 检查函数
     * 当合约余额超过阈值时返回 true
     */
    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        upkeepNeeded = address(this).balance >= threshold;
    }

    /**
     * @dev ChainLink Automation 执行函数
     * 将一半的余额转给 owner
     */
    function performUpkeep(bytes calldata /* performData */) external override {
        // 再次检查条件，防止重入攻击
        if (address(this).balance >= threshold) {
            uint256 transferAmount = address(this).balance / 2;
            (bool success, ) = payable(owner).call{value: transferAmount}("");
            require(success, "Transfer failed");
            emit AutoTransfer(owner, transferAmount);
        }
    }

    /**
     * @dev 更新阈值
     */
    function setThreshold(uint256 _newThreshold) external onlyOwner {
        threshold = _newThreshold;
        emit ThresholdUpdated(_newThreshold);
    }

    /**
     * @dev 获取合约余额
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev 获取用户存款
     */
    function getUserDeposit(address user) external view returns (uint256) {
        return deposits[user];
    }
}
