// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {TellerWithRemediation} from "src/base/Roles/TellerWithRemediation.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {WstHypeLoopingUManager} from "src/micro-managers/WstHypeLoopingUManager.sol";
import {HyperliquidDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/HyperliquidDecoderAndSanitizer.sol";
import {FelixDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/FelixVanillaDecoderAndSanitizer.sol";

// Rate Providers
contract StHypeRateProvider {
    address public immutable stHYPE;
    address public immutable overseer;
    
    constructor(address _stHYPE, address _overseer) {
        stHYPE = _stHYPE;
        overseer = _overseer;
    }
    
    function getRate() external view returns (uint256) {
        // stHYPE is 1:1 with HYPE (liquid staking derivative)
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

/**
 * @title Complete WstHYPE Looping Strategy Deployment
 * @notice Deploys the entire system: Vault, Teller, Accountant, Manager, Strategy, Decoders, and Rate Providers
 */
contract DeployWstHypeLoopingComplete is Script {
    // =============================== PROTOCOL ADDRESSES ===============================
    
    // Hyperliquid protocol contracts
    address public constant wHYPE = 0x5555555555555555555555555555555555555555;
    address public constant stHYPE = 0xfFaa4a3D97fE9107Cef8a3F48c069F577Ff76cC1;
    address public constant wstHYPE = 0x94e8396e0869c9F2200760aF0621aFd240E1CF38;
    address public constant HYPE = 0x2222222222222222222222222222222222222222; // Native token
    address public constant overseer = 0xB96f07367e69e86d6e9C3F29215885104813eeAE;
    address public constant felixMarkets = 0x68e37dE8d93d3496ae143F2E900490f6280C57cD; // Felix Vanilla
    
    // Felix market parameters
    address public constant felixOracle = 0xD767818Ef397e597810cF2Af6b440B1b66f0efD3;
    address public constant felixIrm = 0xD4a426F010986dCad727e8dd6eed44cA4A9b7483;
    uint256 public constant felixLltv = 860000000000000000; // 86%
    
    // =============================== ROLE CONSTANTS ===============================
    
    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 2;
    uint8 public constant MANAGER_INTERNAL_ROLE = 3;
    uint8 public constant ADMIN_ROLE = 4;
    
    // =============================== DEPLOYED CONTRACTS ===============================
    
    BoringVault public vault;
    ManagerWithMerkleVerification public manager;
    AccountantWithRateProviders public accountant;
    TellerWithRemediation public teller;
    WstHypeLoopingUManager public strategyManager;
    RolesAuthority public rolesAuthority;
    
    // Rate providers
    StHypeRateProvider public stHypeRateProvider;
    WstHypeRateProvider public wstHypeRateProvider;
    
    // Decoders
    HyperliquidDecoderAndSanitizer public hyperliquidDecoder;
    FelixDecoderAndSanitizer public felixDecoder;
    
    // Deployment configuration
    address public deployer;
    address public strategist;
    address public admin;
    
    function run() external {
        // Setup deployment addresses
        deployer = msg.sender;
        strategist = msg.sender; // Can be changed later via setStrategist()
        admin = msg.sender; // Can be changed later via setAdmin()
        
        vm.startBroadcast();
        
        console.log("=== STARTING WSTHYPE LOOPING STRATEGY DEPLOYMENT ===");
        console.log("Deployer:", deployer);
        
        // 1. Deploy Rate Providers
        _deployRateProviders();
        
        // 2. Deploy Core Infrastructure
        _deployCoreInfrastructure();
        
        // 3. Deploy Strategy Components
        _deployStrategyComponents();
        
        // 4. Setup Roles and Permissions
        _setupRolesAndPermissions();
        
        // 5. Configure Accountant with Rate Providers
        _configureAccountant();
        
        // 6. Configure Teller
        _configureTeller();
        
        // 7. Configure Vault
        _configureVault();
        
        // 8. Generate and Set Merkle Root (FIXED)
        _generateAndSetMerkleRoot();
        
        // 9. Final Configuration
        _finalConfiguration();
        
        // 10. Verification and Summary
        _verifyDeployment();
        
        console.log("=== DEPLOYMENT COMPLETED SUCCESSFULLY ===");
        
        vm.stopBroadcast();
    }
    
    function _deployRateProviders() internal {
        console.log("\n1. Deploying Rate Providers...");
        
        stHypeRateProvider = new StHypeRateProvider(stHYPE, overseer);
        wstHypeRateProvider = new WstHypeRateProvider(wstHYPE, stHYPE);
        
        console.log("StHype Rate Provider:", address(stHypeRateProvider));
        console.log("WstHype Rate Provider:", address(wstHypeRateProvider));
    }
    
    function _deployCoreInfrastructure() internal {
        console.log("\n2. Deploying Core Infrastructure...");
        
        // Deploy BoringVault
        vault = new BoringVault(
            deployer,
            "wstHYPE Looping Vault", 
            "wstHYPE-LOOP",
            18
        );
        
        // Deploy ManagerWithMerkleVerification
        manager = new ManagerWithMerkleVerification(
            deployer,
            address(vault),
            address(0) // No balancer vault for Hyperliquid
        );
        
        // Deploy AccountantWithRateProviders
        // need to look into this more and configure it properly
        accountant = new AccountantWithRateProviders(
            deployer,           // owner
            address(vault),     // vault
            deployer,           // feeAddress
            1e18,              // startingExchangeRate (1:1)
            wHYPE,             // base asset (wHYPE)
            10500,             // allowedExchangeRateChangeUpper (5% increase)
            9500,              // allowedExchangeRateChangeLower (5% decrease)
            24 hours,          // minimumUpdateDelayInSeconds
            50,                // managementFee (0.5%)
            1000               // performanceFee (10%)
        );
        
        // Deploy TellerWithRemediation
        teller = new TellerWithRemediation(
            deployer,
            address(vault),
            address(accountant),
            wHYPE  // native asset equivalent for Hyperliquid
        );
        
        // Deploy RolesAuthority
        rolesAuthority = new RolesAuthority(deployer, Authority(address(0)));
        
        console.log("BoringVault:", address(vault));
        console.log("Manager:", address(manager));
        console.log("Accountant:", address(accountant));
        console.log("Teller:", address(teller));
        console.log("RolesAuthority:", address(rolesAuthority));
    }
    
    function _deployStrategyComponents() internal {
        console.log("\n3. Deploying Strategy Components...");
        
        // Deploy Decoders
        hyperliquidDecoder = new HyperliquidDecoderAndSanitizer();
        felixDecoder = new FelixDecoderAndSanitizer();
        
        // Deploy Strategy Manager
        strategyManager = new WstHypeLoopingUManager(
            address(vault),
            address(manager),
            wHYPE,
            strategist,      // strategist address
            stHYPE,
            wstHYPE,
            overseer,
            felixMarkets,
            felixOracle,
            felixIrm,
            felixLltv
        );
        
        // Configure strategy manager with decoders
        strategyManager.setDecoders(
            address(hyperliquidDecoder), // For wHYPE/Overseer/ERC20
            address(felixDecoder)   // For Felix operations
        );
        
        console.log("Hyperliquid Decoder:", address(hyperliquidDecoder));
        console.log("Felix Decoder:", address(felixDecoder));
        console.log("Strategy Manager:", address(strategyManager));
    }
    
    function _setupRolesAndPermissions() internal {
        console.log("\n4. Setting up Roles and Permissions...");
        
        // Set authorities for all contracts
        vault.setAuthority(rolesAuthority);
        manager.setAuthority(rolesAuthority);
        accountant.setAuthority(rolesAuthority);
        teller.setAuthority(rolesAuthority);
        
        // Setup BoringVault capabilities
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(vault),
            vault.manage.selector,
            true
        );
        
        // Setup Manager capabilities
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(manager),
            manager.manageVaultWithMerkleVerification.selector,
            true
        );
        
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(manager),
            manager.setManageRoot.selector,
            true
        );
        
        // Setup Accountant capabilities
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(accountant),
            accountant.updateExchangeRate.selector,
            true
        );
        
        // Setup Teller capabilities
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(teller),
            teller.bulkDeposit.selector,
            true
        );
        
        // Grant roles to addresses
        rolesAuthority.setUserRole(deployer, ADMIN_ROLE, true);
        rolesAuthority.setUserRole(strategist, STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);
        
        console.log("Roles and permissions configured");
    }
    
    function _configureAccountant() internal {
        console.log("\n5. Configuring Accountant with Rate Providers...");
        
        // Set rate provider data for each asset
        accountant.setRateProviderData(
            ERC20(wHYPE), 
            true,        // isPricingAsset (base asset)
            address(0)   // no rate provider needed for base asset
        );
        
        accountant.setRateProviderData(
            ERC20(stHYPE),
            false,       // not pricing asset
            address(stHypeRateProvider)
        );
        
        accountant.setRateProviderData(
            ERC20(wstHYPE),
            false,       // not pricing asset  
            address(wstHypeRateProvider)
        );
        
        // Start the accountant
        accountant.updateExchangeRate(1e18);
        
        console.log("Accountant configured with rate providers");
    }
    
    function _configureTeller() internal {
        console.log("\n6. Configuring Teller...");
        
        // Configure deposit/withdrawal assets
        teller.updateAssetData(
            ERC20(wHYPE),
            true,  // allowDeposits
            true,  // allowWithdrawals 
            0      // shareLockPeriod
        );
        
        // Set share lock period
        teller.setShareLockPeriod(0); // No lock period, will change in production
        
        // Enable deposits and withdrawals
        teller.setIsPaused(false);
        
        console.log("Teller configured");
    }
    
    function _configureVault() internal {
        console.log("\n7. Configuring Vault...");
        
        // Set core components
        vault.setManager(address(manager));
        vault.setAccountant(address(accountant));
        vault.setTeller(address(teller));
        
        console.log("Vault configured");
    }
    
    function _generateAndSetMerkleRoot() internal {
        console.log("\n8. Generating and Setting Merkle Root...");
        
        // IMPORTANT: This needs to be done MANUALLY after deployment
        // The merkle root script needs the actual deployed addresses
        // Run: forge script script/MerkleRootCreation/Hyperliquid/CreateWstHypeLoopingMerkleRoot.s.sol --rpc-url $HYPERLIQUID_RPC_URL
        // Then call manager.setManageRoot(strategist, merkleRoot) with the generated root
        
        console.log("MANUAL STEP REQUIRED:");
        console.log("1. Update CreateWstHypeLoopingMerkleRoot.s.sol with these addresses:");
        console.log("   - boringVault:", address(vault));
        console.log("   - managerAddress:", address(manager));
        console.log("   - accountantAddress:", address(accountant));
        console.log("   - hyperliquidDecoder:", address(hyperliquidDecoder));
        console.log("   - felixDecoder:", address(felixDecoder));
        console.log("2. Run the merkle root generation script");
        console.log("3. Call manager.setManageRoot(strategist, merkleRoot)");
        console.log("   - Strategist address:", strategist);
    }
    
    function _finalConfiguration() internal {
        console.log("\n9. Final Configuration...");
        
        // Transfer ownership to admin if different from deployer
        if (admin != deployer) {
            vault.transferOwnership(admin);
            manager.transferOwnership(admin);
            accountant.transferOwnership(admin);
            teller.transferOwnership(admin);
            rolesAuthority.setOwner(admin);
            strategyManager.transferOwnership(admin);
            
            console.log("Ownership transferred to:", admin);
        }
        
        console.log("Final configuration completed");
    }
    
    function _verifyDeployment() internal view {
        console.log("\n10. Deployment Verification...");
        
        // Verify all contracts are deployed
        require(address(vault) != address(0), "Vault not deployed");
        require(address(manager) != address(0), "Manager not deployed");
        require(address(accountant) != address(0), "Accountant not deployed");
        require(address(teller) != address(0), "Teller not deployed");
        require(address(strategyManager) != address(0), "Strategy Manager not deployed");
        require(address(rolesAuthority) != address(0), "Roles Authority not deployed");
        require(address(stHypeRateProvider) != address(0), "StHype Rate Provider not deployed");
        require(address(wstHypeRateProvider) != address(0), "WstHype Rate Provider not deployed");
        require(address(hyperliquidDecoder) != address(0), "Hyperliquid Decoder not deployed");
        require(address(felixDecoder) != address(0), "Felix Decoder not deployed");
        
        // Verify configurations
        require(vault.manager() == address(manager), "Vault manager not set");
        require(vault.accountant() == address(accountant), "Vault accountant not set");
        require(vault.teller() == address(teller), "Vault teller not set");
        require(accountant.baseAsset() == wHYPE, "Accountant base asset incorrect");
        
        console.log(" All verifications passed");
        
        // Print final addresses
        console.log("\n=== FINAL DEPLOYMENT ADDRESSES ===");
        console.log("BoringVault:", address(vault));
        console.log("Manager:", address(manager));
        console.log("Accountant:", address(accountant));
        console.log("Teller:", address(teller));
        console.log("Strategy Manager:", address(strategyManager));
        console.log("Roles Authority:", address(rolesAuthority));
        console.log("StHype Rate Provider:", address(stHypeRateProvider));
        console.log("WstHype Rate Provider:", address(wstHypeRateProvider));
        console.log("Hyperliquid Decoder:", address(hyperliquidDecoder));
        console.log("Felix Decoder:", address(felixDecoder));
        
        console.log("\n=== NEXT STEPS ===");
        console.log("1. Generate merkle root with actual deployed addresses");
        console.log("2. Set merkle root: manager.setManageRoot(", strategist, ", merkleRoot)");
        console.log("3. Users can deposit wHYPE via Teller");
        console.log("4. Strategist can execute looping via manager.manageVaultWithMerkleVerification()");
        console.log("5. Exchange rates updated via Accountant with Rate Providers");
    }
    
    // Helper functions to set specific strategist and admin addresses
    function setStrategist(address _strategist) external {
        strategist = _strategist;
    }
    
    function setAdmin(address _admin) external {
        admin = _admin;
    }
}