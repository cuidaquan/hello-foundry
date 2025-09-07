// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract BankV2 {
    struct Node {
        address user;
        uint256 balance;
        address next;
        address prev;
    }
    
    // 存储每个用户的余额
    mapping(address => uint256) public balances;
    
    // 链表节点映射
    mapping(address => Node) public leaderboard;
    
    // 链表头部和尾部
    address public head;
    address public tail;
    
    // 链表长度
    uint256 public leaderboardSize;
    
    // 最大排行榜大小
    uint256 public constant MAX_LEADERBOARD_SIZE = 10;
    
    // 事件
    event Deposit(address indexed user, uint256 amount, uint256 newBalance);
    event LeaderboardUpdated(address indexed user, uint256 balance, uint256 rank);

    // 接收存款的函数
    receive() external payable {
        require(msg.value > 0, "Deposit must be greater than 0");
        
        balances[msg.sender] += msg.value;
        
        updateLeaderboard(msg.sender);
        
        emit Deposit(msg.sender, msg.value, balances[msg.sender]);
    }
    
    // 手动存款函数
    function deposit() external payable {
        require(msg.value > 0, "Deposit must be greater than 0");
        
        balances[msg.sender] += msg.value;
        
        updateLeaderboard(msg.sender);
        
        emit Deposit(msg.sender, msg.value, balances[msg.sender]);
    }

    // 从链表中移除节点
    function _removeFromLeaderboard(address user) internal {
        if (leaderboard[user].user == address(0)) return;
        
        Node storage node = leaderboard[user];
        
        if (node.prev != address(0)) {
            leaderboard[node.prev].next = node.next;
        } else {
            head = node.next;
        }
        
        if (node.next != address(0)) {
            leaderboard[node.next].prev = node.prev;
        } else {
            tail = node.prev;
        }
        
        delete leaderboard[user];
        leaderboardSize--;
    }
    
    // 插入节点到正确位置
    function _insertIntoLeaderboard(address user, uint256 balance) internal {
        if (leaderboardSize == 0) {
            // 第一个节点
            leaderboard[user] = Node(user, balance, address(0), address(0));
            head = user;
            tail = user;
            leaderboardSize = 1;
            return;
        }
        
        // 寻找插入位置
        address current = head;
        while (current != address(0) && leaderboard[current].balance >= balance) {
            current = leaderboard[current].next;
        }
        
        if (current == address(0)) {
            // 插入到尾部
            leaderboard[user] = Node(user, balance, address(0), tail);
            leaderboard[tail].next = user;
            tail = user;
        } else if (current == head) {
            // 插入到头部
            leaderboard[user] = Node(user, balance, head, address(0));
            leaderboard[head].prev = user;
            head = user;
        } else {
            // 插入到中间
            address prevNode = leaderboard[current].prev;
            leaderboard[user] = Node(user, balance, current, prevNode);
            leaderboard[current].prev = user;
            leaderboard[prevNode].next = user;
        }
        
        leaderboardSize++;
        
        // 如果超过最大大小，移除最后一个
        if (leaderboardSize > MAX_LEADERBOARD_SIZE) {
            address lastNode = tail;
            _removeFromLeaderboard(lastNode);
        }
    }

    // 更新排行榜
    function updateLeaderboard(address user) internal {
        uint256 balance = balances[user];
        
        // 如果用户已经在排行榜中，先移除
        if (leaderboard[user].user != address(0)) {
            _removeFromLeaderboard(user);
        }
        
        // 如果余额为0，不添加到排行榜
        if (balance == 0) {
            return;
        }
        
        // 如果排行榜未满，或者当前余额大于最后一名，则插入
        if (leaderboardSize < MAX_LEADERBOARD_SIZE || 
            (tail != address(0) && balance > leaderboard[tail].balance)) {
            _insertIntoLeaderboard(user, balance);
            
            // 计算排名
            uint256 rank = 1;
            address current = head;
            while (current != address(0) && current != user) {
                rank++;
                current = leaderboard[current].next;
            }
            
            emit LeaderboardUpdated(user, balance, rank);
        }
    }

    // 获取排行榜
    function getLeaderboard() external view returns (address[] memory users, uint256[] memory amounts) {
        users = new address[](leaderboardSize);
        amounts = new uint256[](leaderboardSize);
        
        address current = head;
        uint256 index = 0;
        
        while (current != address(0) && index < leaderboardSize) {
            users[index] = current;
            amounts[index] = leaderboard[current].balance;
            current = leaderboard[current].next;
            index++;
        }
    }
    
    // 获取用户余额
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }
    
    // 获取用户排名（如果在前10名）
    function getUserRank(address user) external view returns (uint256 rank, bool inLeaderboard) {
        if (leaderboard[user].user == address(0)) {
            return (0, false);
        }
        
        rank = 1;
        address current = head;
        while (current != address(0) && current != user) {
            rank++;
            current = leaderboard[current].next;
        }
        
        return (rank, true);
    }
    
    // 获取合约总余额
    function getTotalDeposits() external view returns (uint256) {
        return address(this).balance;
    }
    
    // 获取排行榜大小
    function getLeaderboardSize() external view returns (uint256) {
        return leaderboardSize;
    }
}