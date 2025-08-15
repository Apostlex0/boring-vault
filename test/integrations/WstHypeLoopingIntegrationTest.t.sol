// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC20 as OZToken} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {BoringVault} from "src/base/BoringVault.sol";
import {DecoderCustomTypes} from "src/interfaces/DecoderCustomTypes.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {WstHypeLoopingUManagerNew} from "src/micro-managers/WstHypeLoopingUManagerNew.sol";
import {HyperliquidDecoderAndSanitizer} from "src/base/DecodersAndSanitizers/HyperLiquidDecoderAndSanitizer.sol";

import {MerkleTreeHelper} from "test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

// Import the proper interfaces
import {IFelix, IOverseer, IstHYPE, IwstHYPE, IWHYPE} from "src/interfaces/Hyperliquidinterfaces.sol";

contract WstHypeLoopingIntegrationTest is Test, MerkleTreeHelper {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    // ========================================= STATE VARIABLES =========================================

    // Core contracts
    ManagerWithMerkleVerification public manager;
    BoringVault public boringVault;
    AccountantWithRateProviders public accountant;
    TellerWithMultiAssetSupport public teller;
    WstHypeLoopingUManagerNew public strategyManager;
    RolesAuthority public rolesAuthority;
    
    // Unified decoder for ALL operations (including Felix)
    HyperliquidDecoderAndSanitizer public hyperliquidDecoder;
    address public rawDataDecoderAndSanitizer;

    // Role constants
    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 2;
    uint8 public constant MANAGER_INTERNAL_ROLE = 3;
    uint8 public constant ADMIN_ROLE = 4;
    uint8 public constant MINTER_ROLE = 5;
    uint8 public constant BURNER_ROLE = 6;

    // Protocol addresses (using mainnet Felix market params as specified)
    address public wHYPE;
    address public stHYPE;
    address public wstHYPE;
    address public constant HYPE = address(0); // Native token
    address public overseer;
    address public felixMarkets;
    address public felixOracle = 0xD767818Ef397e597810cF2Af6b440B1b66f0efD3; // Mainnet params
    address public felixIrm = 0xD4a426F010986dCad727e8dd6eed44cA4A9b7483;    // Mainnet params
    uint256 public felixLltv = 860000000000000000; // 86% - Mainnet params
    
    // Test addresses
    address public user1 = address(0x1001);
    address public strategist = address(0x2001);
    address public admin = address(0x3001);

    // Test amounts
    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint256 public constant DEPOSIT_AMOUNT = 100e18;
    uint256 public constant LOOP_AMOUNT = 50e18;
    
    // Mock contracts
    MockWHYPE public mockWHYPE;
    MockStHYPE public mockStHYPE;
    MockWstHYPE public mockWstHYPE;
    MockOverseer public mockOverseer;
    MockFelix public mockFelix;

    // Burn tracking for tests
    mapping(uint256 => BurnRequest) public burnRequests;
    uint256 public nextBurnId = 1;
    
    struct BurnRequest {
        address to;
        uint256 amount;
        uint256 timestamp;
        bool redeemed;
    }

    // ========================================= SETUP =========================================

    function setUp() external {
        // Set source chain for MerkleTreeHelper
        setSourceChainName("hyperliquid");
        
        _deployMockContracts();
        _deployCoreSystem();
        _setupRoles();
        _setupMockBalances();
    }

    function _deployMockContracts() internal {
        // Deploy mock protocol contracts
        mockWHYPE = new MockWHYPE();
        mockStHYPE = new MockStHYPE();
        mockWstHYPE = new MockWstHYPE(address(mockStHYPE));
        mockOverseer = new MockOverseer(address(mockStHYPE));
        mockFelix = new MockFelix();
        
        // Set addresses
        wHYPE = address(mockWHYPE);
        stHYPE = address(mockStHYPE);
        wstHYPE = address(mockWstHYPE);
        overseer = address(mockOverseer);
        felixMarkets = address(mockFelix);
        
        // Set addresses in ChainValues for MerkleTreeHelper
        setAddress(true, "hyperliquid", "wHYPE", wHYPE);
        setAddress(true, "hyperliquid", "stHYPE", stHYPE);
        setAddress(true, "hyperliquid", "wstHYPE", wstHYPE);
        setAddress(true, "hyperliquid", "overseer", overseer);
        setAddress(true, "hyperliquid", "felixMarkets", felixMarkets);
        setAddress(true, "hyperliquid", "felixOracle", felixOracle);
        setAddress(true, "hyperliquid", "felixIrm", felixIrm);
    }

    function _deployCoreSystem() internal {
        // Deploy BoringVault
        boringVault = new BoringVault(address(this), "WstHYPE Looping Vault", "wstHYPE-LOOP", 18);
        
        // Deploy ManagerWithMerkleVerification  
        manager = new ManagerWithMerkleVerification(
            address(this),
            address(boringVault),
            address(0) // No balancer vault needed
        );
        
        // Deploy AccountantWithRateProviders (needed for strategy manager)
        accountant = new AccountantWithRateProviders(
            address(this),      // owner
            address(boringVault), // vault
            address(this),      // payoutAddress
            1e18,              // startingExchangeRate (1:1)
            wHYPE,             // base asset (wHYPE)
            10500,             // allowedExchangeRateChangeUpper (5% increase)
            9500,              // allowedExchangeRateChangeLower (5% decrease)
            24 hours,          // minimumUpdateDelayInSeconds
            50,                // platformFee (0.5%)
            1000               // performanceFee (10%)
        );
        
        // Deploy unified decoder for ALL operations
        hyperliquidDecoder = new HyperliquidDecoderAndSanitizer();
        rawDataDecoderAndSanitizer = address(hyperliquidDecoder);
        
        // Deploy strategy manager
        strategyManager = new WstHypeLoopingUManagerNew(
            address(this),      // owner
            address(manager),   // manager
            address(boringVault), // boringVault
            address(accountant), // accountant (for rate provider access)
            wHYPE,
            stHYPE,
            wstHYPE,
            overseer,
            felixMarkets,
            felixOracle,
            felixIrm,
            felixLltv
        );
        
        // Set decoder in strategy manager
        strategyManager.setDecoder(rawDataDecoderAndSanitizer);
        
        // Set addresses in ChainValues for MerkleTreeHelper
        setAddress(true, "hyperliquid", "boringVault", address(boringVault));
        setAddress(true, "hyperliquid", "manager", address(manager));
        setAddress(true, "hyperliquid", "rawDataDecoderAndSanitizer", rawDataDecoderAndSanitizer);
    }

    function _setupRoles() internal {
        // Deploy RolesAuthority
        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        
        // Set authorities
        boringVault.setAuthority(rolesAuthority);
        manager.setAuthority(rolesAuthority);
        accountant.setAuthority(rolesAuthority);
        strategyManager.setAuthority(rolesAuthority);
        
        // Setup BoringVault role capabilities
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(boringVault),
            bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)"))),
            true
        );
        
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(boringVault),
            bytes4(keccak256(abi.encodePacked("manage(address[],bytes[],uint256[])"))),
            true
        );
        
        // Setup Manager role capabilities
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(manager),
            ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
            true
        );
        
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(manager),
            ManagerWithMerkleVerification.setManageRoot.selector,
            true
        );
        
        // Setup Strategy Manager role capabilities
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(strategyManager),
            WstHypeLoopingUManagerNew.executeLoopingStrategy.selector,
            true
        );
        
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(strategyManager),
            WstHypeLoopingUManagerNew.unwindPositions.selector,
            true
        );
        
        // Grant roles to addresses
        rolesAuthority.setUserRole(address(this), ADMIN_ROLE, true);
        rolesAuthority.setUserRole(address(this), STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(strategist, STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(admin, ADMIN_ROLE, true);
    }

    function _setupMockBalances() internal {
        // Setup mock exchange rates FIRST
        mockWstHYPE.setExchangeRate(1.1e18); // 1 wstHYPE = 1.1 stHYPE
        mockOverseer.setExchangeRate(1.05e18); // 1 stHYPE = 1.05 HYPE
        
        // Give test accounts initial balances
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(address(boringVault), INITIAL_BALANCE * 3); // Extra for operations
        
        // Use MockWHYPE.deposit() to properly mint wHYPE tokens
        vm.prank(user1);
        MockWHYPE(payable(wHYPE)).deposit{value: INITIAL_BALANCE}();
        
        vm.prank(address(boringVault));
        MockWHYPE(payable(wHYPE)).deposit{value: INITIAL_BALANCE}();
        
        // Give MockWHYPE contract wHYPE balance for withdrawals
        vm.deal(address(mockWHYPE), INITIAL_BALANCE * 2);
        
        // Set stHYPE balance for dual interface
        deal(stHYPE, address(boringVault), INITIAL_BALANCE);
        
        // Felix needs wHYPE to lend
        vm.deal(address(mockFelix), INITIAL_BALANCE * 11);
        vm.prank(address(mockFelix));
        MockWHYPE(payable(wHYPE)).deposit{value: INITIAL_BALANCE * 10}();
        
        // Fund MockOverseer with native HYPE for burn redemptions
        vm.deal(address(mockOverseer), INITIAL_BALANCE * 2);
    }

    // ========================================= CORE TEST FUNCTIONS =========================================

    function testBasicLoopingFlow() external {
        _executeBasicLoopingFlow();
        
        // Verify the strategy executed successfully
        assertGt(mockFelix.getCollateralBalance(address(boringVault)), 0, "No collateral supplied to Felix");
        assertGt(mockFelix.getDebtBalance(address(boringVault)), 0, "No debt borrowed from Felix");
        
        console.log("Looping strategy executed successfully");
    }

    function _executeBasicLoopingFlow() internal {
        uint256 initialAmount = LOOP_AMOUNT;
        
        // Verify initial balances
        uint256 initialWHYPE = ERC20(wHYPE).balanceOf(address(boringVault));
        assertGt(initialWHYPE, initialAmount, "Insufficient wHYPE balance for test");
        
        // Get all operation leaves from centralized function
        ManageLeaf[] memory allLeafs = _createAllOperationLeafs();
        
        // Select looping operations (indices 0-4)
        ManageLeaf[] memory leafs = new ManageLeaf[](5);
        leafs[0] = allLeafs[0];  // wHYPE withdraw
        leafs[1] = allLeafs[1];  // Overseer mint
        leafs[2] = allLeafs[2];  // wstHYPE approve Felix
        leafs[3] = allLeafs[3];  // Felix supply collateral
        leafs[4] = allLeafs[4];  // Felix borrow
        
        // Create Felix market params for calldata construction
        IFelix.MarketParams memory params = IFelix.MarketParams({
            loanToken: wHYPE,
            collateralToken: wstHYPE,
            oracle: felixOracle,
            irm: felixIrm,
            lltv: felixLltv
        });
        
        // Generate tree and set root
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);
        
        // Execute COMPLETE LOOPING STRATEGY
        ManageLeaf[] memory manageLeafs = new ManageLeaf[](5);
        manageLeafs[0] = leafs[0]; // wHYPE withdraw
        manageLeafs[1] = leafs[1]; // overseer mint
        manageLeafs[2] = leafs[2]; // wstHYPE approve Felix
        manageLeafs[3] = leafs[3]; // Felix supply collateral
        manageLeafs[4] = leafs[4]; // Felix borrow
        
        bytes32[][] memory manageProofs = _getProofsUsingTree(manageLeafs, manageTree);
        
        address[] memory targets = new address[](5);
        bytes[] memory calldatas = new bytes[](5);
        uint256[] memory values = new uint256[](5);
        address[] memory decoders = new address[](5);
        
        // Build targets and decoders
        targets[0] = wHYPE;
        targets[1] = overseer;
        targets[2] = wstHYPE;
        targets[3] = felixMarkets;
        targets[4] = felixMarkets;
        
        for (uint i = 0; i < 5; i++) {
            decoders[i] = rawDataDecoderAndSanitizer;
        }
        
        // Values: only overseer.mint() requires native HYPE value
        values[0] = 0;
        values[1] = initialAmount; // overseer mint needs HYPE value
        values[2] = 0;
        values[3] = 0;
        values[4] = 0;
        
        // Build calldatas using encodeCall
        calldatas[0] = abi.encodeCall(IWHYPE.withdraw, (initialAmount));
        calldatas[1] = abi.encodeWithSignature("mint(address)", address(boringVault));
        calldatas[2] = abi.encodeCall(IwstHYPE.approve, (felixMarkets, initialAmount));
        calldatas[3] = abi.encodeCall(IFelix.supplyCollateral, (params, initialAmount, address(boringVault), ""));
        calldatas[4] = abi.encodeCall(IFelix.borrow, (params, initialAmount * 8000 / 10000, 0, address(boringVault), address(boringVault)));
        
        console.log("=== EXECUTING COMPLETE WSHYPE LOOPING STRATEGY ===");
        
        // Execute complete strategy loop
        manager.manageVaultWithMerkleVerification(manageProofs, decoders, targets, calldatas, values);
        
        console.log("Looping strategy executed successfully");
    }

    function testUnwindPosition() external {
        // First setup a position to unwind
        _executeBasicLoopingFlow();
        
        uint256 initialCollateral = mockFelix.getCollateralBalance(address(boringVault));
        uint256 initialDebt = mockFelix.getDebtBalance(address(boringVault));
        
        assertGt(initialCollateral, 0, "No position to unwind");
        assertGt(initialDebt, 0, "No debt to repay");
        
        // Get all operation leaves
        ManageLeaf[] memory allLeafs = _createAllOperationLeafs();
        
        // Select unwinding operations (indices 5-10)
        ManageLeaf[] memory leafs = new ManageLeaf[](6);
        leafs[0] = allLeafs[5];  // wHYPE approve Felix
        leafs[1] = allLeafs[6];  // Felix repay
        leafs[2] = allLeafs[7];  // Felix withdraw collateral
        leafs[3] = allLeafs[8];  // stHYPE approve overseer
        leafs[4] = allLeafs[9];  // Overseer burnAndRedeemIfPossible
        leafs[5] = allLeafs[10]; // wHYPE deposit
        
        // Create Felix market params
        IFelix.MarketParams memory params = IFelix.MarketParams({
            loanToken: wHYPE,
            collateralToken: wstHYPE,
            oracle: felixOracle,
            irm: felixIrm,
            lltv: felixLltv
        });
        
        // Generate tree and set root
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);
        
        // Execute all 6 unwinding operations
        ManageLeaf[] memory selectedLeafs = new ManageLeaf[](6);
        for (uint i = 0; i < 6; i++) {
            selectedLeafs[i] = leafs[i];
        }
        
        bytes32[][] memory proofs = _getProofsUsingTree(selectedLeafs, manageTree);
        
        // Prepare execution data
        address[] memory targets = new address[](6);
        bytes[] memory calldatas = new bytes[](6);
        uint256[] memory values = new uint256[](6);
        address[] memory decoders = new address[](6);
        
        // Build targets and decoders
        targets[0] = wHYPE;
        targets[1] = felixMarkets;
        targets[2] = felixMarkets;
        targets[3] = stHYPE;
        targets[4] = overseer;
        targets[5] = wHYPE;
        
        for (uint i = 0; i < 6; i++) {
            decoders[i] = rawDataDecoderAndSanitizer;
        }
        
        // Calculate amounts for burn and deposit
        uint256 stHypeToBurn = initialCollateral * mockWstHYPE.exchangeRate() / 1e18;
        uint256 hypeFromBurn = stHypeToBurn * mockOverseer.exchangeRate() / 1e18;
        
        // Values: only wHYPE deposit requires native value
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        values[3] = 0;
        values[4] = 0;
        values[5] = hypeFromBurn; // wHYPE deposit needs HYPE
        
        // Build calldatas using encodeCall
        calldatas[0] = abi.encodeCall(IWHYPE.approve, (felixMarkets, initialDebt));
        calldatas[1] = abi.encodeCall(IFelix.repay, (params, initialDebt, 0, address(boringVault), ""));
        calldatas[2] = abi.encodeCall(IFelix.withdrawCollateral, (params, initialCollateral, address(boringVault), address(boringVault)));
        calldatas[3] = abi.encodeCall(IstHYPE.approve, (overseer, stHypeToBurn));
        calldatas[4] = abi.encodeCall(IOverseer.burnAndRedeemIfPossible, (address(boringVault), stHypeToBurn, ""));
        calldatas[5] = abi.encodeCall(IWHYPE.deposit, ());
        
        console.log("=== EXECUTING UNWINDING STRATEGY ===");
        
        // Execute all 6 unwinding operations
        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, calldatas, values);
        
        // Verify position was unwound
        assertEq(mockFelix.getCollateralBalance(address(boringVault)), 0, "Collateral not fully withdrawn");
        assertEq(mockFelix.getDebtBalance(address(boringVault)), 0, "Debt not fully repaid");
        
        console.log("Position unwound successfully");
    }

    function testBurnWithDelayedRedemption() external {
        // Setup position
        _executeBasicLoopingFlow();
        
        uint256 collateral = mockFelix.getCollateralBalance(address(boringVault));
        uint256 debt = mockFelix.getDebtBalance(address(boringVault));
        
        // Set overseer to have limited instant redeemable amount
        mockOverseer.setMaxRedeemable(10e18); // Only 10 tokens instantly redeemable
        
        // Start unwinding with large burn amount
        uint256 burnAmount = 50e18; // Larger than maxRedeemable
        
        // Execute partial unwind with burn request
        _executeUnwindWithBurnRequest(debt, collateral, burnAmount);
        
        // Check that burn ID was created
        uint256 burnId = mockOverseer.lastBurnId();
        assertGt(burnId, 0, "No burn ID created");
        
        // Simulate time passing for burn to be ready
        vm.warp(block.timestamp + 1 days);
        mockOverseer.setBurnRedeemable(burnId, true);
        
        // Now complete the redemption
        _completeDelayedRedemption(burnId);
        
        console.log("Burn with delayed redemption completed successfully");
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _executeUnwindWithBurnRequest(uint256 debtAmount, uint256 collateralAmount, uint256 burnAmount) internal {
        // This simulates unwinding when burn amount exceeds maxRedeemable
        ManageLeaf[] memory allLeafs = _createAllOperationLeafs();
        
        // Only execute up to burn (not including final deposit since we're waiting for redemption)
        ManageLeaf[] memory leafs = new ManageLeaf[](5);
        leafs[0] = allLeafs[5];  // wHYPE approve Felix
        leafs[1] = allLeafs[6];  // Felix repay
        leafs[2] = allLeafs[7];  // Felix withdraw collateral
        leafs[3] = allLeafs[8];  // stHYPE approve overseer
        leafs[4] = allLeafs[9];  // Overseer burnAndRedeemIfPossible
        
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);
        
        ManageLeaf[] memory selectedLeafs = new ManageLeaf[](5);
        for (uint i = 0; i < 5; i++) {
            selectedLeafs[i] = leafs[i];
        }
        
        bytes32[][] memory proofs = _getProofsUsingTree(selectedLeafs, manageTree);
        
        address[] memory targets = new address[](5);
        bytes[] memory calldatas = new bytes[](5);
        uint256[] memory values = new uint256[](5);
        address[] memory decoders = new address[](5);
        
        IFelix.MarketParams memory params = IFelix.MarketParams({
            loanToken: wHYPE,
            collateralToken: wstHYPE,
            oracle: felixOracle,
            irm: felixIrm,
            lltv: felixLltv
        });
        
        targets[0] = wHYPE;
        targets[1] = felixMarkets;
        targets[2] = felixMarkets;
        targets[3] = stHYPE;
        targets[4] = overseer;
        
        for (uint i = 0; i < 5; i++) {
            decoders[i] = rawDataDecoderAndSanitizer;
        }
        
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        values[3] = 0;
        values[4] = 0;
        
        calldatas[0] = abi.encodeCall(IWHYPE.approve, (felixMarkets, debtAmount));
        calldatas[1] = abi.encodeCall(IFelix.repay, (params, debtAmount, 0, address(boringVault), ""));
        calldatas[2] = abi.encodeCall(IFelix.withdrawCollateral, (params, collateralAmount, address(boringVault), address(boringVault)));
        calldatas[3] = abi.encodeCall(IstHYPE.approve, (overseer, burnAmount));
        calldatas[4] = abi.encodeCall(IOverseer.burnAndRedeemIfPossible, (address(boringVault), burnAmount, ""));
        
        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, calldatas, values);
    }

    function _completeDelayedRedemption(uint256 burnId) internal {
        // Create leaf for redeem operation
        ManageLeaf[] memory leafs = new ManageLeaf[](1);
        leafs[0] = ManageLeaf(
            overseer,
            false,
            "redeem(uint256)",
            new address[](0),
            "Redeem pending burn",
            rawDataDecoderAndSanitizer
        );
        
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);
        
        ManageLeaf[] memory selectedLeafs = new ManageLeaf[](1);
        selectedLeafs[0] = leafs[0];
        
        bytes32[][] memory proofs = _getProofsUsingTree(selectedLeafs, manageTree);
        
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        address[] memory decoders = new address[](1);
        
        targets[0] = overseer;
        calldatas[0] = abi.encodeCall(IOverseer.redeem, (burnId));
        values[0] = 0;
        decoders[0] = rawDataDecoderAndSanitizer;
        
        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, calldatas, values);
    }

    function _createAllOperationLeafs() internal view returns (ManageLeaf[] memory) {
        ManageLeaf[] memory leafs = new ManageLeaf[](11);
        
        uint256 leafIndex = type(uint256).max;
        
        IFelix.MarketParams memory params = IFelix.MarketParams({
            loanToken: wHYPE,
            collateralToken: wstHYPE,
            oracle: felixOracle,
            irm: felixIrm,
            lltv: felixLltv
        });
        
        // ========== LOOPING OPERATIONS ==========
        // 0. wHYPE withdraw
        unchecked { leafIndex++; }
        leafs[leafIndex] = ManageLeaf(
            wHYPE,
            false,
            "withdraw(uint256)",
            new address[](0),
            "Withdraw wHYPE to get HYPE",
            rawDataDecoderAndSanitizer
        );
        
        // 1. Overseer mint
        unchecked { leafIndex++; }
        leafs[leafIndex] = ManageLeaf(
            overseer,
            true,  // canSendValue = true for native HYPE
            "mint(address)",
            new address[](1),
            "Mint stHYPE from overseer",
            rawDataDecoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = address(boringVault);
        
        // 2. wstHYPE approve Felix
        unchecked { leafIndex++; }
        leafs[leafIndex] = ManageLeaf(
            wstHYPE,
            false,
            "approve(address,uint256)",
            new address[](1),
            "Approve Felix to spend wstHYPE",
            rawDataDecoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = felixMarkets;
        
        // 3. Felix supply collateral
        unchecked { leafIndex++; }
        leafs[leafIndex] = ManageLeaf(
            felixMarkets,
            false,
            "supplyCollateral((address,address,address,address,uint256),uint256,address,bytes)",
            new address[](5),
            "Felix supply collateral",
            rawDataDecoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = params.loanToken;
        leafs[leafIndex].argumentAddresses[1] = params.collateralToken;
        leafs[leafIndex].argumentAddresses[2] = params.oracle;
        leafs[leafIndex].argumentAddresses[3] = params.irm;
        leafs[leafIndex].argumentAddresses[4] = address(boringVault);
        
        // 4. Felix borrow
        unchecked { leafIndex++; }
        leafs[leafIndex] = ManageLeaf(
            felixMarkets,
            false,
            "borrow((address,address,address,address,uint256),uint256,uint256,address,address)",
            new address[](6),
            "Felix borrow wHYPE",
            rawDataDecoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = params.loanToken;
        leafs[leafIndex].argumentAddresses[1] = params.collateralToken;
        leafs[leafIndex].argumentAddresses[2] = params.oracle;
        leafs[leafIndex].argumentAddresses[3] = params.irm;
        leafs[leafIndex].argumentAddresses[4] = address(boringVault);
        leafs[leafIndex].argumentAddresses[5] = address(boringVault);
        
        // ========== UNWINDING OPERATIONS ==========
        // 5. wHYPE approve Felix (for repayment)
        unchecked { leafIndex++; }
        leafs[leafIndex] = ManageLeaf(
            wHYPE,
            false,
            "approve(address,uint256)",
            new address[](1),
            "Approve wHYPE for Felix repayment",
            rawDataDecoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = felixMarkets;
        
        // 6. Felix repay
        unchecked { leafIndex++; }
        leafs[leafIndex] = ManageLeaf(
            felixMarkets,
            false,
            "repay((address,address,address,address,uint256),uint256,uint256,address,bytes)",
            new address[](5),
            "Felix repay wHYPE",
            rawDataDecoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = params.loanToken;
        leafs[leafIndex].argumentAddresses[1] = params.collateralToken;
        leafs[leafIndex].argumentAddresses[2] = params.oracle;
        leafs[leafIndex].argumentAddresses[3] = params.irm;
        leafs[leafIndex].argumentAddresses[4] = address(boringVault);
        
        // 7. Felix withdraw collateral
        unchecked { leafIndex++; }
        leafs[leafIndex] = ManageLeaf(
            felixMarkets,
            false,
            "withdrawCollateral((address,address,address,address,uint256),uint256,address,address)",
            new address[](6),
            "Felix withdraw collateral",
            rawDataDecoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = params.loanToken;
        leafs[leafIndex].argumentAddresses[1] = params.collateralToken;
        leafs[leafIndex].argumentAddresses[2] = params.oracle;
        leafs[leafIndex].argumentAddresses[3] = params.irm;
        leafs[leafIndex].argumentAddresses[4] = address(boringVault);
        leafs[leafIndex].argumentAddresses[5] = address(boringVault);
        
        // 8. stHYPE approve overseer
        unchecked { leafIndex++; }
        leafs[leafIndex] = ManageLeaf(
            stHYPE,
            false,
            "approve(address,uint256)",
            new address[](1),
            "Approve stHYPE for Overseer burn",
            rawDataDecoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = overseer;
        
        // 9. Overseer burnAndRedeemIfPossible
        unchecked { leafIndex++; }
        leafs[leafIndex] = ManageLeaf(
            overseer,
            false,
            "burnAndRedeemIfPossible(address,uint256,string)",
            new address[](1),
            "Burn stHYPE and redeem HYPE",
            rawDataDecoderAndSanitizer
        );
        leafs[leafIndex].argumentAddresses[0] = address(boringVault);
        
        // 10. wHYPE deposit
        unchecked { leafIndex++; }
        leafs[leafIndex] = ManageLeaf(
            wHYPE,
            true,  // canSendValue = true for native HYPE deposit
            "deposit()",
            new address[](0),
            "Deposit HYPE to get wHYPE",
            rawDataDecoderAndSanitizer
        );
        
        // Trim to actual size
        ManageLeaf[] memory finalLeafs = new ManageLeaf[](leafIndex + 1);
        for (uint256 i = 0; i <= leafIndex; i++) {
            finalLeafs[i] = leafs[i];
        }
        
        return finalLeafs;
    }

    // ========================================= ACCESS CONTROL TESTS =========================================

    function testAccessControl() external {
        // Test that unauthorized users cannot execute strategy operations
        ManageLeaf[] memory allLeafs = _createAllOperationLeafs();
        
        // Generate merkle tree from ALL leafs
        bytes32[][] memory manageTree = _generateMerkleTree(allLeafs);
        
        // Set merkle root in manager
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);
        
        ManageLeaf[] memory selectedLeafs = new ManageLeaf[](1);
        selectedLeafs[0] = allLeafs[0]; // Simple wHYPE withdraw
        
        bytes32[][] memory proofs = _getProofsUsingTree(selectedLeafs, manageTree);
        
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        address[] memory decoders = new address[](1);
        
        targets[0] = wHYPE;
        calldatas[0] = abi.encodeCall(IWHYPE.withdraw, (1e18));
        values[0] = 0;
        decoders[0] = rawDataDecoderAndSanitizer;
        
        // Create an unauthorized user and test that they cannot execute
        address unauthorizedUser = address(0x999);
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, calldatas, values);
    }

    function testAccessControlAuthorized() external {
        // Test that authorized strategist can execute strategy operations
        ManageLeaf[] memory allLeafs = _createAllOperationLeafs();
        
        // Generate merkle tree from ALL leafs
        bytes32[][] memory manageTree = _generateMerkleTree(allLeafs);
        
        // Set merkle root in manager
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);
        
        ManageLeaf[] memory selectedLeafs = new ManageLeaf[](1);
        selectedLeafs[0] = allLeafs[0]; // Simple wHYPE withdraw
        
        bytes32[][] memory proofs = _getProofsUsingTree(selectedLeafs, manageTree);
        
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        address[] memory decoders = new address[](1);
        
        targets[0] = wHYPE;
        calldatas[0] = abi.encodeCall(IWHYPE.withdraw, (1e18));
        values[0] = 0;
        decoders[0] = rawDataDecoderAndSanitizer;
        
        // Test that the contract deployer (this test contract) can execute
        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, calldatas, values);
        
        console.log("Authorized execution successful");
    }

    function testPartialUnwindPosition() external {
        // First setup a position to unwind
        _executeBasicLoopingFlow();
        
        uint256 initialCollateral = mockFelix.getCollateralBalance(address(boringVault));
        uint256 initialDebt = mockFelix.getDebtBalance(address(boringVault));
        
        assertGt(initialCollateral, 0, "No position to unwind");
        assertGt(initialDebt, 0, "No debt to repay");
        
        console.log("=== PARTIAL UNWINDING TEST ===");
        console.log("Initial collateral:", initialCollateral);
        console.log("Initial debt:", initialDebt);
        
        // Partial repay: only 50% of debt
        uint256 partialRepayAmount = initialDebt / 2;
        
        _executePartialRepay(partialRepayAmount);
        
        // Verify partial repay worked
        uint256 finalDebt = mockFelix.getDebtBalance(address(boringVault));
        uint256 finalCollateral = mockFelix.getCollateralBalance(address(boringVault));
        
        console.log("Final debt after partial repay:", finalDebt);
        console.log("Final collateral (should be unchanged):", finalCollateral);
        
        // Assertions
        assertEq(finalDebt, initialDebt - partialRepayAmount, "Debt should be reduced by partial repay amount");
        assertEq(finalCollateral, initialCollateral, "Collateral should remain unchanged in partial repay");
        assertGt(finalDebt, 0, "Some debt should still remain after partial repay");
        
        console.log("Partial unwinding test completed successfully");
    }

    function testPartialCollateralWithdrawal() external {
        // First setup a position
        _executeBasicLoopingFlow();
        
        uint256 initialCollateral = mockFelix.getCollateralBalance(address(boringVault));
        uint256 initialDebt = mockFelix.getDebtBalance(address(boringVault));
        
        assertGt(initialCollateral, 0, "No collateral to withdraw");
        
        console.log("=== PARTIAL COLLATERAL WITHDRAWAL TEST ===");
        console.log("Initial collateral:", initialCollateral);
        console.log("Initial debt:", initialDebt);
        
        // Withdraw only 30% of collateral (keeping position healthy)
        uint256 partialWithdrawAmount = initialCollateral * 30 / 100;
        
        _executePartialWithdrawal(partialWithdrawAmount);
        
        // Verify partial withdrawal worked
        uint256 finalCollateral = mockFelix.getCollateralBalance(address(boringVault));
        uint256 finalDebt = mockFelix.getDebtBalance(address(boringVault));
        
        console.log("Final collateral after partial withdrawal:", finalCollateral);
        console.log("Final debt (should be unchanged):", finalDebt);
        
        // Assertions
        assertEq(finalCollateral, initialCollateral - partialWithdrawAmount, "Collateral should be reduced by withdrawal amount");
        assertEq(finalDebt, initialDebt, "Debt should remain unchanged in partial withdrawal");
        assertGt(finalCollateral, 0, "Some collateral should still remain after partial withdrawal");
        
        console.log("Partial collateral withdrawal test completed successfully");
    }

    function testMultipleLeverageLoops() external {
        console.log("=== MULTIPLE LEVERAGE LOOPS TEST ===");
        
        // Execute first loop
        _executeBasicLoopingFlow();
        
        uint256 firstLoopCollateral = mockFelix.getCollateralBalance(address(boringVault));
        uint256 firstLoopDebt = mockFelix.getDebtBalance(address(boringVault));
        
        console.log("After first loop - Collateral:", firstLoopCollateral);
        console.log("After first loop - Debt:", firstLoopDebt);
        
        // Execute second loop (leverage on existing position)
        _executeBasicLoopingFlow();
        
        uint256 secondLoopCollateral = mockFelix.getCollateralBalance(address(boringVault));
        uint256 secondLoopDebt = mockFelix.getDebtBalance(address(boringVault));
        
        console.log("After second loop - Collateral:", secondLoopCollateral);
        console.log("After second loop - Debt:", secondLoopDebt);
        
        // Verify leverage increased
        assertGt(secondLoopCollateral, firstLoopCollateral, "Collateral should increase after second loop");
        assertGt(secondLoopDebt, firstLoopDebt, "Debt should increase after second loop");
        
        // Execute third loop (maximum leverage as per UManager's LEVERAGE_RATIO)
        _executeBasicLoopingFlow();
        
        uint256 thirdLoopCollateral = mockFelix.getCollateralBalance(address(boringVault));
        uint256 thirdLoopDebt = mockFelix.getDebtBalance(address(boringVault));
        
        console.log("After third loop - Collateral:", thirdLoopCollateral);
        console.log("After third loop - Debt:", thirdLoopDebt);
        
        // Verify maximum leverage achieved
        assertGt(thirdLoopCollateral, secondLoopCollateral, "Collateral should increase after third loop");
        assertGt(thirdLoopDebt, secondLoopDebt, "Debt should increase after third loop");
        
        // Calculate final leverage ratio (debt/collateral should be reasonable)
        uint256 leverageRatio = (thirdLoopDebt * 1e18) / thirdLoopCollateral;
        console.log("Final leverage ratio (debt/collateral * 1e18):", leverageRatio);
        
        // Leverage ratio should be at most 80% (LEVERAGE_RATIO = 8000 in UManager)
        assertLe(leverageRatio, 8e17, "Leverage ratio should be at most 80%");
        
        console.log("Multiple leverage loops test completed successfully");
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _executePartialRepay(uint256 repayAmount) internal {
        // Get all operation leaves from centralized function
        ManageLeaf[] memory allLeafs = _createAllOperationLeafs();
        
        // Select partial repay operations (indices 5-6: wHYPE approve Felix for repayment, Felix repay)
        ManageLeaf[] memory leafs = new ManageLeaf[](2);
        leafs[0] = allLeafs[5];  // wHYPE approve Felix (for repayment)
        leafs[1] = allLeafs[6];  // Felix repay
        
        // Create Felix market params for calldata encoding
        IFelix.MarketParams memory params = IFelix.MarketParams({
            loanToken: wHYPE,
            collateralToken: wstHYPE,
            oracle: felixOracle,
            irm: felixIrm,
            lltv: felixLltv
        });
        
        // Generate merkle tree and set root
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);
        
        // Select only the operations we need (partial repay)
        ManageLeaf[] memory selectedLeafs = new ManageLeaf[](2);
        selectedLeafs[0] = leafs[0]; // wHYPE approve
        selectedLeafs[1] = leafs[1]; // Felix partial repay
        
        bytes32[][] memory manageProofs = _getProofsUsingTree(selectedLeafs, manageTree);
        
        // Prepare execution arrays
        address[] memory targets = new address[](2);
        bytes[] memory calldatas = new bytes[](2);
        uint256[] memory values = new uint256[](2);
        address[] memory decoders = new address[](2);
        
        targets[0] = wHYPE;
        calldatas[0] = abi.encodeCall(IWHYPE.approve, (felixMarkets, repayAmount));
        values[0] = 0;
        decoders[0] = rawDataDecoderAndSanitizer;
        
        targets[1] = felixMarkets;
        calldatas[1] = abi.encodeCall(IFelix.repay, (params, repayAmount, 0, address(boringVault), ""));
        values[1] = 0;
        decoders[1] = rawDataDecoderAndSanitizer;
        
        console.log("Executing partial repay of:", repayAmount);
        
        // Execute partial repay
        manager.manageVaultWithMerkleVerification(manageProofs, decoders, targets, calldatas, values);
    }

    function _executePartialWithdrawal(uint256 withdrawAmount) internal {
        // Get all operation leaves from centralized function
        ManageLeaf[] memory allLeafs = _createAllOperationLeafs();
        
        // Select partial withdrawal operation (index 7: Felix withdraw collateral)
        ManageLeaf[] memory leafs = new ManageLeaf[](1);
        leafs[0] = allLeafs[7];  // Felix withdraw collateral
        
        // Create Felix market params for calldata encoding
        IFelix.MarketParams memory params = IFelix.MarketParams({
            loanToken: wHYPE,
            collateralToken: wstHYPE,
            oracle: felixOracle,
            irm: felixIrm,
            lltv: felixLltv
        });
        
        // Generate merkle tree and set root
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setManageRoot(address(this), manageTree[manageTree.length - 1][0]);
        
        // Select only the withdrawal operation
        ManageLeaf[] memory selectedLeafs = new ManageLeaf[](1);
        selectedLeafs[0] = leafs[0]; // Felix withdraw collateral
        
        bytes32[][] memory manageProofs = _getProofsUsingTree(selectedLeafs, manageTree);
        
        // Prepare execution arrays
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        address[] memory decoders = new address[](1);
        
        targets[0] = felixMarkets;
        calldatas[0] = abi.encodeCall(IFelix.withdrawCollateral, (params, withdrawAmount, address(boringVault), address(boringVault)));
        values[0] = 0;
        decoders[0] = rawDataDecoderAndSanitizer;
        
        console.log("Executing partial collateral withdrawal of:", withdrawAmount);
        
        // Execute partial withdrawal
        manager.manageVaultWithMerkleVerification(manageProofs, decoders, targets, calldatas, values);
    }
}

// ========================================= MOCK CONTRACTS =========================================

contract MockWHYPE is OZToken {
    constructor() OZToken("Wrapped HYPE", "wHYPE") {}

    function deposit() external payable {
        // Mock: mint wHYPE for msg.value of native HYPE
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        // Mock: burn wHYPE and send native HYPE
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }

    // Allow contract to receive ETH (representing HYPE)
    receive() external payable {}
}

contract MockStHYPE is OZToken {
    uint256 public exchangeRate = 1e18; // 1:1 initially
    
    constructor() OZToken("Staked HYPE", "stHYPE") {}

    function setExchangeRate(uint256 _rate) external {
        exchangeRate = _rate;
    }

    // Mock mint function (called by overseer)
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    // Mock burn function (called by overseer)
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockWstHYPE is OZToken {
    MockStHYPE public immutable stHYPE;
    uint256 public exchangeRate = 1e18; // 1 wstHYPE = 1 stHYPE initially
    
    constructor(address _stHYPE) OZToken("Wrapped Staked HYPE", "wstHYPE") {
        stHYPE = MockStHYPE(_stHYPE);
    }

    function setExchangeRate(uint256 _rate) external {
        exchangeRate = _rate;
    }

    // Dual interface implementation - wstHYPE and stHYPE share the same underlying data
    function balanceOf(address account) public view override returns (uint256) {
        // Get stHYPE balance and convert to wstHYPE using exchange rate
        uint256 stHypeBalance = stHYPE.balanceOf(account);
        return stHypeBalance * 1e18 / exchangeRate; // Convert stHYPE to wstHYPE
    }

    function totalSupply() public view override returns (uint256) {
        uint256 stHypeTotalSupply = stHYPE.totalSupply();
        return stHypeTotalSupply * 1e18 / exchangeRate;
    }

    // Override transfer functions to work with the dual interface
    function transfer(address to, uint256 amount) public override returns (bool) {
        // Convert wstHYPE amount to stHYPE amount
        uint256 stHypeAmount = amount * exchangeRate / 1e18;
        return stHYPE.transfer(to, stHypeAmount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // Convert wstHYPE amount to stHYPE amount
        uint256 stHypeAmount = amount * exchangeRate / 1e18;
        return stHYPE.transferFrom(from, to, stHypeAmount);
    }

    // Mock functions for testing
    function mint(address to, uint256 amount) external {
        // Mint equivalent stHYPE
        uint256 stHypeAmount = amount * exchangeRate / 1e18;
        stHYPE.mint(to, stHypeAmount);
    }
}

contract MockOverseer {
    MockStHYPE public immutable stHYPE;
    uint256 public exchangeRate = 1e18; // 1 stHYPE = 1 HYPE initially
    uint256 public maxRedeemableAmount = type(uint256).max; // Default: unlimited instant redemption
    uint256 public lastBurnId = 0;
    mapping(uint256 => bool) public burnRedeemable;
    mapping(uint256 => BurnRequest) public burnRequests;
    
    struct BurnRequest {
        address to;
        uint256 amount;
        uint256 timestamp;
        bool redeemed;
    }
    
    constructor(address _stHYPE) {
        stHYPE = MockStHYPE(_stHYPE);
    }

    function setExchangeRate(uint256 _rate) external {
        exchangeRate = _rate;
    }

    function setMaxRedeemable(uint256 _amount) external {
        maxRedeemableAmount = _amount;
    }

    function setBurnRedeemable(uint256 burnId, bool _redeemable) external {
        burnRedeemable[burnId] = _redeemable;
    }

    function maxRedeemable() external view returns (uint256) {
        return maxRedeemableAmount;
    }

    function redeemable(uint256 burnId) external view returns (bool) {
        return burnRedeemable[burnId];
    }

    function mint(address to, string calldata) external payable returns (uint256) {
        // Mock: stake HYPE (msg.value) to get stHYPE
        uint256 stHypeAmount = msg.value * 1e18 / exchangeRate;
        stHYPE.mint(to, stHypeAmount);
        return stHypeAmount;
    }

    function mint(address to) external payable returns (uint256) {
        // Mock: direct stake HYPE (msg.value) to get stHYPE (no community code)
        uint256 stHypeAmount = msg.value * 1e18 / exchangeRate;
        stHYPE.mint(to, stHypeAmount);
        return stHypeAmount;
    }

    function burn(address to, uint256 amount, string calldata) external returns (uint256) {
        // Simple burn without instant redemption - returns burnId
        stHYPE.burn(msg.sender, amount);
        lastBurnId++;
        burnRequests[lastBurnId] = BurnRequest({
            to: to,
            amount: amount,
            timestamp: block.timestamp,
            redeemed: false
        });
        return lastBurnId;
    }

    function burn(address to, uint256 amount) external returns (uint256) {
        // Simple burn without instant redemption - returns burnId (no community code)
        stHYPE.burn(msg.sender, amount);
        lastBurnId++;
        burnRequests[lastBurnId] = BurnRequest({
            to: to,
            amount: amount,
            timestamp: block.timestamp,
            redeemed: false
        });
        return lastBurnId;
    }

    function burnAndRedeemIfPossible(address to, uint256 amount, string calldata) external returns (uint256) {
        // Burn stHYPE first
        stHYPE.burn(msg.sender, amount);
        
        // Check if we can instantly redeem
        uint256 instantRedeemAmount = amount;
        if (amount > maxRedeemableAmount) {
            instantRedeemAmount = maxRedeemableAmount;
        }
        
        // Instantly redeem what we can
        if (instantRedeemAmount > 0) {
            uint256 hypeAmount = instantRedeemAmount * exchangeRate / 1e18;
            payable(to).transfer(hypeAmount);
        }
        
        // If there's remaining amount, create burn request
        uint256 remainingAmount = amount - instantRedeemAmount;
        if (remainingAmount > 0) {
            lastBurnId++;
            burnRequests[lastBurnId] = BurnRequest({
                to: to,
                amount: remainingAmount,
                timestamp: block.timestamp,
                redeemed: false
            });
            return lastBurnId;
        }
        
        return 0; // No burn ID needed if fully redeemed instantly
    }

    function redeem(uint256 burnId) external {
        require(burnRedeemable[burnId], "Burn not ready for redemption");
        require(!burnRequests[burnId].redeemed, "Already redeemed");
        
        BurnRequest storage request = burnRequests[burnId];
        request.redeemed = true;
        
        uint256 hypeAmount = request.amount * exchangeRate / 1e18;
        payable(request.to).transfer(hypeAmount);
    }

    // Allow contract to receive ETH (representing HYPE)
    receive() external payable {}
}

contract MockFelix {
    using SafeTransferLib for ERC20;
    
    // Track positions per user
    mapping(address => uint256) public collateralBalances;
    mapping(address => uint256) public debtBalances;
    
    // Mock market parameters
    address public wHYPE;
    address public wstHYPE;
    
    function setMarketTokens(address _wHYPE, address _wstHYPE) external {
        wHYPE = _wHYPE;
        wstHYPE = _wstHYPE;
    }

    function supplyCollateral(
        IFelix.MarketParams calldata, // marketParams
        uint256 amount,
        address onBehalf,
        bytes calldata // data
    ) external {
        // Transfer collateral from sender
        ERC20(wstHYPE).safeTransferFrom(msg.sender, address(this), amount);
        
        // Update collateral balance
        collateralBalances[onBehalf] += amount;
    }

    function borrow(
        IFelix.MarketParams calldata, // marketParams
        uint256 amount,
        uint256, // shares
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256) {
        // Update debt balance
        debtBalances[onBehalf] += amount;
        
        // Transfer borrowed tokens to receiver
        ERC20(wHYPE).safeTransfer(receiver, amount);
        
        return (amount, 0); // Return (assets, shares)
    }

    function repay(
        IFelix.MarketParams calldata, // marketParams
        uint256 amount,
        uint256, // shares
        address onBehalf,
        bytes calldata // data
    ) external returns (uint256, uint256) {
        // Transfer repayment from sender
        ERC20(wHYPE).safeTransferFrom(msg.sender, address(this), amount);
        
        // Update debt balance
        if (amount >= debtBalances[onBehalf]) {
            debtBalances[onBehalf] = 0;
        } else {
            debtBalances[onBehalf] -= amount;
        }
        
        return (amount, 0); // Return (assets, shares)
    }

    function withdrawCollateral(
        IFelix.MarketParams calldata, // marketParams
        uint256 amount,
        address onBehalf,
        address receiver
    ) external {
        // Update collateral balance
        if (amount >= collateralBalances[onBehalf]) {
            collateralBalances[onBehalf] = 0;
        } else {
            collateralBalances[onBehalf] -= amount;
        }
        
        // Transfer collateral to receiver
        ERC20(wstHYPE).safeTransfer(receiver, amount);
    }

    // Helper functions for testing
    function getCollateralBalance(address user) external view returns (uint256) {
        return collateralBalances[user];
    }

    function getDebtBalance(address user) external view returns (uint256) {
        return debtBalances[user];
    }

    // Allow contract to receive tokens
    function onERC20Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC20Received.selector;
    }
}