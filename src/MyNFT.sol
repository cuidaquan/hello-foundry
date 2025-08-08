// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title MyNFT
 * @dev ERC721标准的NFT合约，支持铸造功能
 */
contract MyNFT is ERC721, ERC721URIStorage, Ownable {

    // 代币ID计数器
    uint256 private _tokenIdCounter;
    
    // 铸造事件
    event NFTMinted(address indexed to, uint256 indexed tokenId, string tokenURI);
    
    /**
     * @dev 构造函数
     */
    constructor() ERC721("MyNFT", "MNFT") Ownable(msg.sender) {
        // NFT名称: MyNFT, 符号: MNFT
        // 初始化计数器为0
        _tokenIdCounter = 0;
    }
    
    /**
     * @dev 铸造NFT - 只有合约拥有者可以调用
     * @param to 接收者地址
     * @param uri NFT的元数据URI
     * @return tokenId 新铸造的NFT的ID
     */
    function mint(address to, string memory uri) public onlyOwner returns (uint256) {
        require(to != address(0), "Cannot mint to zero address");
        require(bytes(uri).length > 0, "Token URI cannot be empty");

        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);

        emit NFTMinted(to, tokenId, uri);

        return tokenId;
    }
    
    /**
     * @dev 获取下一个要铸造的NFT ID
     * @return 下一个NFT ID
     */
    function getNextTokenId() public view returns (uint256) {
        return _tokenIdCounter;
    }

    /**
     * @dev 获取已铸造的NFT总数
     * @return NFT总数
     */
    function getTotalSupply() public view returns (uint256) {
        return _tokenIdCounter;
    }
    
    /**
     * @dev 检查NFT是否存在
     * @param tokenId NFT ID
     * @return 是否存在
     */
    function exists(uint256 tokenId) public view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
    
    /**
     * @dev 获取用户拥有的所有NFT ID
     * @param owner 用户地址
     * @return tokenIds NFT ID数组
     */
    function getTokensByOwner(address owner) public view returns (uint256[] memory) {
        require(owner != address(0), "Owner cannot be zero address");
        
        uint256 tokenCount = balanceOf(owner);
        if (tokenCount == 0) {
            return new uint256[](0);
        }
        
        uint256[] memory tokenIds = new uint256[](tokenCount);
        uint256 index = 0;
        uint256 totalSupply = getTotalSupply();
        
        for (uint256 i = 0; i < totalSupply && index < tokenCount; i++) {
            if (_ownerOf(i) != address(0) && ownerOf(i) == owner) {
                tokenIds[index] = i;
                index++;
            }
        }
        
        return tokenIds;
    }
    
    // 重写必要的函数以解决继承冲突
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        return super._update(to, tokenId, auth);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
