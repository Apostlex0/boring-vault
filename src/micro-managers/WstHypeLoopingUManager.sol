// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {UManager, FixedPointMathLib, ManagerWithMerkleVerification, ERC20} from "src/micro-managers/UManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DecoderCustomTypes} from "src/interfaces/DecoderCustomTypes.sol";


/**
 * @title WstHypeLoopingUManager
 * @notice Strategy contract for wstHYPE looping with Felix Vanilla leverage
 * @dev Executes: wHYPE -> HYPE -> stHYPE -> Felix supply wstHYPE -> Felix borrow wHYPE -> repeat
 *      Also handles unwinding for withdrawals: repay loans -> withdraw collateral -> unstake -> return wHYPE
 */
contract WstHypeLoopingUManager is UManager {
    
    // =============================== ERRORS ===============================
    
    error WstHypeLoopingUManager__InvalidLeverage();
    error WstHypeLoopingUManager__InvalidAmount();
    error WstHypeLoopingUManager__CallFailed();
    error WstHypeLoopingUManager__Unauthorized();
    error WstHypeLoopingUManager__InsufficientProofs();
    error WstHypeLoopingUManager__BurnNotReady();
    
    // =============================== IMMUTABLES ===============================
    
    // Protocol addresses
    address public immutable wHYPE;
    address public immutable stHYPE;
    address public immutable wstHYPE;
    address public immutable overseer;
    address public immutable felixMarkets;
    
    // Market parameters for Felix Vanilla (wstHYPE/wHYPE market)
    address public immutable felixOracle;
    address public immutable felixIrm;
    uint256 public immutable felixLltv;
    
    // Strategy parameters
    uint256 public constant MAX_LEVERAGE_LOOPS = 3;
    uint256 public constant LEVERAGE_RATIO = 8000; // 80% LTV
    uint256 public constant MIN_AMOUNT = 1e18; // 1 token minimum
    
    // Unified decoder address (HyperLiquidDecoder for all operations)
    address public rawDataDecoderAndSanitizer;
    
    // State tracking for burn operations
    mapping(uint256 => uint256) public burnIdToAmount;
    uint256[] public pendingBurnIds;
    
    // =============================== CONSTRUCTOR ===============================
    
    constructor(
        address _owner,
        address _manager,
        address _boringVault,
        address _wHYPE,
        address _stHYPE,
        address _wstHYPE,
        address _overseer,
        address _felixMarkets,
        address _felixOracle,
        address _felixIrm,
        uint256 _felixLltv
    ) UManager(_owner, _manager, _boringVault) {
        wHYPE = _wHYPE;
        stHYPE = _stHYPE;
        wstHYPE = _wstHYPE;
        overseer = _overseer;
        felixMarkets = _felixMarkets;
        felixOracle = _felixOracle;
        felixIrm = _felixIrm;
        felixLltv = _felixLltv;
    }

    // Removed custom modifiers - using UManager's requiresAuth and enforceRateLimit
    
    // =============================== DECODER SETTERS ===============================
    
    function setDecoder(
        address _hyperliquidDecoder  // Unified decoder for ALL operations (including Felix)
    ) external requiresAuth {
        rawDataDecoderAndSanitizer = _hyperliquidDecoder;
    }
    
    // =============================== STRATEGY EXECUTION (DEPOSIT/LOOP) ===============================
    
    /**
     * @notice Execute wstHYPE looping strategy with specified leverage using BATCHED operations
     * @param initialAmount The initial amount of wHYPE to loop
     * @param leverageLoops Number of leverage loops (max 3)
     * @param allProofs Array of merkle proofs for ALL operations (batched)
     */
    function executeLoopingStrategy(
        uint256 initialAmount,
        uint256 leverageLoops,
        bytes32[][] calldata allProofs
    ) external requiresAuth enforceRateLimit {
        require(initialAmount >= MIN_AMOUNT, "Amount too small");
        require(leverageLoops > 0 && leverageLoops <= MAX_LEVERAGE_LOOPS, "Invalid leverage loops");
        
        // Calculate total number of operations needed (5 operations per loop)
        uint256 totalOperations = leverageLoops * 5;
        require(allProofs.length >= totalOperations, "Insufficient proofs");
        
        // Prepare all operations for batched execution
        (
            bytes32[][] memory proofs,
            address[] memory targets,
            bytes[] memory calldatas,
            uint256[] memory values,
            address[] memory decoders
        ) = _prepareLoopingBatch(initialAmount, leverageLoops, allProofs);
        
        // Execute all operations in a single batch call
        try manager.manageVaultWithMerkleVerification(
            proofs,
            decoders,
            targets,
            calldatas,
            values
        ) {
            // Batch execution successful
        } catch {
            revert WstHypeLoopingUManager__CallFailed();
        }
    }
    
    /**
     * @notice Prepare all looping operations for batched execution
     */
    function _prepareLoopingBatch(
        uint256 initialAmount,
        uint256 leverageLoops,
        bytes32[][] calldata allProofs
    ) internal view returns (
        bytes32[][] memory proofs,
        address[] memory targets,
        bytes[] memory calldatas,
        uint256[] memory values,
        address[] memory decoders
    ) {
        uint256 totalOps = leverageLoops * 5;
        
        proofs = new bytes32[][](totalOps);
        targets = new address[](totalOps);
        calldatas = new bytes[](totalOps);
        values = new uint256[](totalOps);
        decoders = new address[](totalOps);
        
        uint256 currentAmount = initialAmount;
        uint256 opIndex = 0;
        
        for (uint256 i = 0; i < leverageLoops; i++) {
            // 1. Unwrap wHYPE to HYPE
            proofs[opIndex] = allProofs[opIndex];
            targets[opIndex] = wHYPE;
            calldatas[opIndex] = abi.encodeCall(IWHype.withdraw, (currentAmount));
            values[opIndex] = 0;
            decoders[opIndex] = rawDataDecoderAndSanitizer;
            opIndex++;
            
            // 2. Mint stHYPE by sending HYPE to Overseer
            proofs[opIndex] = allProofs[opIndex];
            targets[opIndex] = overseer;
            calldatas[opIndex] = abi.encodeCall(IOverseer.mint, (address(boringVault)));
            values[opIndex] = currentAmount; // HYPE value (native token)
            decoders[opIndex] = rawDataDecoderAndSanitizer;
            opIndex++;
            
            // 3. Approve wstHYPE to Felix
            proofs[opIndex] = allProofs[opIndex];
            targets[opIndex] = wstHYPE;
            calldatas[opIndex] = abi.encodeCall(IERC20.approve, (felixMarkets, currentAmount));
            values[opIndex] = 0;
            decoders[opIndex] = rawDataDecoderAndSanitizer;
            opIndex++;
            
            // 4. Supply wstHYPE as collateral to Felix
            proofs[opIndex] = allProofs[opIndex];
            targets[opIndex] = felixMarkets;
            calldatas[opIndex] = abi.encodeCall(IFelix.supplyCollateral, (_getMarketParams(), currentAmount, address(boringVault), ""));
            values[opIndex] = 0;
            decoders[opIndex] = rawDataDecoderAndSanitizer;
            opIndex++;
            
            // 5. Borrow wHYPE from Felix
            uint256 borrowAmount = currentAmount * LEVERAGE_RATIO / 10000;
            proofs[opIndex] = allProofs[opIndex];
            targets[opIndex] = felixMarkets;
            calldatas[opIndex] = abi.encodeCall(IFelix.borrow, (_getMarketParams(), borrowAmount, 0, address(boringVault), address(boringVault)));
            values[opIndex] = 0;
            decoders[opIndex] = rawDataDecoderAndSanitizer;
            opIndex++;
            
            // Update amount for next loop
            currentAmount = borrowAmount;
        }
        
        return (proofs, targets, calldatas, values, decoders);
    }
    
    // =============================== STRATEGY UNWINDING (WITHDRAWAL) ===============================
    
    /**
     * @notice Unwind positions to prepare for withdrawal using BATCHED operations
     * @param targetAmount Amount of wHYPE needed for repayment
     * @param allProofs Array of merkle proofs for all unwinding operations
     */
    function unwindPositions(
        uint256 targetAmount,
        bytes32[][] calldata allProofs
    ) external requiresAuth enforceRateLimit {
        require(targetAmount >= MIN_AMOUNT, "Amount too small");
        
        // Prepare all unwinding operations for batched execution
        (
            bytes32[][] memory proofs,
            address[] memory targets,
            bytes[] memory calldatas,
            uint256[] memory values,
            address[] memory decoders
        ) = _prepareUnwindingBatch(targetAmount, allProofs);
        
        // Execute all operations in a single batch call
        try manager.manageVaultWithMerkleVerification(
            proofs,
            decoders,
            targets,
            calldatas,
            values
        ) {
            // Batch execution successful
        } catch {
            revert WstHypeLoopingUManager__CallFailed();
        }
    }
    
    /**
     * @notice Prepare all unwinding operations for batched execution
     */
    function _prepareUnwindingBatch(
        uint256 targetAmount,
        bytes32[][] calldata allProofs
    ) internal view returns (
        bytes32[][] memory proofs,
        address[] memory targets,
        bytes[] memory calldatas,
        uint256[] memory values,
        address[] memory decoders
    ) {
        uint256 totalOps = 5; // Simplified unwinding operations
        require(allProofs.length >= totalOps, "Insufficient proofs for unwinding");
        
        proofs = new bytes32[][](totalOps);
        targets = new address[](totalOps);
        calldatas = new bytes[](totalOps);
        values = new uint256[](totalOps);
        decoders = new address[](totalOps);
        
        uint256 opIndex = 0;
        
        // 1. Approve wHYPE for repayment
        proofs[opIndex] = allProofs[opIndex];
        targets[opIndex] = wHYPE;
        calldatas[opIndex] = abi.encodeCall(IERC20.approve, (felixMarkets, targetAmount));
        values[opIndex] = 0;
        decoders[opIndex] = rawDataDecoderAndSanitizer;
        opIndex++;
        
        // 2. Repay loan
        proofs[opIndex] = allProofs[opIndex];
        targets[opIndex] = felixMarkets;
        calldatas[opIndex] = abi.encodeCall(IFelix.repay, (_getMarketParams(), targetAmount, 0, address(boringVault), ""));
        values[opIndex] = 0;
        decoders[opIndex] = rawDataDecoderAndSanitizer;
        opIndex++;
        
        // 3. Withdraw collateral (wstHYPE)
        proofs[opIndex] = allProofs[opIndex];
        targets[opIndex] = felixMarkets;
        calldatas[opIndex] = abi.encodeCall(IFelix.withdrawCollateral, (_getMarketParams(), targetAmount, address(boringVault), address(boringVault)));
        values[opIndex] = 0;
        decoders[opIndex] = rawDataDecoderAndSanitizer;
        opIndex++;
        
        // 4. Approve stHYPE for burning
        proofs[opIndex] = allProofs[opIndex];
        targets[opIndex] = stHYPE;
        calldatas[opIndex] = abi.encodeCall(IERC20.approve, (overseer, targetAmount));
        values[opIndex] = 0;
        decoders[opIndex] = rawDataDecoderAndSanitizer;
        opIndex++;
        
        // 5. Burn stHYPE and redeem if possible, then wrap HYPE to wHYPE
        proofs[opIndex] = allProofs[opIndex];
        targets[opIndex] = overseer;
        calldatas[opIndex] = abi.encodeCall(IOverseer.burnAndRedeemIfPossible, (address(boringVault), targetAmount, ""));
        values[opIndex] = 0;
        decoders[opIndex] = rawDataDecoderAndSanitizer;
        opIndex++;
        
        return (proofs, targets, calldatas, values, decoders);
    }
    
    /**
     * @notice Wrap HYPE to wHYPE after unstaking, done seperately so that it can be unwrapped in bulk instead of wrapping small amounts on each unstake
     */
    function wrapHypeToWHype(
        uint256 amount,
        bytes32[] calldata proof
    ) external requiresAuth enforceRateLimit {
        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        address[] memory decoders = new address[](1);
        
        proofs[0] = proof;
        targets[0] = wHYPE;
        calldatas[0] = abi.encodeCall(IWHype.deposit, ());
        values[0] = amount;
        decoders[0] = rawDataDecoderAndSanitizer;
        
        try manager.manageVaultWithMerkleVerification(
            proofs,
            decoders,
            targets,
            calldatas,
            values
        ) {
            // Wrap execution successful
        } catch {
            revert WstHypeLoopingUManager__CallFailed();
        }
    }
    
    // =============================== BURN REDEMPTION HANDLING ===============================
    
    /**
     * @notice Complete pending burn redemptions using BATCHED operations
     * @param burnIds Array of burn IDs to redeem
     * @param allProofs Merkle proofs for redemption operations
     */
    function completeBurnRedemptions(
        uint256[] calldata burnIds,
        bytes32[][] calldata allProofs
    ) external requiresAuth enforceRateLimit {
        require(burnIds.length == allProofs.length, "Mismatched arrays");
        
        bytes32[][] memory proofs = new bytes32[][](burnIds.length);
        address[] memory targets = new address[](burnIds.length);
        bytes[] memory calldatas = new bytes[](burnIds.length);
        uint256[] memory values = new uint256[](burnIds.length);
        address[] memory decoders = new address[](burnIds.length);
        
        for (uint256 i = 0; i < burnIds.length; i++) {
            // Verify burn is ready for redemption
            require(IOverseer(overseer).redeemable(burnIds[i]), "Burn not ready");
            
            proofs[i] = allProofs[i];
            targets[i] = overseer;
            calldatas[i] = abi.encodeCall(IOverseer.redeem, (burnIds[i]));
            values[i] = 0;
            decoders[i] = rawDataDecoderAndSanitizer;
        }
        
        // Execute all redemptions in a single batch call
        try manager.manageVaultWithMerkleVerification(
            proofs,
            decoders,
            targets,
            calldatas,
            values
        ) {
            // Batch execution successful
        } catch {
            revert WstHypeLoopingUManager__CallFailed();
        }
    }
    
    // =============================== HELPER FUNCTIONS ===============================
    
    /**
     * @notice Check maximum instantly redeemable amount from overseer
     */
    function getMaxRedeemable() external view returns (uint256) {
        return IOverseer(overseer).maxRedeemable();
    }
    
    /**
     * @notice Check if a burn ID is ready for redemption
     */
    function isBurnReady(uint256 burnId) external view returns (bool) {
        return IOverseer(overseer).redeemable(burnId);
    }
    
    /**
     * @notice Emergency function to check vault's health and positions
     * @dev This can be used by external monitoring systems
     */
    function checkVaultHealth() external view returns (
        uint256 totalWHypeBalance,
        uint256 totalStHypeBalance,
        uint256 maxRedeemableFromOverseer
    ) {
        totalWHypeBalance = IERC20(wHYPE).balanceOf(address(boringVault));
        totalStHypeBalance = IERC20(stHYPE).balanceOf(address(boringVault));
        maxRedeemableFromOverseer = IOverseer(overseer).maxRedeemable();
    }


    function _getMarketParams() private view returns (DecoderCustomTypes.MarketParams memory) {
        return DecoderCustomTypes.MarketParams({
            loanToken: wHYPE,
            collateralToken: wstHYPE,
            oracle: felixOracle,
            irm: felixIrm,
            lltv: felixLltv
        });
    }
    // Ownership and strategist management now handled by UManager's Auth system

}

// =============================== INTERFACES ===============================

interface IOverseer {
    function mint(address to) external payable returns (uint256);
    function burnAndRedeemIfPossible(address to, uint256 amount, string calldata communityCode) external returns (uint256);
    function redeem(uint256 burnId) external;
    function maxRedeemable() external view returns (uint256);
    function redeemable(uint256 burnId) external view returns (bool);
}

interface IFelix {
    function supplyCollateral(
        DecoderCustomTypes.MarketParams calldata marketParams,
        uint256 assets,
        address onBehalf,
        bytes calldata data
    ) external;
    
    function borrow(
        DecoderCustomTypes.MarketParams calldata marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external;
    
    function repay(
        DecoderCustomTypes.MarketParams calldata marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external;
    
    function withdrawCollateral(
        DecoderCustomTypes.MarketParams calldata marketParams,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external;
}

interface IWHype {
    function deposit() external payable; // Wrap HYPE to wHYPE
    function withdraw(uint256 wad) external; // Unwrap wHYPE to HYPE
}