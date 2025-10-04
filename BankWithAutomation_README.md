# Bank with ChainLink Automation

这是一个集成了 ChainLink Automation 功能的智能合约银行系统，当存款超过设定阈值时，会自动转移一半的余额到指定地址（Owner）。

## 合约信息

### 已部署合约地址
- **网络**: Sepolia Testnet
- **合约地址**: `0xef8cd5D9FE33D0fB851E3a4217b6A696B97b8584`
- **Etherscan**: https://sepolia.etherscan.io/address/0xef8cd5d9fe33d0fb851e3a4217b6a696b97b8584
- **阈值**: 0.1 ETH (100000000000000000 wei)

## 功能特性

### 1. 存款功能 (deposit)
- 用户可以通过 `deposit()` 函数存入 ETH
- 也支持直接向合约地址转账（通过 receive 函数）
- 记录每个用户的存款金额

### 2. ChainLink Automation 集成
- **checkUpkeep**: 当合约余额 >= 阈值时，返回 true
- **performUpkeep**: 自动将合约余额的一半转给 Owner

### 3. 管理功能
- Owner 可以更新触发阈值 (`setThreshold`)
- 查询合约余额 (`getBalance`)
- 查询用户存款 (`getUserDeposit`)

## 使用方式

### 本地测试
```bash
# 运行测试
forge test --match-contract BankWithAutomationTest -vv
```

### 部署到测试网
```bash
# 部署到 Sepolia
forge script script/DeployBankWithAutomation.s.sol:DeployBankWithAutomation --rpc-url sepolia --broadcast --verify
```

### 与合约交互

#### 1. 存款
```bash
# 使用 cast 发送 ETH
cast send 0xef8cd5D9FE33D0fB851E3a4217b6A696B97b8584 "deposit()" --value 0.05ether --rpc-url sepolia --private-key $PRIVATE_KEY
```

#### 2. 查询余额
```bash
# 查询合约总余额
cast call 0xef8cd5D9FE33D0fB851E3a4217b6A696B97b8584 "getBalance()" --rpc-url sepolia

# 查询用户存款
cast call 0xef8cd5D9FE33D0fB851E3a4217b6A696B97b8584 "getUserDeposit(address)" <USER_ADDRESS> --rpc-url sepolia
```

#### 3. 检查 Upkeep 状态
```bash
cast call 0xef8cd5D9FE33D0fB851E3a4217b6A696B97b8584 "checkUpkeep(bytes)" 0x --rpc-url sepolia
```

## ChainLink Automation 设置

### 在 ChainLink Automation 网站上注册 Upkeep

1. 访问 [ChainLink Automation](https://automation.chain.link/)
2. 连接钱包并切换到 Sepolia 网络
3. 点击 "Register new Upkeep"
4. 选择 "Custom logic" 类型
5. 填写信息：
   - **Target contract address**: `0xef8cd5D9FE33D0fB851E3a4217b6A696B97b8584`
   - **Upkeep name**: Bank Auto Transfer
   - **Gas limit**: 500000
   - **Starting balance**: 根据需要添加 LINK（建议至少 5 LINK）

6. 确认并等待交易完成

### Automation 执行链接
注册完成后，你会获得一个 Upkeep ID，可以在以下位置查看：
- ChainLink Automation Dashboard: https://automation.chain.link/sepolia/1744955911604018015877705420496439620141775180267641191882846726347489726990

## 工作流程

1. **用户存款**: 用户调用 `deposit()` 函数或直接向合约转账
2. **余额累积**: 合约记录所有存款，总余额不断增长
3. **触发条件**: 当合约余额 >= 0.1 ETH 时
4. **ChainLink Automation 检测**: `checkUpkeep()` 返回 true
5. **自动执行**: ChainLink 节点调用 `performUpkeep()`
6. **转账**: 将合约余额的一半转给 Owner
7. **循环**: 重复上述过程

## 代码结构

```
src/BankWithAutomation.sol          # 主合约
script/DeployBankWithAutomation.s.sol  # 部署脚本
test/BankWithAutomation.t.sol       # 测试文件
```

## GitHub 仓库
https://github.com/cuidaquan/hello-foundry

## 注意事项

1. 确保 Owner 地址能够接收 ETH
2. 需要在 ChainLink Automation 中维护足够的 LINK 余额
3. 阈值可以通过 `setThreshold()` 调整（仅 Owner）
4. 测试时建议使用小额 ETH

## 测试覆盖

- ✅ 基本存款功能
- ✅ 通过 receive 函数接收 ETH
- ✅ checkUpkeep 逻辑验证
- ✅ performUpkeep 自动转账
- ✅ 阈值更新功能
- ✅ 权限控制
- ✅ 完整工作流程

所有 11 个测试用例均通过！
