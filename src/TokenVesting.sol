// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TokenVesting
 * @dev 线性解锁（Vesting）合约
 *
 * 功能说明：
 * - 12个月的cliff期（锁定期）
 * - 从第13个月开始，在接下来的24个月内线性释放代币
 * - 每月释放 1/24 的总锁定代币
 */
contract TokenVesting is Ownable {
    using SafeERC20 for IERC20;

    // 受益人地址
    address public immutable beneficiary;

    // 锁定的ERC20代币地址
    IERC20 public immutable token;

    // 开始时间（部署时间）
    uint256 public immutable startTime;

    // Cliff期（12个月 = 360天）
    uint256 public constant CLIFF_DURATION = 360 days;

    // 总释放期（24个月 = 720天）
    uint256 public constant VESTING_DURATION = 720 days;

    // 总锁定代币数量
    uint256 public immutable totalTokens;

    // 已释放的代币数量
    uint256 public releasedTokens;

    event TokensReleased(address indexed beneficiary, uint256 amount);

    /**
     * @dev 构造函数
     * @param _beneficiary 受益人地址
     * @param _token 锁定的ERC20代币地址
     * @param _totalTokens 总锁定代币数量
     */
    constructor(
        address _beneficiary,
        address _token,
        uint256 _totalTokens
    ) Ownable(msg.sender) {
        require(_beneficiary != address(0), "Beneficiary is zero address");
        require(_token != address(0), "Token is zero address");
        require(_totalTokens > 0, "Total tokens must be greater than 0");

        beneficiary = _beneficiary;
        token = IERC20(_token);
        totalTokens = _totalTokens;
        startTime = block.timestamp;
    }

    /**
     * @dev 释放当前可解锁的代币给受益人
     */
    function release() public {
        uint256 unreleased = _releasableAmount();
        require(unreleased > 0, "No tokens available for release");

        releasedTokens += unreleased;
        token.safeTransfer(beneficiary, unreleased);

        emit TokensReleased(beneficiary, unreleased);
    }

    /**
     * @dev 计算当前可释放的代币数量
     * @return 可释放的代币数量
     */
    function _releasableAmount() private view returns (uint256) {
        return _vestedAmount() - releasedTokens;
    }

    /**
     * @dev 计算截至当前时间应该解锁的总代币数量
     * @return 应该解锁的总代币数量
     */
    function _vestedAmount() private view returns (uint256) {
        uint256 currentTime = block.timestamp;

        // 如果还在cliff期内，返回0
        if (currentTime < startTime + CLIFF_DURATION) {
            return 0;
        }

        // 如果已经超过cliff + vesting期，全部解锁
        if (currentTime >= startTime + CLIFF_DURATION + VESTING_DURATION) {
            return totalTokens;
        }

        // 计算从cliff结束后经过的时间
        uint256 timeAfterCliff = currentTime - (startTime + CLIFF_DURATION);

        // 线性计算解锁数量：总代币数 * 已过时间 / 释放总时长
        return (totalTokens * timeAfterCliff) / VESTING_DURATION;
    }

    /**
     * @dev 查看当前可释放的代币数量（外部查询函数）
     * @return 可释放的代币数量
     */
    function releasableAmount() external view returns (uint256) {
        return _releasableAmount();
    }

    /**
     * @dev 查看截至当前时间应该解锁的总代币数量（外部查询函数）
     * @return 应该解锁的总代币数量
     */
    function vestedAmount() external view returns (uint256) {
        return _vestedAmount();
    }

    /**
     * @dev 获取合约剩余的代币余额
     * @return 合约持有的代币数量
     */
    function getBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }
}
