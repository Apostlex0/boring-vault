#!/usr/bin/env node

const { Command } = require('commander');
const { ethers } = require('ethers');
const StrategyExecutor = require('./execute');
const StrategyMonitor = require('./monitor');
const ContractManager = require('./contracts');
const Logger = require('./logger');
const config = require('./config');

const program = new Command();
const logger = new Logger('WstHypeAutomation');

program
  .name('wsthype-automation')
  .description('WstHYPE Looping Strategy Automation CLI')
  .version('1.0.0');

// Deposit command
program
  .command('deposit')
  .description('Deposit wHYPE into the vault')
  .requiredOption('-a, --amount <amount>', 'wHYPE amount to deposit (in ETH units)')
  .option('-m, --minimum-mint <minimum>', 'Minimum vault shares to receive', '0')
  .action(async (options) => {
    try {
      const contractManager = new ContractManager();
      const amount = ethers.parseEther(options.amount);
      const minimumMint = ethers.parseEther(options.minimumMint);

      console.log(`💰 Depositing ${options.amount} wHYPE into vault...`);
      
      const tx = await contractManager.deposit(
        contractManager.wHype.target,
        amount,
        minimumMint
      );

      console.log(`📝 Transaction hash: ${tx.hash}`);
      console.log('⏳ Waiting for confirmation...');
      
      const receipt = await tx.wait();
      console.log(`✅ Deposit confirmed in block ${receipt.blockNumber}`);
      console.log(`⛽ Gas used: ${receipt.gasUsed.toString()}`);

    } catch (error) {
      console.error('❌ Deposit failed:', error.message);
      process.exit(1);
    }
  });

// Execute looping strategy command
program
  .command('execute')
  .description('Execute looping strategy')
  .requiredOption('-a, --amount <amount>', 'Initial wHYPE amount (in ETH units)')
  .requiredOption('-l, --loops <loops>', 'Number of leverage loops (1-3)')
  .action(async (options) => {
    try {
      const executor = new StrategyExecutor();
      const amount = ethers.parseEther(options.amount);
      const loops = parseInt(options.loops);

      logger.info(`Executing looping strategy: ${options.amount} wHYPE, ${loops} loops`);
      
      const result = await executor.executeLoopingStrategy(amount, loops);
      
      console.log('\n✅ Strategy executed successfully!');
      console.log(`Transaction Hash: ${result.txHash}`);
      console.log(`Block Number: ${result.blockNumber}`);
      console.log(`Gas Used: ${result.gasUsed}`);
      console.log('\nPost-execution stats:');
      console.log(JSON.stringify(result.postStats, null, 2));
      
    } catch (error) {
      console.error('\n❌ Strategy execution failed:');
      console.error(error.message);
      process.exit(1);
    }
  });

// Unwind positions command
program
  .command('unwind')
  .description('Unwind leveraged positions')
  .requiredOption('-a, --amount <amount>', 'Collateral amount to unwind (in ETH units)')
  .action(async (options) => {
    try {
      const executor = new StrategyExecutor();
      const amount = ethers.parseEther(options.amount);

      logger.info(`Unwinding positions: ${options.amount} collateral`);
      
      const result = await executor.unwindPositions(amount);
      
      console.log('\n✅ Positions unwound successfully!');
      console.log(`Transaction Hash: ${result.txHash}`);
      console.log(`Block Number: ${result.blockNumber}`);
      console.log(`Gas Used: ${result.gasUsed}`);
      console.log('\nPost-execution stats:');
      console.log(JSON.stringify(result.postStats, null, 2));
      
    } catch (error) {
      console.error('\n❌ Position unwinding failed:');
      console.error(error.message);
      process.exit(1);
    }
  });

// Complete burn redemption command
program
  .command('redeem')
  .description('Complete burn redemptions')
  .action(async () => {
    try {
      const executor = new StrategyExecutor();

      logger.info('Checking for ready burn redemptions');
      
      const result = await executor.completeBurnRedemption();
      
      if (result.redeemedBurnIds) {
        console.log('\n✅ Burn redemptions completed successfully!');
        console.log(`Transaction Hash: ${result.txHash}`);
        console.log(`Block Number: ${result.blockNumber}`);
        console.log(`Gas Used: ${result.gasUsed}`);
        console.log(`Redeemed Burn IDs: ${result.redeemedBurnIds.join(', ')}`);
      } else {
        console.log('\n📋 No burn redemptions ready');
        console.log(result.message);
      }
      
    } catch (error) {
      console.error('\n❌ Burn redemption failed:');
      console.error(error.message);
      process.exit(1);
    }
  });

// Health check command
program
  .command('health')
  .description('Check vault and strategy health')
  .action(async () => {
    try {
      const contractManager = new ContractManager();

      console.log('\n🔍 Checking vault health...\n');
      
      const [vaultHealth, strategyStats, pendingBurns, isPaused] = await Promise.all([
        contractManager.checkVaultHealth(),
        contractManager.getStrategyStats(),
        // contractManager.getRateLimitStatus(),
        contractManager.getPendingBurnIds(),
        contractManager.isPaused()
      ]);

      // Display results
      console.log('📊 Vault Health:');
      console.log(`  wHYPE Balance: ${vaultHealth.totalWHypeBalance} ETH`);
      console.log(`  stHYPE Balance: ${vaultHealth.totalStHypeBalance} ETH`);
      console.log(`  wstHYPE Balance: ${vaultHealth.totalWstHypeBalance} ETH`);
      console.log(`  Felix Collateral: ${vaultHealth.felixCollateral} ETH`);
      console.log(`  Felix Debt: ${vaultHealth.felixDebt} ETH`);
      console.log(`  Collateralization Ratio: ${vaultHealth.collateralizationRatio.toFixed(2)}%`);

      console.log('\n📈 Strategy Stats:');
      console.log(`  Total Loops: ${strategyStats.totalLoops}`);
      console.log(`  Total Collateral: ${strategyStats.totalCollateral} ETH`);
      console.log(`  Total Debt: ${strategyStats.totalDebt} ETH`);
      console.log(`  Effective Leverage: ${strategyStats.effectiveLeverage.toFixed(2)}x`);

      // console.log('\n⏱️  Rate Limits:');
      // if (rateLimitStatus.period > 0) {
      //   console.log(`  Period: ${rateLimitStatus.period} seconds`);
      //   console.log(`  Calls Made: ${rateLimitStatus.callsMade}/${rateLimitStatus.allowedCallsPerPeriod}`);
      //   console.log(`  Calls Remaining: ${rateLimitStatus.callsRemaining}`);
      //   console.log(`  Next Reset: ${rateLimitStatus.nextReset}`);
      // } else {
      //   console.log('  Rate limiting not configured');
      // }

      console.log('\n🔥 Burn Queue:');
      if (pendingBurns.length > 0) {
        console.log(`  Pending Burns: ${pendingBurns.length}`);
        
        // Check which are ready
        const readyBurns = [];
        for (const burnId of pendingBurns) {
          const isReady = await contractManager.isBurnReady(burnId);
          if (isReady) readyBurns.push(burnId);
        }
        
        if (readyBurns.length > 0) {
          console.log(`  Ready for Redemption: ${readyBurns.join(', ')}`);
        } else {
          console.log('  No burns ready for redemption');
        }
      } else {
        console.log('  No pending burns');
      }

      console.log('\n⚙️  System Status:');
      console.log(`  Strategy Paused: ${isPaused ? '🔴 YES' : '🟢 NO'}`);

      // Health warnings
      if (vaultHealth.collateralizationRatio > 0 && vaultHealth.collateralizationRatio < 150) {
        console.log('\n⚠️  WARNING: Low collateralization ratio!');
      }
      
      // if (rateLimitStatus.callsRemaining <= 1 && rateLimitStatus.period > 0) {
      //   console.log('\n⚠️  WARNING: Rate limit almost exceeded!');
      // }

      if (isPaused) {
        console.log('\n🚨 CRITICAL: Strategy is paused!');
      }
      
    } catch (error) {
      console.error('\n❌ Health check failed:');
      console.error(error.message);
      process.exit(1);
    }
  });

// Monitor command
program
  .command('monitor')
  .description('Start continuous monitoring')
  .option('-d, --daemon', 'Run as daemon (background process)')
  .action(async (options) => {
    try {
      const monitor = new StrategyMonitor();

      if (options.daemon) {
        console.log('🚀 Starting monitoring daemon...');
        monitor.start();
        
        // Keep process alive
        process.on('SIGINT', () => {
          console.log('\n🛑 Stopping monitor...');
          monitor.stop();
          process.exit(0);
        });
        
        process.on('SIGTERM', () => {
          console.log('\n🛑 Stopping monitor...');
          monitor.stop();
          process.exit(0);
        });
        
        console.log('✅ Monitor started. Press Ctrl+C to stop.');
        
        // Keep alive
        setInterval(() => {}, 1000);
        
      } else {
        console.log('📊 Running single monitoring check...');
        const status = await monitor.getMonitoringStatus();
        console.log(JSON.stringify(status, null, 2));
      }
      
    } catch (error) {
      console.error('\n❌ Monitoring failed:');
      console.error(error.message);
      process.exit(1);
    }
  });

// // Configure rate limits command
// program
//   .command('configure')
//   .description('Configure strategy parameters')
//   .option('-p, --period <seconds>', 'Rate limit period in seconds')
//   .option('-c, --calls <number>', 'Allowed calls per period')
//   .action(async (options) => {
//     try {
//       const contractManager = new ContractManager();

//       if (options.period && options.calls) {
//         console.log(`🔧 Configuring rate limits: ${options.calls} calls per ${options.period} seconds`);
        
//         const result = await contractManager.configureRateLimits(
//           parseInt(options.period),
//           parseInt(options.calls)
//         );
        
//         console.log('✅ Rate limits configured successfully!');
//         console.log(`Period: ${result.period} seconds`);
//         console.log(`Allowed calls: ${result.allowedCalls} per period`);
        
//       } else {
//         console.log('❌ Both --period and --calls options are required');
//         process.exit(1);
//       }
      
//     } catch (error) {
//       console.error('\n❌ Configuration failed:');
//       console.error(error.message);
//       process.exit(1);
//     }
//   });

// Pause/unpause commands
program
  .command('pause')
  .description('Pause strategy operations')
  .action(async () => {
    try {
      const contractManager = new ContractManager();
      await contractManager.pauseStrategy();
      console.log('⏸️  Strategy paused successfully');
    } catch (error) {
      console.error('❌ Failed to pause strategy:', error.message);
      process.exit(1);
    }
  });

program
  .command('unpause')
  .description('Unpause strategy operations')
  .action(async () => {
    try {
      const contractManager = new ContractManager();
      await contractManager.unpauseStrategy();
      console.log('▶️  Strategy unpaused successfully');
    } catch (error) {
      console.error('❌ Failed to unpause strategy:', error.message);
      process.exit(1);
    }
  });

// Parse command line arguments
program.parse();

// If no command provided, show help
if (!process.argv.slice(2).length) {
  program.outputHelp();
}
