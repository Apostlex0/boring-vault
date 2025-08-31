const ContractManager = require('./contracts');
const merkle = require('./merkle');
const Logger = require('./logger');
const config = require('./config');

class StrategyExecutor {
  constructor() {
    this.contractManager = new ContractManager();
    this.logger = new Logger('StrategyExecutor');
  }

  // Execute looping strategy
  async executeLoopingStrategy(initialAmount, leverageLoops) {
    try {
      this.logger.info(`Starting looping strategy execution`, {
        initialAmount: initialAmount.toString(),
        leverageLoops,
        timestamp: new Date().toISOString()
      });

      // Pre-execution checks
      const preChecks = await this.preExecutionChecks();
      if (!preChecks.canExecute) {
        throw new Error(`Pre-execution checks failed: ${preChecks.reason}`);
      }

      // Validate inputs
      this.validateLoopingInputs(initialAmount, leverageLoops);

      // Generate Merkle proofs
      this.logger.info('Generating Merkle proofs for looping strategy');
      // Generate Merkle proofs using pre-generated data
      const proofs = merkle.getLoopingProofs(leverageLoops);

      // Execute strategy
      this.logger.info('Executing looping strategy transaction');
      const tx = await this.contractManager.executeLoopingStrategy(
        initialAmount,
        leverageLoops,
        proofs
      );

      this.logger.info(`Transaction submitted: ${tx.hash}`);
      
      // Wait for confirmation
      const receipt = await tx.wait();
      this.logger.info(`Transaction confirmed in block ${receipt.blockNumber}`);

      // Post-execution checks
      const postChecks = await this.postExecutionChecks();
      
      this.logger.info('Looping strategy executed successfully', {
        txHash: tx.hash,
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed.toString(),
        postStats: postChecks
      });

      return {
        success: true,
        txHash: tx.hash,
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed.toString(),
        postStats: postChecks
      };

    } catch (error) {
      this.logger.error('Failed to execute looping strategy', {
        error: error.message,
        stack: error.stack
      });
      throw error;
    }
  }

  // Execute unwinding strategy
  async unwindPositions(collateralAmount) {
    try {
      this.logger.info(`Starting position unwinding`, {
        collateralAmount: collateralAmount.toString(),
        timestamp: new Date().toISOString()
      });

      // Pre-execution checks
      const preChecks = await this.preExecutionChecks();
      if (!preChecks.canExecute) {
        throw new Error(`Pre-execution checks failed: ${preChecks.reason}`);
      }

      // Validate inputs
      this.validateUnwindingInputs(collateralAmount);

      // Generate Merkle proofs using pre-generated data
      this.logger.info('Generating Merkle proofs for unwinding strategy');
      const proofs = merkle.getUnwindingProofs(); 

      // Execute unwinding
      this.logger.info('Executing unwinding transaction');
      const tx = await this.contractManager.unwindPositions(
        collateralAmount,
        proofs
      );

      this.logger.info(`Transaction submitted: ${tx.hash}`);
      
      // Wait for confirmation
      const receipt = await tx.wait();
      this.logger.info(`Transaction confirmed in block ${receipt.blockNumber}`);

      // Post-execution checks
      const postChecks = await this.postExecutionChecks();
      
      this.logger.info('Position unwinding executed successfully', {
        txHash: tx.hash,
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed.toString(),
        postStats: postChecks
      });

      return {
        success: true,
        txHash: tx.hash,
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed.toString(),
        postStats: postChecks
      };

    } catch (error) {
      this.logger.error('Failed to execute unwinding strategy', {
        error: error.message,
        stack: error.stack
      });
      throw error;
    }
  }

  // Complete burn redemption
  async completeBurnRedemption() {
    try {
      this.logger.info('Starting burn redemption check');

      // Get pending burn IDs
      const pendingBurnIds = await this.contractManager.getPendingBurnIds();
      if (pendingBurnIds.length === 0) {
        this.logger.info('No pending burn IDs found');
        return { success: true, message: 'No pending burns to redeem' };
      }

      // Check which burns are ready
      const readyBurnIds = [];
      for (const burnId of pendingBurnIds) {
        const isReady = await this.contractManager.isBurnReady(burnId);
        if (isReady) {
          readyBurnIds.push(burnId);
        }
      }

      if (readyBurnIds.length === 0) {
        this.logger.info('No burn IDs are ready for redemption');
        return { success: true, message: 'No burns ready for redemption' };
      }

      this.logger.info(`Found ${readyBurnIds.length} ready burn IDs: ${readyBurnIds.join(', ')}`);

      // Generate Merkle proofs using pre-generated data
      const proofs = merkle.getBurnRedemptionProofs(readyBurnIds.length);

      // Execute burn redemption
      this.logger.info('Executing burn redemption transaction');
      const tx = await this.contractManager.completeBurnRedemption(
        readyBurnIds,
        proofs
      );

      this.logger.info(`Transaction submitted: ${tx.hash}`);
      
      // Wait for confirmation
      const receipt = await tx.wait();
      this.logger.info(`Transaction confirmed in block ${receipt.blockNumber}`);

      // Post-execution checks
      const postChecks = await this.postExecutionChecks();
      
      this.logger.info('Burn redemption completed successfully', {
        txHash: tx.hash,
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed.toString(),
        redeemedBurnIds: readyBurnIds,
        postStats: postChecks
      });

      return {
        success: true,
        txHash: tx.hash,
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed.toString(),
        redeemedBurnIds: readyBurnIds,
        postStats: postChecks
      };

    } catch (error) {
      this.logger.error('Failed to complete burn redemption', {
        error: error.message,
        stack: error.stack
      });
      throw error;
    }
  }

  // Pre-execution checks
  async preExecutionChecks() {
    try {
      // Check if strategy is paused
      const isPaused = await this.contractManager.isPaused();
      if (isPaused) {
        return { canExecute: false, reason: 'Strategy is paused' };
      }

      // Check rate limits (commented out - not implemented yet)
      // const rateLimitStatus = await this.contractManager.getRateLimitStatus();
      // if (rateLimitStatus.callsRemaining <= 0) {
      //   return { 
      //     canExecute: false, 
      //     reason: `Rate limit exceeded. Next reset: ${rateLimitStatus.nextReset}` 
      //   };
      // }

      // Check vault health
      const vaultHealth = await this.contractManager.checkVaultHealth();
      if (vaultHealth.collateralizationRatio > 0 && vaultHealth.collateralizationRatio < config.alerts.criticalCollateralRatio) {
        return { 
          canExecute: false, 
          reason: `Critical collateralization ratio: ${vaultHealth.collateralizationRatio}%` 
        };
      }

      return { 
        canExecute: true, 
        vaultHealth
        // rateLimitStatus 
      };

    } catch (error) {
      return { 
        canExecute: false, 
        reason: `Pre-execution check failed: ${error.message}` 
      };
    }
  }

  // Post-execution checks
  async postExecutionChecks() {
    try {
      const [vaultHealth, strategyStats, pendingBurns] = await Promise.all([
        this.contractManager.checkVaultHealth(),
        this.contractManager.getStrategyStats(),
        this.contractManager.getPendingBurnIds()
      ]);

      return {
        vaultHealth,
        strategyStats,
        pendingBurnIds: pendingBurns
      };

    } catch (error) {
      this.logger.error('Post-execution checks failed', { error: error.message });
      return { error: error.message };
    }
  }

  // Input validation
  validateLoopingInputs(initialAmount, leverageLoops) {
    const minAmount = BigInt(config.strategy.minAmount);
    const maxAmount = BigInt(config.strategy.maxAmount);

    if (initialAmount < minAmount) {
      throw new Error(`Initial amount ${initialAmount} is below minimum ${minAmount}`);
    }

    if (initialAmount > maxAmount) {
      throw new Error(`Initial amount ${initialAmount} is above maximum ${maxAmount}`);
    }

    if (leverageLoops < 1 || leverageLoops > config.strategy.maxLeverageLoops) {
      throw new Error(`Leverage loops ${leverageLoops} must be between 1 and ${config.strategy.maxLeverageLoops}`);
    }
  }

  validateUnwindingInputs(collateralAmount) {
    const minAmount = BigInt(config.strategy.minAmount);
    const maxAmount = BigInt(config.strategy.maxAmount);

    if (collateralAmount < minAmount) {
      throw new Error(`Collateral amount ${collateralAmount} is below minimum ${minAmount}`);
    }

    if (collateralAmount > maxAmount) {
      throw new Error(`Collateral amount ${collateralAmount} is above maximum ${maxAmount}`);
    }
  }
}

module.exports = StrategyExecutor;
