// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {UManager} from "src/micro-managers/UManager.sol";
import {ManagerWithMerkleVerification} from "src/base/Roles/ManagerWithMerkleVerification.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {BoringVault} from "src/base/BoringVault.sol";

// Import the proper interfaces
import {IFelix, IOverseer, IstHYPE, IwstHYPE, IWHYPE} from "src/interfaces/Hyperliquidinterfaces.sol";

/**
 * @dev Executes: wHYPE -> HYPE -> stHYPE -> Felix supply wstHYPE -> Felix borrow wHYPE -> repeat
 *      Also handles unwinding for withdrawals: repay loans -> withdraw collateral -> unstake -> return wHYPE
 */
contract WstHypeLoopingUManagerNew is UManager {
    using FixedPointMathLib for uint256;
    
    // =============================== EVENTS ===============================
    
    event LoopingStrategyExecuted(uint256 initialAmount, uint256 leverageLoops, uint256 finalCollateral, uint256 finalDebt);
    event UnwindingExecuted(uint256 targetAmount, uint256 collateralWithdrawn, uint256 debtRepaid);
    event BurnRedemptionCompleted(uint256[] burnIds, uint256 totalRedeemed);
    event DecoderUpdated(address oldDecoder, address newDecoder);
    event EmergencyActionTaken(string action, uint256 amount);
    
    // =============================== ERRORS ===============================
    
    error WstHypeLoopingUManager__InvalidLeverage();
    error WstHypeLoopingUManager__InvalidAmount();
    error WstHypeLoopingUManager__CallFailed(string reason);
    error WstHypeLoopingUManager__Unauthorized();
    error WstHypeLoopingUManager__InsufficientProofs(uint256 required, uint256 provided);
    error WstHypeLoopingUManager__BurnNotReady(uint256 burnId);
    error WstHypeLoopingUManager__ArrayLengthMismatch();
    error WstHypeLoopingUManager__DecoderNotSet();
    error WstHypeLoopingUManager__ZeroAddress();
    error WstHypeLoopingUManager__InsufficientBalance(uint256 required, uint256 available);
    
    // =============================== IMMUTABLES ===============================
    
    // Protocol addresses
    address public immutable wHYPE;
    address public immutable stHYPE;
    address public immutable wstHYPE;
    address public immutable overseer;
    address public immutable felixMarkets;
    address public immutable felixOracle;
    address public immutable felixIrm;
    uint256 public immutable felixLltv;
    
    // Accountant for rate provider access
    AccountantWithRateProviders public immutable accountant;
    
    // Strategy parameters
    uint256 public constant MAX_LEVERAGE_LOOPS = 3;
    uint256 public constant LEVERAGE_RATIO = 8000; // 80% LTV
    uint256 public constant MIN_AMOUNT = 1e15; // 0.001 token minimum 
    uint256 public constant MAX_AMOUNT = 1000000e18; // 1M token maximum for safety
    
    // Unified decoder address (HyperLiquidDecoder for all operations)
    address public rawDataDecoderAndSanitizer;
    
    // State tracking for burn operations
    mapping(uint256 => uint256) public burnIdToAmount;
    mapping(uint256 => address) public burnIdToRecipient;
    uint256[] public pendingBurnIds;
    
    // Strategy state tracking
    uint256 public totalLoopsExecuted;
    uint256 public totalCollateralSupplied;
    uint256 public totalDebtBorrowed;
    
    // =============================== CONSTRUCTOR ===============================
    
    constructor(
        address _owner,
        address _manager,
        address _boringVault,
        address _accountant,
        address _wHYPE,
        address _stHYPE,
        address _wstHYPE,
        address _overseer,
        address _felixMarkets,
        address _felixOracle,
        address _felixIrm,
        uint256 _felixLltv
    ) UManager(_owner, _manager, _boringVault) {
        // Validate all addresses are non-zero
        if (_accountant == address(0) || _wHYPE == address(0) || _stHYPE == address(0) || _wstHYPE == address(0) ||
            _overseer == address(0) || _felixMarkets == address(0) || _felixOracle == address(0) ||
            _felixIrm == address(0)) {
            revert WstHypeLoopingUManager__ZeroAddress();
        }
        
        accountant = AccountantWithRateProviders(_accountant);
        wHYPE = _wHYPE;
        stHYPE = _stHYPE;
        wstHYPE = _wstHYPE;
        overseer = _overseer;
        felixMarkets = _felixMarkets;
        felixOracle = _felixOracle;
        felixIrm = _felixIrm;
        felixLltv = _felixLltv;
    }
    
    // =============================== DECODER SETTERS ===============================
    
    /**
     * @notice Set the unified decoder for all operations
     * @param _hyperliquidDecoder Unified decoder address for ALL operations (including Felix)
     */
    function setDecoder(address _hyperliquidDecoder) external requiresAuth {
        if (_hyperliquidDecoder == address(0)) {
            revert WstHypeLoopingUManager__ZeroAddress();
        }
        
        address oldDecoder = rawDataDecoderAndSanitizer;
        rawDataDecoderAndSanitizer = _hyperliquidDecoder;
        
        emit DecoderUpdated(oldDecoder, _hyperliquidDecoder);
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
        // Input validation
        if (initialAmount < MIN_AMOUNT) {
            revert WstHypeLoopingUManager__InvalidAmount();
        }
        if (initialAmount > MAX_AMOUNT) {
            revert WstHypeLoopingUManager__InvalidAmount();
        }
        if (leverageLoops == 0 || leverageLoops > MAX_LEVERAGE_LOOPS) {
            revert WstHypeLoopingUManager__InvalidLeverage();
        }
        if (rawDataDecoderAndSanitizer == address(0)) {
            revert WstHypeLoopingUManager__DecoderNotSet();
        }
        
        // Calculate total number of operations needed (5 operations per loop)
        uint256 totalOperations = leverageLoops * 5;
        if (allProofs.length < totalOperations) {
            revert WstHypeLoopingUManager__InsufficientProofs(totalOperations, allProofs.length);
        }
        
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
            // Update state tracking
            totalLoopsExecuted += leverageLoops;
            
            // Calculate final amounts for event (approximate)
            uint256 finalCollateral = _calculateExpectedCollateral(initialAmount, leverageLoops);
            uint256 finalDebt = _calculateExpectedDebt(initialAmount, leverageLoops);
            
            totalCollateralSupplied += finalCollateral;
            totalDebtBorrowed += finalDebt;
            
            emit LoopingStrategyExecuted(initialAmount, leverageLoops, finalCollateral, finalDebt);
            
        } catch Error(string memory reason) {
            revert WstHypeLoopingUManager__CallFailed(reason);
        } catch (bytes memory) {
            revert WstHypeLoopingUManager__CallFailed("Unknown error in batch execution");
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
        
        IFelix.MarketParams memory marketParams = _getMarketParams();
        
        for (uint256 i = 0; i < leverageLoops; i++) {
            // 1. Unwrap wHYPE to HYPE
            proofs[opIndex] = allProofs[opIndex];
            targets[opIndex] = wHYPE;
            calldatas[opIndex] = abi.encodeCall(IWHYPE.withdraw, (currentAmount));
            values[opIndex] = 0;
            decoders[opIndex] = rawDataDecoderAndSanitizer;
            opIndex++;
            
            // 2. Mint stHYPE by sending HYPE to Overseer
            proofs[opIndex] = allProofs[opIndex];
            targets[opIndex] = overseer;
            calldatas[opIndex] = abi.encodeWithSignature("mint(address)", boringVault);
            values[opIndex] = currentAmount; // HYPE value (native token)
            decoders[opIndex] = rawDataDecoderAndSanitizer;
            opIndex++;
            
            // 3. Approve wstHYPE to Felix
            proofs[opIndex] = allProofs[opIndex];
            targets[opIndex] = wstHYPE;
            calldatas[opIndex] = abi.encodeCall(IwstHYPE.approve, (felixMarkets, currentAmount));
            values[opIndex] = 0;
            decoders[opIndex] = rawDataDecoderAndSanitizer;
            opIndex++;
            
            // 4. Supply wstHYPE as collateral to Felix
            proofs[opIndex] = allProofs[opIndex];
            targets[opIndex] = felixMarkets;
            calldatas[opIndex] = abi.encodeCall(
                IFelix.supplyCollateral, 
                (marketParams, currentAmount, boringVault, "")
            );
            values[opIndex] = 0;
            decoders[opIndex] = rawDataDecoderAndSanitizer;
            opIndex++;
            
            // 5. Borrow wHYPE from Felix
            uint256 borrowAmount = currentAmount.mulDivDown(LEVERAGE_RATIO, 10000);
            proofs[opIndex] = allProofs[opIndex];
            targets[opIndex] = felixMarkets;
            calldatas[opIndex] = abi.encodeCall(
                IFelix.borrow, 
                (marketParams, borrowAmount, 0, boringVault, boringVault)
            );
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
     * @notice Unwind leveraged positions by repaying debt and withdrawing collateral
     * @param collateralAmount Amount of collateral to unwind
     * @param allProofs Array of merkle proofs for all unwinding operations
     */
    function unwindPositions(
        uint256 collateralAmount,
        bytes32[][] calldata allProofs
    ) external requiresAuth enforceRateLimit {
        if (collateralAmount < MIN_AMOUNT) {
            revert WstHypeLoopingUManager__InvalidAmount();
        }
        if (collateralAmount > MAX_AMOUNT) {
            revert WstHypeLoopingUManager__InvalidAmount();
        }
        if (rawDataDecoderAndSanitizer == address(0)) {
            revert WstHypeLoopingUManager__DecoderNotSet();
        }
        
        // Prepare all unwinding operations for batched execution
        (
            bytes32[][] memory proofs,
            address[] memory targets,
            bytes[] memory calldatas,
            uint256[] memory values,
            address[] memory decoders
        ) = _prepareUnwindingBatch(collateralAmount, allProofs);
        
        // Execute all operations in a single batch call
        try manager.manageVaultWithMerkleVerification(
            proofs,
            decoders,
            targets,
            calldatas,
            values
        ) {
            // Update state tracking (approximate)
            if (totalCollateralSupplied >= collateralAmount) {
                totalCollateralSupplied -= collateralAmount;
            } else {
                totalCollateralSupplied = 0;
            }
            
            uint256 debtRepaid = _calculateDebtAmount();
            if (totalDebtBorrowed >= debtRepaid) {
                totalDebtBorrowed -= debtRepaid;
            } else {
                totalDebtBorrowed = 0;
            }
            
            emit UnwindingExecuted(collateralAmount, collateralAmount, _calculateDebtAmount());
            
        } catch Error(string memory reason) {
            revert WstHypeLoopingUManager__CallFailed(reason);
        } catch (bytes memory) {
            revert WstHypeLoopingUManager__CallFailed("Unknown error in unwinding");
        }
    }
    
    /**
     * @notice Prepare all unwinding operations for batched execution
     */
    function _prepareUnwindingBatch(
        uint256 collateralAmount,
        bytes32[][] calldata allProofs
    ) internal view returns (
        bytes32[][] memory proofs,
        address[] memory targets,
        bytes[] memory calldatas,
        uint256[] memory values,
        address[] memory decoders
    ) {
        uint256 totalOps = 6; // Complete unwinding operations (including wHYPE deposit)
        if (allProofs.length < totalOps) {
            revert WstHypeLoopingUManager__InsufficientProofs(totalOps, allProofs.length);
        }
        
        proofs = new bytes32[][](totalOps);
        targets = new address[](totalOps);
        calldatas = new bytes[](totalOps);
        values = new uint256[](totalOps);
        decoders = new address[](totalOps);
        
        uint256 opIndex = 0;
        IFelix.MarketParams memory marketParams = _getMarketParams();
        
        // Calculate amounts based on exchange rates (following test pattern)
        uint256 debtAmount = _calculateDebtAmount(); // Get actual debt from Felix
        uint256 stHypeToBurn = _calculateStHypeToBurn(collateralAmount); // wstHYPE -> stHYPE
        uint256 hypeFromBurn = _calculateHypeFromBurn(stHypeToBurn); // stHYPE -> HYPE
        
        // 1. Approve wHYPE for repayment (use actual debt amount)
        proofs[opIndex] = allProofs[opIndex];
        targets[opIndex] = wHYPE;
        calldatas[opIndex] = abi.encodeCall(IWHYPE.approve, (felixMarkets, debtAmount));
        values[opIndex] = 0;
        decoders[opIndex] = rawDataDecoderAndSanitizer;
        opIndex++;
        
        // 2. Repay loan (use actual debt amount)
        proofs[opIndex] = allProofs[opIndex];
        targets[opIndex] = felixMarkets;
        calldatas[opIndex] = abi.encodeCall(
            IFelix.repay, 
            (marketParams, debtAmount, 0, boringVault, "")
        );
        values[opIndex] = 0;
        decoders[opIndex] = rawDataDecoderAndSanitizer;
        opIndex++;
        
        // 3. Withdraw collateral (use collateral amount)
        proofs[opIndex] = allProofs[opIndex];
        targets[opIndex] = felixMarkets;
        calldatas[opIndex] = abi.encodeCall(
            IFelix.withdrawCollateral, 
            (marketParams, collateralAmount, boringVault, boringVault)
        );
        values[opIndex] = 0;
        decoders[opIndex] = rawDataDecoderAndSanitizer;
        opIndex++;
        
        // 4. Approve stHYPE for burning (use calculated stHYPE amount)
        proofs[opIndex] = allProofs[opIndex];
        targets[opIndex] = stHYPE;
        calldatas[opIndex] = abi.encodeCall(IstHYPE.approve, (overseer, stHypeToBurn));
        values[opIndex] = 0;
        decoders[opIndex] = rawDataDecoderAndSanitizer;
        opIndex++;
        
        // 5. Burn stHYPE and redeem if possible (use calculated stHYPE amount)
        proofs[opIndex] = allProofs[opIndex];
        targets[opIndex] = overseer;
        calldatas[opIndex] = abi.encodeCall(
            IOverseer.burnAndRedeemIfPossible, 
            (boringVault, stHypeToBurn, "")
        );
        values[opIndex] = 0;
        decoders[opIndex] = rawDataDecoderAndSanitizer;
        opIndex++;
        
        // 6. Wrap HYPE to wHYPE (use calculated HYPE amount from burn)
        proofs[opIndex] = allProofs[opIndex];
        targets[opIndex] = wHYPE;
        calldatas[opIndex] = abi.encodeCall(IWHYPE.deposit, ());
        values[opIndex] = hypeFromBurn; // Use calculated HYPE value from burn
        decoders[opIndex] = rawDataDecoderAndSanitizer;
        opIndex++;
        
        return (proofs, targets, calldatas, values, decoders);
    }
    
    /**
     * @notice Wrap HYPE to wHYPE after unstaking
     * @dev Done separately so it can be batched for multiple unstake operations
     */
    function wrapHypeToWHype(
        uint256 amount,
        bytes32[] calldata proof
    ) external requiresAuth enforceRateLimit {
        if (amount < MIN_AMOUNT) {
            revert WstHypeLoopingUManager__InvalidAmount();
        }
        if (rawDataDecoderAndSanitizer == address(0)) {
            revert WstHypeLoopingUManager__DecoderNotSet();
        }
        
        // Check if vault has sufficient HYPE balance
        if (address(boringVault).balance < amount) {
            revert WstHypeLoopingUManager__InsufficientBalance(amount, address(boringVault).balance);
        }
        
        bytes32[][] memory proofs = new bytes32[][](1);
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);
        address[] memory decoders = new address[](1);
        
        proofs[0] = proof;
        targets[0] = wHYPE;
        calldatas[0] = abi.encodeCall(IWHYPE.deposit, ());
        values[0] = amount;
        decoders[0] = rawDataDecoderAndSanitizer;
        
        try manager.manageVaultWithMerkleVerification(
            proofs,
            decoders,
            targets,
            calldatas,
            values
        ) {
            emit EmergencyActionTaken("HYPE_WRAPPED", amount);
        } catch Error(string memory reason) {
            revert WstHypeLoopingUManager__CallFailed(reason);
        } catch (bytes memory) {
            revert WstHypeLoopingUManager__CallFailed("Unknown error in HYPE wrapping");
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
        if (burnIds.length == 0) {
            revert WstHypeLoopingUManager__InvalidAmount();
        }
        if (burnIds.length != allProofs.length) {
            revert WstHypeLoopingUManager__ArrayLengthMismatch();
        }
        if (rawDataDecoderAndSanitizer == address(0)) {
            revert WstHypeLoopingUManager__DecoderNotSet();
        }
        
        bytes32[][] memory proofs = new bytes32[][](burnIds.length);
        address[] memory targets = new address[](burnIds.length);
        bytes[] memory calldatas = new bytes[](burnIds.length);
        uint256[] memory values = new uint256[](burnIds.length);
        address[] memory decoders = new address[](burnIds.length);
        
        uint256 totalRedeemed = 0;
        
        for (uint256 i = 0; i < burnIds.length; i++) {
            // Verify burn is ready for redemption
            if (!IOverseer(overseer).redeemable(burnIds[i])) {
                revert WstHypeLoopingUManager__BurnNotReady(burnIds[i]);
            }
            
            proofs[i] = allProofs[i];
            targets[i] = overseer;
            calldatas[i] = abi.encodeCall(IOverseer.redeem, (burnIds[i]));
            values[i] = 0;
            decoders[i] = rawDataDecoderAndSanitizer;
            
            // Track redeemed amount (if we have it stored)
            totalRedeemed += burnIdToAmount[burnIds[i]];
        }
        
        // Execute all redemptions in a single batch call
        try manager.manageVaultWithMerkleVerification(
            proofs,
            decoders,
            targets,
            calldatas,
            values
        ) {
            // Clean up tracking data
            for (uint256 i = 0; i < burnIds.length; i++) {
                delete burnIdToAmount[burnIds[i]];
                delete burnIdToRecipient[burnIds[i]];
            }
            
            emit BurnRedemptionCompleted(burnIds, totalRedeemed);
            
        } catch Error(string memory reason) {
            revert WstHypeLoopingUManager__CallFailed(reason);
        } catch (bytes memory) {
            revert WstHypeLoopingUManager__CallFailed("Unknown error in burn redemption");
        }
    }
    
    // =============================== VIEW FUNCTIONS ===============================
    
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
     * @notice Get all pending burn IDs
     */
    function getPendingBurnIds() external view returns (uint256[] memory) {
        return pendingBurnIds;
    }
    
    /**
     * @notice Get strategy statistics
     */
    function getStrategyStats() external view returns (
        uint256 loops,
        uint256 collateral,
        uint256 debt,
        uint256 pendingBurns
    ) {
        return (totalLoopsExecuted, totalCollateralSupplied, totalDebtBorrowed, pendingBurnIds.length);
    }
    
    /**
     * @notice Emergency function to check vault's health and positions
     * @dev This can be used by external monitoring systems
     */
    function checkVaultHealth() external view returns (
        uint256 totalWHypeBalance,
        uint256 totalStHypeBalance,
        uint256 totalWstHypeBalance,
        uint256 totalNativeBalance,
        uint256 maxRedeemableFromOverseer
    ) {
        totalWHypeBalance = ERC20(wHYPE).balanceOf(boringVault);
        totalStHypeBalance = ERC20(stHYPE).balanceOf(boringVault);
        totalWstHypeBalance = ERC20(wstHYPE).balanceOf(boringVault);
        totalNativeBalance = address(boringVault).balance;
        maxRedeemableFromOverseer = IOverseer(overseer).maxRedeemable();
    }
    
    // =============================== INTERNAL HELPER FUNCTIONS ===============================
    
    /**
     * @notice Get Felix market parameters
     */
    function _getMarketParams() internal view returns (IFelix.MarketParams memory) {
        return IFelix.MarketParams({
            loanToken: wHYPE,
            collateralToken: wstHYPE,
            oracle: felixOracle,
            irm: felixIrm,
            lltv: felixLltv
        });
    }
    
    /**
     * @notice Calculate expected collateral after looping
     */
    function _calculateExpectedCollateral(uint256 initialAmount, uint256 loops) internal pure returns (uint256) {
        uint256 total = initialAmount;
        uint256 amount = initialAmount;
        
        for (uint256 i = 0; i < loops; i++) {
            amount = amount.mulDivDown(LEVERAGE_RATIO, 10000);
            total += amount;
        }
        
        return total;
    }
    
    /**
     * @notice Calculate expected debt after looping
     */
    function _calculateExpectedDebt(uint256 initialAmount, uint256 loops) internal pure returns (uint256) {
        uint256 totalDebt = 0;
        uint256 amount = initialAmount;
        
        for (uint256 i = 0; i < loops; i++) {
            uint256 borrowAmount = amount.mulDivDown(LEVERAGE_RATIO, 10000);
            totalDebt += borrowAmount;
            amount = borrowAmount;
        }
        
        return totalDebt;
    }
    
    // =============================== EMERGENCY FUNCTIONS ===============================
    
    /**
     * @notice Emergency function to pause all operations
     * @dev Can only be called by auth, sets decoder to zero address
     */
    function emergencyPause() external requiresAuth {
        address oldDecoder = rawDataDecoderAndSanitizer;
        rawDataDecoderAndSanitizer = address(0);
        
        emit DecoderUpdated(oldDecoder, address(0));
        emit EmergencyActionTaken("EMERGENCY_PAUSE", 0);
    }
    
    /**
     * @notice Emergency function to resume operations
     * @dev Can only be called by auth, restores decoder
     */
    function emergencyResume(address decoder) external requiresAuth {
        if (decoder == address(0)) {
            revert WstHypeLoopingUManager__ZeroAddress();
        }
        
        address oldDecoder = rawDataDecoderAndSanitizer;
        rawDataDecoderAndSanitizer = decoder;
        
        emit DecoderUpdated(oldDecoder, decoder);
        emit EmergencyActionTaken("EMERGENCY_RESUME", 0);
    }
    
    // =============================== CALCULATION HELPERS ===============================
    
    /**
     * @notice Calculate actual debt amount from Felix
     * @dev Queries Felix for the actual debt balance using position and market data
     */
    function _calculateDebtAmount() internal view returns (uint256) {
        // Create market params for Felix query
        IFelix.MarketParams memory marketParams = IFelix.MarketParams({
            loanToken: wHYPE,
            collateralToken: wstHYPE,
            oracle: felixOracle,
            irm: felixIrm,
            lltv: felixLltv
        });
        
        // Calculate market ID (using keccak256 hash of market params)
        bytes32 marketId = keccak256(abi.encode(marketParams));
        
        // Get position data from Felix
        (, uint128 borrowShares,) = IFelix(felixMarkets).position(marketId, address(boringVault));
        
        // If no borrow shares, return 0
        if (borrowShares == 0) {
            return 0;
        }
        
        // Get market data to convert shares to assets
        (,, uint128 totalBorrowAssets, uint128 totalBorrowShares,,) = IFelix(felixMarkets).market(marketId);
        
        // Convert borrow shares to actual debt amount
        // debt = borrowShares * totalBorrowAssets / totalBorrowShares
        if (totalBorrowShares == 0) {
            return 0;
        }
        
        return (uint256(borrowShares) * uint256(totalBorrowAssets)) / uint256(totalBorrowShares);
    }
    
    /**
     * @notice Calculate stHYPE amount to burn from wstHYPE collateral
     * @param wstHypeAmount Amount of wstHYPE collateral
     * @return stHypeAmount Amount of stHYPE to burn
     */
    function _calculateStHypeToBurn(uint256 wstHypeAmount) internal view returns (uint256) {
        // Use accountant's rate provider system to get wstHYPE -> stHYPE conversion rate
        uint256 wstHypeRate = accountant.getRateInQuote(ERC20(wstHYPE));
        // Convert wstHYPE amount to stHYPE equivalent
        return wstHypeAmount.mulDivDown(wstHypeRate, 1e18);
    }
    
    /**
     * @notice Calculate HYPE amount from burning stHYPE
     * @param stHypeAmount Amount of stHYPE to burn
     * @return hypeAmount Amount of HYPE received from burn
     */
    function _calculateHypeFromBurn(uint256 stHypeAmount) internal view returns (uint256) {
        // Use accountant's rate provider system to get stHYPE -> base asset (wHYPE) conversion rate
        uint256 stHypeRate = accountant.getRateInQuote(ERC20(stHYPE));
        // Convert stHYPE amount to HYPE equivalent (assuming 1:1 HYPE to wHYPE base rate)
        return stHypeAmount.mulDivDown(stHypeRate, 1e18);
    }
}