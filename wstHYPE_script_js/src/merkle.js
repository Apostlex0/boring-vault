const fs = require('fs');
const path = require('path');
const logger = require('./logger');

// Path to pre-generated Merkle proofs
const LEAFS_PATH = path.join(__dirname, '../../leafs/HyperLiquid/WstHypeLoopingDeploymentLeafs.json');

// Cache for loaded proof data
let cachedProofData = null;

/**
 * Load pre-generated Merkle proofs from filesystem
 * @returns {Object} Parsed proof data with leafs and tree
 */
function loadProofData() {
    try {
        if (cachedProofData) {
            return cachedProofData;
        }
        
        if (!fs.existsSync(LEAFS_PATH)) {
            throw new Error(`Merkle proof file not found at: ${LEAFS_PATH}`);
        }
        
        const rawData = fs.readFileSync(LEAFS_PATH, 'utf8');
        cachedProofData = JSON.parse(rawData);
        
        logger.info('Loaded pre-generated Merkle proofs', {
            leafCount: cachedProofData.leafs.length,
            manageRoot: cachedProofData.metadata.ManageRoot,
            treeCapacity: cachedProofData.metadata.TreeCapacity
        });
        
        return cachedProofData;
    } catch (error) {
        logger.error('Error loading proof data:', error);
        throw error;
    }
}

/**
 * Generate Merkle proof for specific leaf by description
 * @param {string} description - Leaf description to find
 * @returns {Array} Merkle proof array (bytes32[])
 */
function getProofForLeaf(description) {
    try {
        const proofData = loadProofData();
        
        // Find leaf by description
        const leafIndex = proofData.leafs.findIndex(leaf => 
            leaf.Description.toLowerCase().includes(description.toLowerCase())
        );
        
        if (leafIndex === -1) {
            throw new Error(`Leaf not found for description: ${description}`);
        }
        
        const leaf = proofData.leafs[leafIndex];
        
        // Generate proof using the pre-built Merkle tree
        const proof = generateProofFromTree(leafIndex, proofData.MerkleTree);
        
        logger.debug('Generated proof for leaf', {
            description,
            leafIndex,
            leafDigest: leaf.LeafDigest,
            proofLength: proof.length
        });
        
        return proof;
    } catch (error) {
        logger.error('Error generating proof for leaf:', error);
        throw error;
    }
}

/**
 * Generate Merkle proofs for looping strategy operations
 * Based on WstHypeLoopingUManager._prepareLoopingBatch: 5 operations per loop
 * @param {Object} params - Strategy parameters
 * @returns {Array} Array of Merkle proofs (bytes32[][])
 */
function generateLoopingProofs(params) {
    try {
        const { leverageLoops } = params;
        const proofs = [];
        
        // Each loop has exactly 5 operations (from contract analysis)
        for (let i = 0; i < leverageLoops; i++) {
            // 1. Unwrap wHYPE to HYPE (withdraw)
            const withdrawProof = getProofForLeaf('Withdraw wHYPE to get HYPE');
            proofs.push(withdrawProof);
            
            // 2. Mint stHYPE from overseer (with HYPE value)
            const mintProof = getProofForLeaf('Mint stHYPE from overseer');
            proofs.push(mintProof);
            
            // 3. Approve wstHYPE to Felix
            const approveProof = getProofForLeaf('Approve Felix to spend wstHYPE');
            proofs.push(approveProof);
            
            // 4. Supply wstHYPE as collateral to Felix
            const supplyProof = getProofForLeaf('Felix supply collateral');
            proofs.push(supplyProof);
            
            // 5. Borrow wHYPE from Felix
            const borrowProof = getProofForLeaf('Felix borrow wHYPE');
            proofs.push(borrowProof);
        }
        
        logger.info('Generated looping strategy Merkle proofs', {
            leverageLoops,
            totalOperations: leverageLoops * 5,
            proofCount: proofs.length
        });
        
        return proofs;
    } catch (error) {
        logger.error('Error generating looping proofs:', error);
        throw error;
    }
}

/**
 * Generate Merkle proofs for unwinding strategy operations
 * Based on WstHypeLoopingUManager._prepareUnwindingBatch: 6 total operations
 * @param {Object} params - Strategy parameters
 * @returns {Array} Array of Merkle proofs (bytes32[][])
 */
function generateUnwindingProofs() {
    try {
        const proofs = [];
        
        // Unwinding has exactly 6 operations (from contract analysis)
        // 1. Approve wHYPE for repayment
        const approveWHypeProof = getProofForLeaf('Approve wHYPE for Felix repayment');
        proofs.push(approveWHypeProof);
        
        // 2. Repay loan to Felix
        const repayProof = getProofForLeaf('Felix repay wHYPE loan');
        proofs.push(repayProof);
        
        // 3. Withdraw collateral from Felix
        const withdrawCollateralProof = getProofForLeaf('Felix withdraw wstHYPE collateral');
        proofs.push(withdrawCollateralProof);
        
        // 4. Approve stHYPE for burning
        const approveStHypeProof = getProofForLeaf('Approve stHYPE for Overseer burn');
        proofs.push(approveStHypeProof);
        
        // 5. Burn stHYPE and redeem if possible
        const burnProof = getProofForLeaf('Burn stHYPE and redeem HYPE');
        proofs.push(burnProof);
        
        // 6. Wrap HYPE to wHYPE (deposit with value)
        const wrapProof = getProofForLeaf('Deposit HYPE to get wHYPE');
        proofs.push(wrapProof);
        
        logger.info('Generated unwinding strategy Merkle proofs', {
            totalOperations: 6,
            proofCount: proofs.length
        });
        
        return proofs;
    } catch (error) {
        logger.error('Error generating unwinding proofs:', error);
        throw error;
    }
}

/**
 * Generate Merkle proofs for burn redemption operations
 * Based on WstHypeLoopingUManager.completeBurnRedemptions: 1 operation per burnId
 * @param {Object} params - Strategy parameters
 * @returns {Array} Array of Merkle proofs (bytes32[][])
 */
function generateBurnRedemptionProofs(params) {
    try {
        const { burnIds } = params;
        const proofs = [];
        
        // Each burn ID requires exactly 1 redeem operation
        for (let i = 0; i < burnIds.length; i++) {
            const redeemProof = getProofForLeaf('Redeem completed burn request');
            proofs.push(redeemProof);
        }
        
        logger.info('Generated burn redemption Merkle proofs', {
            burnIdCount: burnIds.length,
            proofCount: proofs.length
        });
        
        return proofs;
    } catch (error) {
        logger.error('Error generating burn redemption proofs:', error);
        throw error;
    }
}

/**
 * Generate Merkle proof from tree data
 * @param {number} leafIndex - Index of the leaf in the tree
 * @param {Object} treeData - Merkle tree data
 * @returns {Array} Merkle proof
 */
function generateProofFromTree(leafIndex, treeData) {
    const proof = [];
    let currentIndex = leafIndex;
    
    // Start from the leaf level (highest level number)
    const maxLevel = Math.max(...Object.keys(treeData).map(Number));
    
    for (let level = maxLevel; level > 0; level--) {
        const levelNodes = treeData[level];
        if (!levelNodes || currentIndex >= levelNodes.length) {
            break;
        }
        
        // Determine sibling index
        const isRightNode = currentIndex % 2 === 1;
        const siblingIndex = isRightNode ? currentIndex - 1 : currentIndex + 1;
        
        // Add sibling to proof if it exists
        if (siblingIndex < levelNodes.length) {
            proof.push(levelNodes[siblingIndex]);
        }
        
        // Move to parent index for next level
        currentIndex = Math.floor(currentIndex / 2);
    }
    
    return proof;
}

/**
 * Get the Merkle root from pre-generated data
 * @returns {string} Merkle root hash
 */
function getMerkleRoot() {
    try {
        const proofData = loadProofData();
        return proofData.metadata.ManageRoot;
    } catch (error) {
        logger.error('Error getting Merkle root:', error);
        throw error;
    }
}

module.exports = {
    generateLoopingProofs,
    generateUnwindingProofs,
    generateBurnRedemptionProofs,
    getMerkleRoot
};
