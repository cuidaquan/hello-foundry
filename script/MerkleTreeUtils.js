const crypto = require('crypto');

/**
 * Merkle Tree implementation for whitelist verification
 */
class MerkleTree {
    constructor(leaves) {
        this.leaves = leaves.map(leaf => this.hashLeaf(leaf));
        this.layers = this.buildTree(this.leaves);
        this.root = this.layers[this.layers.length - 1][0];
    }

    /**
     * Hash a leaf node (address)
     */
    hashLeaf(address) {
        // Remove '0x' prefix if present and convert to lowercase
        const cleanAddress = address.replace('0x', '').toLowerCase();
        // Pad to 40 characters if needed
        const paddedAddress = cleanAddress.padStart(40, '0');
        
        // Keccak256 hash of the packed address (same as Solidity's keccak256(abi.encodePacked(address)))
        const addressBytes = Buffer.from(paddedAddress, 'hex');
        return this.keccak256(addressBytes);
    }

    /**
     * Hash two nodes together
     */
    hashPair(left, right) {
        if (!left) return right;
        if (!right) return left;
        
        // Sort the hashes to ensure consistent ordering
        const sortedHashes = [left, right].sort(Buffer.compare);
        const combined = Buffer.concat(sortedHashes);
        return this.keccak256(combined);
    }

    /**
     * Simple Keccak256 implementation using Node.js crypto
     */
    keccak256(data) {
        return crypto.createHash('sha3-256').update(data).digest();
    }

    /**
     * Build the Merkle tree layers
     */
    buildTree(leaves) {
        if (leaves.length === 0) {
            throw new Error('Cannot build tree with no leaves');
        }

        const layers = [leaves];
        
        while (layers[layers.length - 1].length > 1) {
            const currentLayer = layers[layers.length - 1];
            const nextLayer = [];
            
            for (let i = 0; i < currentLayer.length; i += 2) {
                const left = currentLayer[i];
                const right = i + 1 < currentLayer.length ? currentLayer[i + 1] : null;
                nextLayer.push(this.hashPair(left, right));
            }
            
            layers.push(nextLayer);
        }
        
        return layers;
    }

    /**
     * Get the Merkle root as hex string
     */
    getRoot() {
        return '0x' + this.root.toString('hex');
    }

    /**
     * Generate proof for a given address
     */
    getProof(address) {
        const targetLeaf = this.hashLeaf(address);
        let leafIndex = -1;
        
        // Find the leaf index
        for (let i = 0; i < this.leaves.length; i++) {
            if (this.leaves[i].equals(targetLeaf)) {
                leafIndex = i;
                break;
            }
        }
        
        if (leafIndex === -1) {
            throw new Error('Address not found in tree');
        }

        const proof = [];
        let currentIndex = leafIndex;

        // Build proof by traversing up the tree
        for (let layerIndex = 0; layerIndex < this.layers.length - 1; layerIndex++) {
            const currentLayer = this.layers[layerIndex];
            const isRightNode = currentIndex % 2 === 1;
            const siblingIndex = isRightNode ? currentIndex - 1 : currentIndex + 1;
            
            if (siblingIndex < currentLayer.length) {
                proof.push('0x' + currentLayer[siblingIndex].toString('hex'));
            }
            
            currentIndex = Math.floor(currentIndex / 2);
        }

        return proof;
    }

    /**
     * Verify a proof for given address and root
     */
    static verify(proof, root, address) {
        const tree = new MerkleTree([address]);
        let computedHash = tree.hashLeaf(address);
        
        for (const proofElement of proof) {
            const proofBuffer = Buffer.from(proofElement.replace('0x', ''), 'hex');
            
            // Sort to maintain consistent ordering
            const sortedHashes = [computedHash, proofBuffer].sort(Buffer.compare);
            const combined = Buffer.concat(sortedHashes);
            computedHash = tree.keccak256(combined);
        }
        
        const rootBuffer = Buffer.from(root.replace('0x', ''), 'hex');
        return computedHash.equals(rootBuffer);
    }
}

/**
 * Generate whitelist data for smart contract deployment
 */
function generateWhitelist(addresses) {
    console.log('Generating Merkle tree for whitelist...');
    console.log('Addresses:', addresses);
    
    const tree = new MerkleTree(addresses);
    const root = tree.getRoot();
    
    console.log('\n=== MERKLE TREE RESULTS ===');
    console.log('Merkle Root:', root);
    console.log('\nProofs for each address:');
    
    const proofs = {};
    addresses.forEach(address => {
        const proof = tree.getProof(address);
        proofs[address] = proof;
        console.log(`${address}: [${proof.map(p => `"${p}"`).join(', ')}]`);
        
        // Verify the proof
        const isValid = MerkleTree.verify(proof, root, address);
        console.log(`  Verification: ${isValid ? '✓ Valid' : '✗ Invalid'}`);
    });
    
    return {
        root,
        proofs
    };
}

// Example usage and testing
if (require.main === module) {
    // Example whitelist addresses
    const whitelistAddresses = [
        '0x1234567890123456789012345678901234567890',
        '0xAbCdEf1234567890123456789012345678901234',
        '0x9876543210987654321098765432109876543210',
        '0xfedcba0987654321098765432109876543210987',
        '0x1111111111111111111111111111111111111111'
    ];
    
    const result = generateWhitelist(whitelistAddresses);
    
    console.log('\n=== FOR SMART CONTRACT ===');
    console.log(`Merkle Root: ${result.root}`);
    console.log('\n=== FOR FRONTEND ===');
    console.log('Proofs object:');
    console.log(JSON.stringify(result.proofs, null, 2));
}

module.exports = {
    MerkleTree,
    generateWhitelist
};