# 可升级的 NFT Market 合约项目

## 文件结构

```
src/
├── MyNFTUpgradeable.sol              # 可升级的 ERC721 NFT
├── NFTMarketUpgradeableV1.sol        # 市场合约 V1
├── NFTMarketUpgradeableV2.sol        # 市场合约 V2（含签名功能）
└── ExtendedERC20.sol                 # ERC20 代币（支持回调）

script/
└── DeployUpgradeableNFTMarket.s.sol  # 部署和升级脚本

test/
└── NFTMarketUpgradeable.t.sol        # 完整测试用例（包括升级测试）

test-logs/
└── NFTMarketUpgradeable.log          # 测试日志
```

## 运行测试

```bash
# 运行所有测试
forge test --match-contract NFTMarketUpgradeableTest

# 查看详细日志
forge test --match-contract NFTMarketUpgradeableTest -vv

# 查看 gas 报告
forge test --match-contract NFTMarketUpgradeableTest --gas-report
```

## 部署说明

### 1. 部署初始合约（V1）

```bash
forge script script/DeployUpgradeableNFTMarket.s.sol:DeployUpgradeableNFTMarket --rpc-url sepolia --broadcast --verify -vvv 
```

部署后会输出：
- Payment Token 地址： 0xD90d5a361ab5F824386efa68c2802cDaC4EaD27D
- NFT Implementation 地址: 0xc326B0051bFC3D6bAc110414F144Eb79f25450bc
- NFT Proxy 地址: 0x7e22119c13e3bBB17273822C6FC1BBDc54efe375
- Market V1 Implementation 地址: 0x099655D1af57A1D2799d3923FDe224A911C0CB6C
- Market Proxy 地址: 0x1FCE120E7297F539FF77a66dd7d80F7F791E776e


### 2. 升级到 V2

```bash
forge script script/DeployUpgradeableNFTMarket.s.sol:UpgradeNFTMarketToV2 --rpc-url sepolia --broadcast --verify -vvv 
```
部署后会输出：
- Market V2 Implementation 地址: 0x026398126d52cf38d973b2b3f8f1953f18201af5



## 依赖
```bash
forge install OpenZeppelin/openzeppelin-foundry-upgrades
forge install OpenZeppelin/openzeppelin-contracts-upgradeable
```