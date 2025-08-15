// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts/contracts/utils/Context.sol";

/**
 * @title MultiSigWallet
 * @dev 多签钱包合约，支持多个持有人共同管理资金
 * @author Augment Agent
 */
contract MultiSigWallet is Context, ReentrancyGuard {
    using Address for address;
    using Address for address payable;

    // 交易状态枚举
    enum TransactionStatus {
        Pending,    // 0: 待确认（确认数 < required）
        Ready,      // 1: 可执行（确认数 >= required，但未执行）
        Executed,   // 2: 已成功执行
        Failed      // 3: 执行失败
    }

    // 交易结构体
    struct Transaction {
        address to;                    // 目标地址
        uint256 value;                 // ETH 数量
        bytes data;                    // 调用数据
        TransactionStatus status;      // 交易状态
        uint256 timestamp;             // 提交时间
    }

    // 状态变量
    address[] public owners;                                        // 多签持有人数组
    uint256 public required;                                        // 所需确认数量
    mapping(address => bool) public isOwner;                        // 持有人映射
    Transaction[] public transactions;                              // 交易数组
    mapping(uint256 => mapping(address => bool)) public confirmations; // 交易确认映射
    mapping(uint256 => uint256) public confirmationCount;          // 交易确认计数

    // 事件
    event Deposit(address indexed sender, uint256 value, uint256 balance);
    
    event TransactionSubmitted(
        uint256 indexed txId,
        address indexed submitter,
        address indexed to,
        uint256 value,
        bytes data
    );
    
    event TransactionConfirmed(
        uint256 indexed txId,
        address indexed confirmer,
        uint256 confirmations
    );
    
    event TransactionRevoked(
        uint256 indexed txId,
        address indexed revoker,
        uint256 confirmations
    );
    
    event TransactionExecuted(
        uint256 indexed txId,
        address indexed executor,
        bool success,
        bytes returnData
    );

    // 修饰器
    modifier onlyOwner() {
        require(isOwner[_msgSender()], "Not an owner");
        _;
    }

    modifier txExists(uint256 txId) {
        require(txId < transactions.length, "Transaction does not exist");
        _;
    }

    modifier notExecuted(uint256 txId) {
        require(transactions[txId].status != TransactionStatus.Executed, "Transaction already executed");
        require(transactions[txId].status != TransactionStatus.Failed, "Transaction failed");
        _;
    }

    modifier notConfirmed(uint256 txId) {
        require(!confirmations[txId][_msgSender()], "Transaction already confirmed");
        _;
    }

    modifier confirmed(uint256 txId) {
        require(confirmations[txId][_msgSender()], "Transaction not confirmed");
        _;
    }

    /**
     * @dev 构造函数
     * @param _owners 多签持有人地址数组
     * @param _required 所需的签名数量
     */
    constructor(address[] memory _owners, uint256 _required) {
        require(_owners.length > 0, "Owners required");
        require(_required > 0 && _required <= _owners.length, "Invalid required number");
        
        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Invalid owner");
            require(!isOwner[owner], "Owner not unique");
            
            isOwner[owner] = true;
            owners.push(owner);
        }
        
        required = _required;
    }

    /**
     * @dev 接收ETH转账
     */
    receive() external payable {
        if (msg.value > 0) {
            emit Deposit(_msgSender(), msg.value, address(this).balance);
        }
    }

    /**
     * @dev 处理带数据的调用
     */
    fallback() external payable {
        if (msg.value > 0) {
            emit Deposit(_msgSender(), msg.value, address(this).balance);
        }
    }

    /**
     * @dev 获取ETH余额
     * @return 当前合约的ETH余额
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev 获取持有人列表
     * @return 所有持有人地址数组
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    /**
     * @dev 获取交易总数
     * @return 交易总数
     */
    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    /**
     * @dev 提交交易提案
     * @param to 目标地址
     * @param value ETH数量
     * @param data 调用数据
     * @return txId 交易ID
     */
    function submitTransaction(address to, uint256 value, bytes memory data)
        external
        onlyOwner
        returns (uint256 txId)
    {
        txId = transactions.length;
        transactions.push(Transaction({
            to: to,
            value: value,
            data: data,
            status: TransactionStatus.Pending,
            timestamp: block.timestamp
        }));
        
        emit TransactionSubmitted(txId, _msgSender(), to, value, data);
        
        // 自动确认
        confirmTransaction(txId);
    }

    /**
     * @dev 确认交易
     * @param txId 交易ID
     */
    function confirmTransaction(uint256 txId)
        public
        onlyOwner
        txExists(txId)
        notExecuted(txId)
        notConfirmed(txId)
    {
        confirmations[txId][_msgSender()] = true;
        confirmationCount[txId]++;
        
        // 更新交易状态
        if (confirmationCount[txId] >= required) {
            transactions[txId].status = TransactionStatus.Ready;
        }
        
        emit TransactionConfirmed(txId, _msgSender(), confirmationCount[txId]);
    }

    /**
     * @dev 撤销确认
     * @param txId 交易ID
     */
    function revokeConfirmation(uint256 txId)
        external
        onlyOwner
        txExists(txId)
        notExecuted(txId)
        confirmed(txId)
    {
        confirmations[txId][_msgSender()] = false;
        confirmationCount[txId]--;
        
        // 更新交易状态
        if (confirmationCount[txId] < required) {
            transactions[txId].status = TransactionStatus.Pending;
        }
        
        emit TransactionRevoked(txId, _msgSender(), confirmationCount[txId]);
    }

    /**
     * @dev 执行交易
     * @param txId 交易ID
     */
    function executeTransaction(uint256 txId)
        external
        nonReentrant
        txExists(txId)
        notExecuted(txId)
    {
        require(confirmationCount[txId] >= required, "Not enough confirmations");
        require(transactions[txId].status == TransactionStatus.Ready, "Transaction not ready");
        
        Transaction storage txn = transactions[txId];
        
        bool success;
        bytes memory returnData;
        
        try this._executeCall(txn.to, txn.value, txn.data) returns (bytes memory result) {
            success = true;
            returnData = result;
            txn.status = TransactionStatus.Executed;
        } catch {
            success = false;
            returnData = "";
            txn.status = TransactionStatus.Failed;
        }
        
        emit TransactionExecuted(txId, _msgSender(), success, returnData);
    }

    /**
     * @dev 内部执行函数，便于错误处理
     * @param to 目标地址
     * @param value ETH数量
     * @param data 调用数据
     * @return 调用返回数据
     */
    function _executeCall(address to, uint256 value, bytes memory data) 
        external 
        returns (bytes memory) 
    {
        require(_msgSender() == address(this), "Only self call");
        
        if (data.length == 0) {
            // 简单 ETH 转账
            payable(to).sendValue(value);
            return "";
        } else {
            // 合约调用
            return to.functionCallWithValue(data, value);
        }
    }

    /**
     * @dev 获取交易详细信息
     * @param txId 交易ID
     * @return to 目标地址
     * @return value ETH数量
     * @return data 调用数据
     * @return status 交易状态
     * @return confirmationCount_ 确认数量
     * @return timestamp 提交时间
     */
    function getTransaction(uint256 txId)
        external
        view
        txExists(txId)
        returns (
            address to,
            uint256 value,
            bytes memory data,
            TransactionStatus status,
            uint256 confirmationCount_,
            uint256 timestamp
        )
    {
        Transaction storage txn = transactions[txId];
        return (
            txn.to,
            txn.value,
            txn.data,
            txn.status,
            confirmationCount[txId],
            txn.timestamp
        );
    }

    /**
     * @dev 获取交易确认者列表
     * @param txId 交易ID
     * @return _confirmations 确认者地址数组
     */
    function getConfirmations(uint256 txId)
        external
        view
        txExists(txId)
        returns (address[] memory _confirmations)
    {
        address[] memory confirmationsTemp = new address[](owners.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < owners.length; i++) {
            if (confirmations[txId][owners[i]]) {
                confirmationsTemp[count] = owners[i];
                count++;
            }
        }
        
        _confirmations = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            _confirmations[i] = confirmationsTemp[i];
        }
    }

    /**
     * @dev 检查指定持有人是否已确认指定交易
     * @param txId 交易ID
     * @param owner 持有人地址
     * @return 是否已确认
     */
    function isConfirmed(uint256 txId, address owner)
        external
        view
        txExists(txId)
        returns (bool)
    {
        return confirmations[txId][owner];
    }
}
