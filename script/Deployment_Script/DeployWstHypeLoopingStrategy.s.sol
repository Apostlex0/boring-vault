// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {WstHypeLoopingUManagerNew} from "src/micro-managers/WstHypeLoopingUManagerNew.sol";
import {HyperliquidDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/HyperLiquidDecoderAndSanitizer.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

/**
 * @title WstHYPE Looping Strategy Deployment
 */

// Rate Providers
contract StHypeRateProvider {
    address public immutable stHYPE;
    address public immutable overseer;

    constructor(address _stHYPE, address _overseer) {
        stHYPE = _stHYPE;
        overseer = _overseer;
    }

    function getRate() external view returns (uint256) {
        return 1e18;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }
}

contract WstHypeRateProvider {
    address public immutable wstHYPE;
    address public immutable stHYPE;

    constructor(address _wstHYPE, address _stHYPE) {
        wstHYPE = _wstHYPE;
        stHYPE = _stHYPE;
    }

    function getRate() external view returns (uint256) {
        // Calculate exchange rate: stHYPE backing per wstHYPE
        uint256 stHypeBalance = ERC20(stHYPE).balanceOf(wstHYPE);
        uint256 wstHypeSupply = ERC20(wstHYPE).totalSupply();

        if (wstHypeSupply == 0) return 1e18;
        return (stHypeBalance * 1e18) / wstHypeSupply;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }
}

contract DeployWstHypeLoopingStrategy is Script, MerkleTreeHelper {
    // =============================== PROTOCOL ADDRESSES ===============================

    // Hyperliquid protocol contracts (mainnet addresses)
    address public constant WHYPE = 0x5555555555555555555555555555555555555555;
    address public constant STHYPE = 0xfFaa4a3D97fE9107Cef8a3F48c069F577Ff76cC1;
    address public constant WSTHYPE =
        0x94e8396e0869c9F2200760aF0621aFd240E1CF38;
    address public constant OVERSEER =
        0xB96f07367e69e86d6e9C3F29215885104813eeAE;

    // Felix Vanilla addresses
    address public constant FELIX_MARKETS =
        0x68e37dE8d93d3496ae143F2E900490f6280C57cD;
    address public constant FELIX_ORACLE =
        0xD767818Ef397e597810cF2Af6b440B1b66f0efD3;
    address public constant FELIX_IRM =
        0xD4a426F010986dCad727e8dd6eed44cA4A9b7483;
    uint256 public constant FELIX_LLTV = 860000000000000000; // 86%

    // =============================== ROLE CONSTANTS ===============================

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 2;
    uint8 public constant MANAGER_INTERNAL_ROLE = 3;
    uint8 public constant ADMIN_ROLE = 4;

    // =============================== DEPLOYED CONTRACTS ===============================

    RolesAuthority public rolesAuthority;
    BoringVault public vault;
    AccountantWithRateProviders public accountant;
    TellerWithMultiAssetSupport public teller;
    HyperliquidDecoderAndSanitizer public decoder;
    ManagerWithMerkleVerification public manager;
    WstHypeLoopingUManagerNew public strategyManager;

    // Rate providers
    StHypeRateProvider public stHypeRateProvider;
    WstHypeRateProvider public wstHypeRateProvider;

    // =============================== MAIN DEPLOYMENT FUNCTION ===============================

    function run() external {
        address deployer = msg.sender;

        vm.startBroadcast();

        console.log("=== STARTING WSTHYPE LOOPING STRATEGY DEPLOYMENT ===");
        console.log("Deployer:", deployer);

        // Phase 1. Deploy Rate Providers
        _deployRateProviders();

        // Phase 2: Deploy RolesAuthority
        _deployRolesAuthority(deployer);

        // Phase 3: Deploy Core Vault
        _deployVault(deployer);

        // Phase 4: Deploy Vault Roles
        _deployVaultRoles(deployer);

        // Phase 5: Deploy Security Layer
        _deploySecurityLayer(deployer);

        // Phase 6: Deploy Strategy Layer
        _deployStrategyLayer(deployer);

        // Phase 7: Configure Accountant and Teller
        _configureAccountant();
        _configureTeller();

        // Phase 8: Configure Roles and Permissions
        _configureRolesAndPermissions(deployer);

        // Phase 9: Generate Merkle Tree and Set Root
        _generateMerkleTreeAndSetRoot(deployer);

        // Final Configuration
        _finalConfiguration();

        console.log("=== DEPLOYMENT COMPLETED SUCCESSFULLY ===");

        vm.stopBroadcast();
    }

    // =============================== DEPLOYMENT PHASES ===============================

    function _deployRateProviders() internal {
        console.log("Phase 1. Deploying Rate Providers...");

        stHypeRateProvider = new StHypeRateProvider(STHYPE, OVERSEER);
        wstHypeRateProvider = new WstHypeRateProvider(WSTHYPE, STHYPE);

        console.log("StHype Rate Provider:", address(stHypeRateProvider));
        console.log("WstHype Rate Provider:", address(wstHypeRateProvider));
    }

    function _deployRolesAuthority(address deployer) internal {
        console.log("Phase 2: Deploying RolesAuthority...");

        rolesAuthority = new RolesAuthority(deployer, Authority(address(0)));

        console.log("  RolesAuthority:", address(rolesAuthority));
    }

    function _deployVault(address deployer) internal {
        console.log("Phase 3: Deploying Core Vault...");

        vault = new BoringVault(
            deployer, // owner
            "wstHYPE Looping Vault", // name
            "wstHYPE-LOOP", // symbol
            18 // decimals
        );

        console.log("  BoringVault:", address(vault));
    }

    function _deployVaultRoles(address deployer) internal {
        console.log("Phase 4: Deploying Vault Roles...");

        accountant = new AccountantWithRateProviders(
            deployer, // owner
            address(vault), // vault
            deployer, // payoutAddress
            1e18, // startingExchangeRate (1:1)
            WHYPE, // base asset (wHYPE)
            10500, // allowedExchangeRateChangeUpper (5% increase)
            9500, // allowedExchangeRateChangeLower (5% decrease)
            24 hours, // minimumUpdateDelayInSeconds
            50, // platformFee (0.5%)
            1000 // performanceFee (10%)
        );

        teller = new TellerWithMultiAssetSupport(
            deployer, // owner
            address(vault), // vault
            address(accountant), // accountant
            WHYPE // weth (using wHYPE as native equivalent)
        );

        console.log("  AccountantWithRateProviders:", address(accountant));
        console.log("  TellerWithMultiAssetSupport:", address(teller));
    }

    function _deploySecurityLayer(address deployer) internal {
        console.log("Phase 5: Deploying Security Layer...");

        decoder = new HyperliquidDecoderAndSanitizer();

        manager = new ManagerWithMerkleVerification(
            deployer, // owner
            address(vault), // vault
            address(0) // balancerVault for flash loan mechanism (not needed for Hyperliquid)
        );

        console.log("  HyperliquidDecoderAndSanitizer:", address(decoder));
        console.log("  ManagerWithMerkleVerification:", address(manager));
    }

    function _deployStrategyLayer(address deployer) internal {
        console.log("Phase 6: Deploying Strategy Layer...");

        strategyManager = new WstHypeLoopingUManagerNew(
            deployer, // owner
            address(manager), // manager
            address(vault), // boringVault
            address(accountant), // accountant (for rate provider access)
            WHYPE, // wHYPE
            STHYPE, // stHYPE
            WSTHYPE, // wstHYPE
            OVERSEER, // overseer
            FELIX_MARKETS, // felixMarkets
            FELIX_ORACLE, // felixOracle
            FELIX_IRM, // felixIrm
            FELIX_LLTV // felixLltv
        );

        strategyManager.setDecoder(address(decoder));

        console.log("  WstHypeLoopingUManagerNew:", address(strategyManager));
    }

        function _configureAccountant() internal {
        console.log("Phase 7: Configuring Accountant with Rate Providers...");

        // Set rate provider data for each asset
        accountant.setRateProviderData(
            ERC20(WHYPE),
            true, // isPricingAsset (base asset)
            address(0) // no rate provider needed for base asset
        );

        accountant.setRateProviderData(
            ERC20(STHYPE),
            false, // not pricing asset
            address(stHypeRateProvider)
        );

        accountant.setRateProviderData(
            ERC20(WSTHYPE),
            false, // not pricing asset
            address(wstHypeRateProvider)
        );

        console.log("Accountant configured with rate providers");
    }

    function _configureTeller() internal {
        console.log("Phase 7: Configuring Teller...");

        // Configure deposit/withdrawal assets
        teller.updateAssetData(
            ERC20(WHYPE),
            true, // allowDeposits
            true, // allowWithdrawals
            0 // shareLockPeriod
        );

        vault.setBeforeTransferHook(address(teller));

        console.log("Teller configured");
    }

    function _configureRolesAndPermissions(address deployer) internal {
        console.log("Phase 8: Configuring Roles and Permissions...");

        vault.setAuthority(rolesAuthority);
        manager.setAuthority(rolesAuthority);
        accountant.setAuthority(rolesAuthority);
        teller.setAuthority(rolesAuthority);
        strategyManager.setAuthority(rolesAuthority);

        // ================ VAULT PERMISSIONS ================

        // Manager contract can call vault.manage() - BOTH overloads
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(vault),
            bytes4(
                keccak256(abi.encodePacked("manage(address,bytes,uint256)"))
            ),
            true
        );

        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(vault),
            bytes4(
                keccak256(
                    abi.encodePacked("manage(address[],bytes[],uint256[])")
                )
            ),
            true
        );

        // Teller can mint shares via vault.enter()
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(vault),
            vault.enter.selector,
            true
        );

        // Teller can burn shares via vault.exit()
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(vault),
            vault.exit.selector,
            true
        );

        // ================ MANAGER PERMISSIONS ================

        // Strategy contracts can call manageVaultWithMerkleVerification
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(manager),
            manager.manageVaultWithMerkleVerification.selector,
            true
        );

        // Internal manager role (for flash loans, etc)
        rolesAuthority.setRoleCapability(
            MANAGER_INTERNAL_ROLE,
            address(manager),
            manager.manageVaultWithMerkleVerification.selector,
            true
        );

        // Admin can set merkle root
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(manager),
            manager.setManageRoot.selector,
            true
        );

        // Admin can pause/unpause
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(manager),
            manager.pause.selector,
            true
        );

        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(manager),
            manager.unpause.selector,
            true
        );

        // ================ ACCOUNTANT PERMISSIONS ================

        // Admin can configure rate providers
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(accountant),
            accountant.setRateProviderData.selector,
            true
        );

        // Admin can update exchange rates
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(accountant),
            accountant.updateExchangeRate.selector,
            true
        );

        // Admin can pause/unpause
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(accountant),
            accountant.pause.selector,
            true
        );

        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(accountant),
            accountant.unpause.selector,
            true
        );

        // Vault can claim fees
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(accountant),
            accountant.claimFees.selector,
            true
        );

        // ================ TELLER PERMISSIONS ================
        // Admin can configure assets
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(teller),
            teller.updateAssetData.selector,
            true
        );

        // Admin can pause/unpause
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(teller),
            teller.pause.selector,
            true
        );

        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(teller),
            teller.unpause.selector,
            true
        );

        // Strategist can do bulk operations
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(teller),
            teller.bulkDeposit.selector,
            true
        );

        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(teller),
            teller.bulkWithdraw.selector,
            true
        );

        // ================ STRATEGY MANAGER PERMISSIONS ================

        // Strategist can execute strategy
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(strategyManager),
            strategyManager.executeLoopingStrategy.selector,
            true
        );

        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(strategyManager),
            strategyManager.unwindPositions.selector,
            true
        );

        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(strategyManager),
            strategyManager.completeBurnRedemptions.selector,
            true
        );

        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(strategyManager),
            strategyManager.wrapHypeToWHype.selector,
            true
        );

        // Admin can set decoder
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(strategyManager),
            strategyManager.setDecoder.selector,
            true
        );

        // Grant roles to addresses
        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(deployer, STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(deployer, ADMIN_ROLE, true);

        // Give contracts their necessary roles
        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(
            address(strategyManager),
            STRATEGIST_ROLE,
            true
        );
        rolesAuthority.setUserRole(address(manager), MANAGER_INTERNAL_ROLE, true);

        console.log("Roles and permissions configured");
    }

    function _generateMerkleTreeAndSetRoot(address deployer) internal {
        console.log("Generating Merkle root for strategy operations...");

        // Set source chain name
        setSourceChainName("hyperliquid");

        // Set deployed contract addresses
        setAddress(true, "hyperliquid", "boringVault", address(vault));
        setAddress(
            true,
            "hyperliquid",
            "rawDataDecoderAndSanitizer",
            address(decoder)
        );
        setAddress(true, "hyperliquid", "managerAddress", address(manager));
        setAddress(
            true,
            "hyperliquid",
            "accountantAddress",
            address(accountant)
        );

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
        string
            memory filePath = "./leafs/HyperLiquid/WstHypeLoopingDeploymentLeafs.json";

        vm.createDir("./leafs/HyperLiquid", true);

        // Generate and save leafs to JSON file for audit trail
        _generateLeafs(filePath, leafs, merkleRoot, manageTree);

        console.log("Merkle tree saved to:", filePath);

        // Set the Merkle root in the manager
        manager.setManageRoot(deployer, merkleRoot);

        console.log(
            "Merkle root set successfully in ManagerWithMerkleVerification"
        );
    }

    function _finalConfiguration() internal {
        console.log("Phase 10: Final Configuration...");

        console.log("Final configuration completed");

        // Print deployment summary
        console.log("\\n=== DEPLOYMENT ADDRESSES ===");
        console.log("RolesAuthority:", address(rolesAuthority));
        console.log("BoringVault:", address(vault));
        console.log("AccountantWithRateProviders:", address(accountant));
        console.log("TellerWithMultiAssetSupport:", address(teller));
        console.log("HyperliquidDecoderAndSanitizer:", address(decoder));
        console.log("ManagerWithMerkleVerification:", address(manager));
        console.log("WstHypeLoopingUManagerNew:", address(strategyManager));
    }

}
