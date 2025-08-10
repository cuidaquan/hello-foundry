import React, { useState, useEffect } from 'react'
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt, useReadContracts } from 'wagmi'
import { parseEther, formatEther } from 'viem'
import { MyNFTABI, MY_NFT_ADDRESS } from '../contracts/MyNFT'
import { NFTMarketABI, NFT_MARKET_ADDRESS } from '../contracts/NFTMarket'

interface NFT {
  tokenId: bigint
  tokenURI: string
  isApproved: boolean
}

interface ListNFTProps {
  onListedSuccess?: () => void
}

const ListNFT: React.FC<ListNFTProps> = ({ onListedSuccess }) => {
  const { address } = useAccount()
  const [userNFTs, setUserNFTs] = useState<NFT[]>([])
  const [selectedNFT, setSelectedNFT] = useState<bigint | null>(null)
  const [price, setPrice] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [approvedNFTs, setApprovedNFTs] = useState<Set<string>>(new Set())
  const [currentApprovingNFT, setCurrentApprovingNFT] = useState<bigint | null>(null)

  const { writeContract, data: hash, isPending } = useWriteContract()
  
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({
    hash,
  })

  // 获取用户拥有的 NFT
  const { data: tokenIds } = useReadContract({
    address: MY_NFT_ADDRESS,
    abi: MyNFTABI,
    functionName: 'getTokensByOwner',
    args: address ? [address] : undefined,
  })

  // 获取 NFT 详细信息
  useEffect(() => {
    const fetchNFTDetails = async () => {
      if (!tokenIds || tokenIds.length === 0) {
        setUserNFTs([])
        return
      }

      setLoading(true)
      try {
        const nftDetails: NFT[] = []

        for (const tokenId of tokenIds) {
          // 简单的 tokenURI，实际项目中可以调用合约获取
          const tokenURI = `My NFT #${tokenId.toString()}`

          // 检查是否已授权给市场合约
          // 检查本地状态中是否已标记为授权
          const isApproved = approvedNFTs.has(tokenId.toString())

          nftDetails.push({
            tokenId,
            tokenURI,
            isApproved
          })
        }

        setUserNFTs(nftDetails)
      } catch (err) {
        console.error('获取 NFT 详情失败:', err)
        setError('获取 NFT 详情失败')
      } finally {
        setLoading(false)
      }
    }

    fetchNFTDetails()
  }, [tokenIds])

  // 授权 NFT 给市场合约
  const handleApprove = async (tokenId: bigint) => {
    try {
      setError('')
      setCurrentOperation('approve')
      setCurrentApprovingNFT(tokenId)
      writeContract({
        address: MY_NFT_ADDRESS,
        abi: MyNFTABI,
        functionName: 'approve',
        args: [NFT_MARKET_ADDRESS, tokenId],
      })
    } catch (err: any) {
      setError(`授权失败: ${err.message}`)
      setCurrentOperation(null)
      setCurrentApprovingNFT(null)
    }
  }

  // 上架 NFT
  const handleListNFT = async () => {
    if (!selectedNFT || !price) {
      setError('请选择 NFT 并输入价格')
      return
    }

    try {
      setError('')
      setSuccess('')
      setCurrentOperation('list')

      const priceInWei = parseEther(price)

      writeContract({
        address: NFT_MARKET_ADDRESS,
        abi: NFTMarketABI,
        functionName: 'list',
        args: [selectedNFT, priceInWei],
      })
    } catch (err: any) {
      setError(`上架失败: ${err.message}`)
      setCurrentOperation(null)
    }
  }

  // 添加一个状态来跟踪当前操作类型
  const [currentOperation, setCurrentOperation] = useState<'approve' | 'list' | null>(null)

  // 监听交易确认
  useEffect(() => {
    if (isConfirmed) {
      if (currentOperation === 'list') {
        // 如果是上架操作
        setSuccess('NFT 上架成功！')
        setSelectedNFT(null)
        setPrice('')
        setCurrentOperation(null)
        // 回调通知父组件（App）切换到市场页
        onListedSuccess && onListedSuccess()
      } else if (currentOperation === 'approve' && currentApprovingNFT) {
        // 如果是授权操作，更新授权状态但不跳转页面
        setSuccess('授权成功！现在可以选择 NFT 进行上架')
        setCurrentOperation(null)

        // 更新本地状态，标记该NFT为已授权
        setApprovedNFTs(prev => new Set([...prev, currentApprovingNFT.toString()]))
        setCurrentApprovingNFT(null)

        // 更新NFT列表中的授权状态
        setUserNFTs(prev => prev.map(nft =>
          nft.tokenId === currentApprovingNFT
            ? { ...nft, isApproved: true }
            : nft
        ))
      }
    }
  }, [isConfirmed, currentOperation])

  if (loading) {
    return <div className="loading">加载中...</div>
  }

  return (
    <div>
      <h2>上架我的 NFT</h2>

      <div className="card" style={{ marginBottom: '1rem', background: '#1a1a2e' }}>
        <h3>上架流程说明</h3>
        <ol style={{ paddingLeft: '1.5rem', lineHeight: '1.6' }}>
          <li>首先点击"授权给市场"按钮，授权 NFT 给市场合约</li>
          <li>授权成功后，点击"选择上架"选择要上架的 NFT</li>
          <li>输入价格并点击"确认上架"完成上架</li>
          <li>上架成功后可以在市场页面查看</li>
        </ol>
      </div>

      {error && <div className="error">{error}</div>}
      {success && <div className="success">{success}</div>}

      {userNFTs.length === 0 ? (
        <div className="card">
          <p>您还没有任何 NFT</p>
        </div>
      ) : (
        <>
          <div className="grid">
            {userNFTs.map((nft) => (
              <div key={nft.tokenId.toString()} className="nft-card">
                <div className="nft-image" style={{ 
                  background: `linear-gradient(45deg, #${nft.tokenId.toString(16).padStart(6, '0')}, #${(Number(nft.tokenId) * 123456).toString(16).slice(-6)})`,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  color: 'white',
                  fontSize: '1.2rem',
                  fontWeight: 'bold'
                }}>
                  NFT #{nft.tokenId.toString()}
                </div>
                <h3>{nft.tokenURI}</h3>
                <div style={{ marginTop: '1rem' }}>
                  {!nft.isApproved ? (
                    <div>
                      <button
                        onClick={() => handleApprove(nft.tokenId)}
                        disabled={isPending || isConfirming}
                        style={{ width: '100%', marginBottom: '0.5rem' }}
                      >
                        {isPending || isConfirming ? '授权中...' : '授权给市场'}
                      </button>
                      <p style={{ fontSize: '0.8rem', color: '#999', textAlign: 'center' }}>
                        需要先授权才能上架
                      </p>
                    </div>
                  ) : (
                    <div>
                      <button
                        onClick={() => setSelectedNFT(nft.tokenId)}
                        disabled={selectedNFT === nft.tokenId}
                        style={{
                          width: '100%',
                          marginBottom: '0.5rem',
                          backgroundColor: selectedNFT === nft.tokenId ? '#646cff' : '#4CAF50'
                        }}
                      >
                        {selectedNFT === nft.tokenId ? '已选择' : '选择上架'}
                      </button>
                      <p style={{ fontSize: '0.8rem', color: '#4CAF50', textAlign: 'center' }}>
                        ✓ 已授权，可以上架
                      </p>
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>

          {selectedNFT && (
            <div className="card" style={{ marginTop: '2rem' }}>
              <h3>上架 NFT #{selectedNFT.toString()}</h3>
              <div className="form-group">
                <label>价格 (ETH):</label>
                <input
                  type="number"
                  step="0.001"
                  value={price}
                  onChange={(e) => setPrice(e.target.value)}
                  placeholder="输入价格"
                />
              </div>
              <button
                onClick={handleListNFT}
                disabled={isPending || isConfirming || !price}
                style={{ width: '100%' }}
              >
                {isPending || isConfirming ? '上架中...' : '确认上架'}
              </button>
            </div>
          )}
        </>
      )}
    </div>
  )
}

export default ListNFT
