const fs = require('fs');
const path = require('path');

// Path to pre-generated leafs file
const LEAFS_PATH = path.join(__dirname, '../../leafs/HyperLiquid/WstHypeLoopingDeploymentLeafs.json');

// Cache for loaded data
let cachedData = null;

/**
 * Load leafs data from filesystem
 * @returns {Object} Parsed leafs data
 */
function loadLeafsData() {
    if (cachedData) {
        return cachedData;
    }
    
    if (!fs.existsSync(LEAFS_PATH)) {
        throw new Error(`Leafs file not found at: ${LEAFS_PATH}`);
    }
    
    const rawData = fs.readFileSync(LEAFS_PATH, 'utf8');
    cachedData = JSON.parse(rawData);
    
    return cachedData;
}

/**
 * Get proof for leaf by description - matches test pattern
 * @param {string} description - Leaf description to find
 * @returns {Array} Merkle proof (bytes32[])
 */
function getProofForLeaf(description) {
    const data = loadLeafsData();
    
    // Find leaf by description
    const leafIndex = data.leafs.findIndex(leaf => 
        leaf.Description.toLowerCase().includes(description.toLowerCase())
    );
    
    if (leafIndex === -1) {
        throw new Error(`Leaf not found: ${description}`);
    }
    
    const leaf = data.leafs[leafIndex];
    const leafDigest = leaf.LeafDigest;
    
    // Generate proof using the tree structure (matches Solidity _generateProof)
    return generateProof(leafDigest, data.MerkleTree);
}

/**
 * Generate proof for a leaf digest - matches Solidity MerkleTreeHelper._generateProof exactly
 * @param {string} leafDigest - The leaf hash to generate proof for
 * @param {Object} tree - Merkle tree structure
 * @returns {Array} Merkle proof
 */
function generateProof(leafDigest, tree) {
    // Convert tree object to array format that matches Solidity
    // Solidity expects: tree[0] = leafs, tree[1] = level1, ..., tree[n] = root
    // JSON has: {"0": [root], "1": [...], "4": [leafs]} - need to reverse
    const treeArray = [];
    const maxLevel = Math.max(...Object.keys(tree).map(Number));
    
    // Reverse the tree structure to match Solidity format
    for (let i = maxLevel; i >= 0; i--) {
        treeArray.push(tree[i.toString()]);
    }
    
    // Find leaf in bottom layer (tree[0] in Solidity format)
    const leafIndex = treeArray[0].findIndex(hash => hash === leafDigest);
    
    if (leafIndex === -1) {
        throw new Error('Leaf not found in tree');
    }
    
    // The length of each proof is the height of the tree - 1
    const proof = new Array(treeArray.length - 1);
    let currentIndex = leafIndex;
    
    // Build proof by traversing up the tree (matches Solidity logic exactly)
    for (let i = 0; i < treeArray.length - 1; i++) {
        // Determine sibling index
        let siblingIndex;
        if (currentIndex % 2 === 0) {
            // Current is left child, sibling is right
            siblingIndex = currentIndex + 1;
            if (siblingIndex >= treeArray[i].length) {
                // No right sibling exists, use current node (duplicate case)
                siblingIndex = currentIndex;
            }
        } else {
            // Current is right child, sibling is left
            siblingIndex = currentIndex - 1;
        }
        
        proof[i] = treeArray[i][siblingIndex];
        currentIndex = Math.floor(currentIndex / 2); // Move to parent index in next layer
    }
    
    return proof;
}

/**
 * Get Merkle root
 * @returns {string} Merkle root hash
 */
function getMerkleRoot() {
    const data = loadLeafsData();
    return data.metadata.ManageRoot;
}

/**
 * Get all available leaf descriptions
 * @returns {Array} Array of descriptions
 */
function getAvailableLeafs() {
    const data = loadLeafsData();
    return data.leafs.map(leaf => leaf.Description);
}

/**
 * Get proofs for multiple looping cycles
 * @param {number} loops - Number of leverage loops to execute
 * @returns {Array} Array of proofs (bytes32[][]) for all operations
 */
function getLoopingProofs(loops = 1) {
    const proofs = [];
    
    // Each loop requires 5 operations (0-4)
    for (let i = 0; i < loops; i++) {
        proofs.push(getProofForLeaf('Withdraw wHYPE to get HYPE'));           // 0
        proofs.push(getProofForLeaf('Mint stHYPE from overseer'));            // 1
        proofs.push(getProofForLeaf('Approve Felix to spend wstHYPE'));       // 2
        proofs.push(getProofForLeaf('Felix supply collateral'));             // 3
        proofs.push(getProofForLeaf('Felix borrow wHYPE'));                   // 4
    }
    
    return proofs;
}

/**
 * Get proofs for unwinding operations (single sequence)
 * @returns {Array} Array of proofs (bytes32[][]) for unwinding
 */
function getUnwindingProofs() {
    const proofs = [];
    
    // Unwinding operations in order (5-10)
    proofs.push(getProofForLeaf('Approve wHYPE for Felix repayment'));    // 5
    proofs.push(getProofForLeaf('Felix repay wHYPE loan'));               // 6
    proofs.push(getProofForLeaf('Felix withdraw wstHYPE collateral'));    // 7
    proofs.push(getProofForLeaf('Approve stHYPE for Overseer burn'));     // 8
    proofs.push(getProofForLeaf('Burn stHYPE and redeem HYPE'));          // 9
    proofs.push(getProofForLeaf('Deposit HYPE to get wHYPE'));            // 10
    
    return proofs;
}

/**
 * Get proofs for multiple burn redemptions
 * @param {number} burnCount - Number of burn redemptions to process
 * @returns {Array} Array of proofs (bytes32[][]) for burn redemptions
 */
function getBurnRedemptionProofs(burnCount) {
    const proofs = [];
    
    // Each burn requires 1 redemption operation 
    for (let i = 0; i < burnCount; i++) {
        proofs.push(getProofForLeaf('Redeem completed burn request'));
    }
    
    return proofs;
}

/**
 * Get proof for a single operation by index (0-11)
 * @param {number} operationIndex - Index of operation (0-11)
 * @returns {Array} Proof array (bytes32[])
 */
function getProofByIndex(operationIndex) {
    const data = loadLeafsData();
    
    if (operationIndex < 0 || operationIndex >= data.leafs.length) {
        throw new Error(`Invalid operation index: ${operationIndex}`);
    }
    
    const leaf = data.leafs[operationIndex];
    return generateProof(leaf.LeafDigest, data.MerkleTree);
}

module.exports = {
    getProofForLeaf,
    getProofByIndex,
    getMerkleRoot,
    getAvailableLeafs,
    getLoopingProofs,
    getUnwindingProofs,
    getBurnRedemptionProofs
};
