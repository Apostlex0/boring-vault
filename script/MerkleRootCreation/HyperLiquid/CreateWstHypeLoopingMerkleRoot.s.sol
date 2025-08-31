// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import "forge-std/Script.sol";

/**
 * @title CreateWstHypeLoopingMerkleRootScript
 * @notice Script to generate merkle root for wstHYPE looping strategy operations
 * @dev Run with: source .env && forge script script/MerkleRootCreation/HyperLiquid/CreateWstHypeLoopingMerkleRoot.s.sol:CreateWstHypeLoopingMerkleRootScript --rpc-url $HYPERLIQUID_RPC_URL
 */
contract CreateWstHypeLoopingMerkleRootScript is Script, MerkleTreeHelper {
    using FixedPointMathLib for uint256;

    // Chain name constant
    string constant HYPERLIQUID = "hyperliquid";

    function setUp() external {
        // Set the source chain name
        setSourceChainName(HYPERLIQUID);

        // Set actual Hyperliquid protocol addresses
        setAddress(false, HYPERLIQUID, "wHYPE", 0x5555555555555555555555555555555555555555);
        setAddress(false, HYPERLIQUID, "stHYPE", 0xfFaa4a3D97fE9107Cef8a3F48c069F577Ff76cC1);
        setAddress(false, HYPERLIQUID, "wstHYPE", 0x94e8396e0869c9F2200760aF0621aFd240E1CF38);
        setAddress(false, HYPERLIQUID, "overseer", 0xB96f07367e69e86d6e9C3F29215885104813eeAE);
        setAddress(false, HYPERLIQUID, "felixMarkets", 0x68e37dE8d93d3496ae143F2E900490f6280C57cD);
        
        // Felix market parameters (using mainnet values)
        setAddress(false, HYPERLIQUID, "felixOracle", 0xD767818Ef397e597810cF2Af6b440B1b66f0efD3);
        setAddress(false, HYPERLIQUID, "felixIrm", 0xD4a426F010986dCad727e8dd6eed44cA4A9b7483);
    }

    function run() external {
        console.log("=== Generating WstHYPE Looping Strategy Merkle Root ===");
        
        // Create leafs array with sufficient size for all operations
        ManageLeaf[] memory leafs = new ManageLeaf[](12);
        
        // Reset leaf index for proper indexing
        leafIndex = type(uint256).max;
        
        // Add all WstHYPE looping operation leafs using MerkleTreeHelper
        _addWstHypeLoopingLeafs(leafs);
        
        console.log("Total operations created:", leafs.length);
        
        // Generate merkle tree
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        bytes32 merkleRoot = manageTree[manageTree.length - 1][0];
        
        console.log("Generated Merkle Root:", vm.toString(merkleRoot));

        // Define output file path for deployment artifacts
        string memory filePath = "./leafs/HyperLiquid/WstHypeLoopingDeploymentLeafs.json";
        
        // Generate and save leafs to JSON file for audit trail
        _generateLeafs(filePath, leafs, merkleRoot, manageTree);
        
        console.log("Merkle tree saved to:", filePath);
    }

    function _printOperationSummary() internal pure {
        console.log("\n=== Operation Summary ===");
        console.log("LOOPING OPERATIONS (0-4):");
        console.log("  0. wHYPE withdraw (unwrap to HYPE)");
        console.log("  1. Overseer mint (HYPE -> stHYPE)");
        console.log("  2. wstHYPE approve Felix");
        console.log("  3. Felix supply collateral");
        console.log("  4. Felix borrow wHYPE");
        console.log("\nUNWINDING OPERATIONS (5-11):");
        console.log("  5. wHYPE approve Felix (for repayment)");
        console.log("  6. Felix repay");
        console.log("  7. Felix withdraw collateral");
        console.log("  8. stHYPE approve overseer");
        console.log("  9. Overseer burn and redeem");
        console.log("  10. wHYPE deposit (wrap HYPE)");
        console.log("  11. Overseer redeem (complete burn)");
        console.log("=========================\n");
    }
}