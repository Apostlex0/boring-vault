// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import "forge-std/Script.sol";

/**
 *  source .env && forge script script/MerkleRootCreation/Sonic/CreateStakedSonicUSDMerkleRoot.s.sol:CreateStakedSonicUSDMerkleRoot --rpc-url $SONIC_MAINNET_RPC_URL
 */
contract CreateStakedSonicUSDMerkleRoot is Script, MerkleTreeHelper {
    using FixedPointMathLib for uint256;

    address public boringVault = 0x4D85bA8c3918359c78Ed09581E5bc7578ba932ba;
    address public managerAddress = 0x5F7f5205A3E7c63c3bd287EecBe7879687D4c698;
    address public accountantAddress = 0x13cCc810DfaA6B71957F2b87060aFE17e6EB8034;
    address public rawDataDecoderAndSanitizer = 0x476465EABBc951Bd9506a1237EB8b64286a0B461;

    function setUp() external {}

    /**
     * @notice Uncomment which script you want to run.
     */
    function run() external {
        /// NOTE Only have 1 function run at a time, otherwise the merkle root created will be wrong.
        generateAdminStrategistMerkleRoot();
    }

    function generateAdminStrategistMerkleRoot() public {
        setSourceChainName(sonicMainnet);
        setAddress(false, sonicMainnet, "boringVault", boringVault);
        setAddress(false, sonicMainnet, "managerAddress", managerAddress);
        setAddress(false, sonicMainnet, "accountantAddress", accountantAddress);
        setAddress(false, sonicMainnet, "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizer);

        ManageLeaf[] memory leafs = new ManageLeaf[](256);

        // ========================== Fee Claiming ==========================
        ERC20[] memory feeAssets = new ERC20[](2);
        feeAssets[0] = getERC20(sourceChain, "USDC");
        feeAssets[1] = getERC20(sourceChain, "scUSD");
        _addLeafsForFeeClaiming(leafs, getAddress(sourceChain, "accountantAddress"), feeAssets, true);

        // ========================== Beets ==========================
        _addBalancerLeafs(
            leafs, getBytes32(sourceChain, "scUSD_USDC_PoolId"), getAddress(sourceChain, "scUSD_USDC_gauge")
        );
        _addBalancerSwapLeafs(leafs, getBytes32(sourceChain, "USDC_stS_PoolId")); //USDC, stS
        _addBalancerSwapLeafs(leafs, getBytes32(sourceChain, "USDC_wS_PoolId")); //USDC, wS
        _addBalancerSwapLeafs(leafs, getBytes32(sourceChain, "stS_BEETS_PoolId")); //stS, BEETS (swap BEETS for stS, then USDC, swap function leaves only support 2 token pools atm)

        // ========================== Odos ==========================
        
        address[] memory tokens = new address[](5);   
        tokens[0] = getAddress(sourceChain, "USDC"); 
        tokens[1] = getAddress(sourceChain, "stS"); 
        tokens[2] = getAddress(sourceChain, "wS"); 
        tokens[3] = getAddress(sourceChain, "scUSD"); 
        tokens[4] = getAddress(sourceChain, "BEETS");
        SwapKind[] memory kind = new SwapKind[](5);
        kind[0] = SwapKind.BuyAndSell;
        kind[1] = SwapKind.BuyAndSell;
        kind[2] = SwapKind.BuyAndSell;
        kind[3] = SwapKind.BuyAndSell;
        kind[4] = SwapKind.BuyAndSell;
        _addOdosSwapLeafs(leafs, tokens, kind); 
        
        // ========================== Teller ==========================
        ERC20[] memory tellerAssets = new ERC20[](1);
        tellerAssets[0] = getERC20(sourceChain, "USDC");
        _addTellerLeafs(leafs, getAddress(sourceChain, "scUSDTeller"), tellerAssets, false);

        // ========================== Silo ==========================

        _addSiloV2Leafs(leafs, getAddress(sourceChain, "silo_wS_USDC_id8_config"));
        _addSiloV2Leafs(leafs, getAddress(sourceChain, "silo_wS_USDC_id20_config"));
        _addSiloV2Leafs(leafs, getAddress(sourceChain, "silo_USDC_wstkscUSD_id23_config"));

        // ========================== Curve =========================

        _addCurveLeafs(
            leafs,
            getAddress(sourceChain, "curve_USDC_scUSD_pool"),
            2,
            getAddress(sourceChain, "curve_USDC_scUSD_gauge")
        );
        _addLeafsForCurveSwapping(leafs, getAddress(sourceChain, "curve_USDC_scUSD_pool"));

        // ========================== Euler =========================

        ERC4626[] memory depositVaults = new ERC4626[](2);
        depositVaults[0] = ERC4626(getAddress(sourceChain, "euler_scUSD_MEV"));
        depositVaults[1] = ERC4626(getAddress(sourceChain, "euler_USDC_MEV"));

        address[] memory subaccounts = new address[](1);
        subaccounts[0] = address(boringVault);

        _addEulerDepositLeafs(leafs, depositVaults, subaccounts);

        // ========================== Native =========================
        _addNativeLeafs(leafs, getAddress(sourceChain, "wS"));

         // ========================== Merkl =========================
        ERC20[] memory tokensToClaim = new ERC20[](2);
        tokensToClaim[0] = getERC20(sourceChain, "rEUL");
        tokensToClaim[1] = getERC20(sourceChain, "wS");
        _addMerklLeafs(leafs, getAddress(sourceChain, "merklDistributor"), getAddress(sourceChain, "dev1Address"), tokensToClaim);

        // ========================== Verify =========================

        _verifyDecoderImplementsLeafsFunctionSelectors(leafs);

        string memory filePath = "./leafs/Sonic/StakedSonicUSDStrategistLeafs.json";

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        _generateLeafs(filePath, leafs, manageTree[manageTree.length - 1][0], manageTree);
    }
}
