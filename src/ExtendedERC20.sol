// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title ITokenReceiver
 * @dev 接收代币的接口
 */
interface ITokenReceiver {
    function tokensReceived(address from, uint256 amount, bytes calldata data) external returns (bool);
}

/**
 * @title ExtendedERC20
 * @dev 扩展的ERC20合约，添加了hook功能的转账函数
 */
contract ExtendedERC20 is ERC20, Ownable {
    
    /**
     * @dev 构造函数
     * @param name_ 代币名称
     * @param symbol_ 代币符号
     * @param initialSupply 初始供应量
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        _mint(msg.sender, initialSupply * 10**decimals());
    }
    
    /**
     * @dev 检查地址是否为合约地址
     * @param account 要检查的地址
     * @return 如果是合约地址返回true，否则返回false
     */
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
    
    /**
     * @dev 带回调功能的转账函数
     * @param to 接收地址
     * @param amount 转账金额
     * @param data 附加数据
     * @return 转账是否成功
     */
    // 内部实现，避免使用 this. 导致 msg.sender 变为合约地址
    function _transferWithCallback(
        address to,
        uint256 amount,
        bytes memory data
    ) internal returns (bool) {
        // 执行标准转账
        require(to != address(0), "ERC20: transfer to the zero address");
        require(balanceOf(msg.sender) >= amount, "ERC20: transfer amount exceeds balance");

        _transfer(msg.sender, to, amount);

        // 如果目标地址是合约，调用其tokensReceived方法
        if (isContract(to)) {
            try ITokenReceiver(to).tokensReceived(msg.sender, amount, data) returns (bool success) {
                require(success, "Token transfer rejected by receiver");
            } catch {
                revert("Token transfer callback failed");
            }
        }

        return true;
    }

    function transferWithCallback(
        address to,
        uint256 amount,
        bytes calldata data
    ) public returns (bool) {
        return _transferWithCallback(to, amount, data);
    }

    /**
     * @dev 重载transferWithCallback，不带data参数
     * @param to 接收地址
     * @param amount 转账金额
     * @return 转账是否成功
     */
    function transferWithCallback(
        address to,
        uint256 amount
    ) public returns (bool) {
        return _transferWithCallback(to, amount, "");
    }
    
    /**
     * @dev 铸造代币 - 只有合约拥有者可以调用
     * @param to 接收者地址
     * @param amount 铸造数量
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
    
    /**
     * @dev 销毁代币
     * @param amount 销毁数量
     */
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
    
    /**
     * @dev 从指定地址销毁代币
     * @param from 销毁地址
     * @param amount 销毁数量
     */
    function burnFrom(address from, uint256 amount) public {
        uint256 currentAllowance = allowance(from, msg.sender);
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        
        _approve(from, msg.sender, currentAllowance - amount);
        _burn(from, amount);
    }
}
