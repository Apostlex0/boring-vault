const { ethers } = require('ethers');
const config = require('./config');
const ContractManager = require('./contracts');
const Logger = require('./logger');
const fs = require('fs');
const path = require('path');
const { getMerkleRoot } = require('./merkle');

class StrategyMonitor {
  constructor() {
    this.contractManager = new ContractManager();
    this.logger = new Logger('StrategyMonitor');
    this.alertCooldowns = new Map();
    this.isRunning = false;
  }

  // Start continuous monitoring
  start() {
    if (this.isRunning) {
      this.logger.warn('Monitor is already running');
      return;
    }

    this.isRunning = true;
    this.logger.info('Starting strategy monitoring system');

    // Start health monitoring interval
    this.healthInterval = setInterval(() => {
      this.performHealthCheck().catch(error => {
        this.logger.error('Health check failed', { error: error.message });
      });
    }, config.monitoring.healthCheckInterval);

    // Start burn redemption check interval
    this.burnInterval = setInterval(() => {
      this.checkBurnRedemptions().catch(error => {
        this.logger.error('Burn redemption check failed', { error: error.message });
      });
    }, config.monitoring.healthCheckInterval * 2); // Check every 2 minutes

    // Start rate limit monitoring (commented out - not implemented yet)
    // this.rateLimitInterval = setInterval(() => {
    //   this.checkRateLimits().catch(error => {
    //     this.logger.error('Rate limit check failed', { error: error.message });
    //   });
    // }, config.monitoring.healthCheckInterval * 2); // Check every 2 minutes

    this.logger.info('Strategy monitoring system started successfully');
  }

  // Stop monitoring
  stop() {
    if (!this.isRunning) {
      this.logger.warn('Monitor is not running');
      return;
    }

    this.isRunning = false;
    
    if (this.healthInterval) clearInterval(this.healthInterval);
    if (this.burnInterval) clearInterval(this.burnInterval);
    // if (this.rateLimitInterval) clearInterval(this.rateLimitInterval);

    this.logger.info('Strategy monitoring system stopped');
  }

  // Perform comprehensive health check
  async performHealthCheck() {
    try {
      const [vaultHealth, strategyStats, isPaused] = await Promise.all([
        this.contractManager.checkVaultHealth(),
        this.contractManager.getStrategyStats(),
        this.contractManager.isPaused()
      ]);

      const healthData = {
        timestamp: new Date().toISOString(),
        vaultHealth,
        strategyStats,
        isPaused
      };

      this.logger.logHealthCheck(healthData);

      // Check for alerts
      await this.checkHealthAlerts(vaultHealth, strategyStats, isPaused);

      return healthData;

    } catch (error) {
      this.logger.error('Failed to perform health check', { error: error.message });
      throw error;
    }
  }

  // Check for health-related alerts
  async checkHealthAlerts(vaultHealth, strategyStats, isPaused) {
    // Check if strategy is paused
    if (isPaused) {
      await this.sendAlert('critical', 'Strategy is paused', { isPaused });
    }

    // Check collateralization ratio
    if (vaultHealth.collateralizationRatio > 0) {
      if (vaultHealth.collateralizationRatio < config.alerts.criticalCollateralRatio) {
        await this.sendAlert('critical', 'Critical collateralization ratio', {
          ratio: vaultHealth.collateralizationRatio,
          threshold: config.alerts.criticalCollateralRatio
        });
      } else if (vaultHealth.collateralizationRatio < config.alerts.warningCollateralRatio) {
        await this.sendAlert('warning', 'Low collateralization ratio', {
          ratio: vaultHealth.collateralizationRatio,
          threshold: config.alerts.warningCollateralRatio
        });
      }
    }

  }


  // Check burn redemptions
  async checkBurnRedemptions() {
    try {
      const pendingBurnIds = await this.contractManager.getPendingBurnIds();
      
      if (pendingBurnIds.length === 0) {
        return;
      }

      const readyBurnIds = [];
      for (const burnId of pendingBurnIds) {
        const isReady = await this.contractManager.isBurnReady(burnId);
        if (isReady) {
          readyBurnIds.push(burnId);
        }
      }

      if (readyBurnIds.length > 0) {
        await this.sendAlert('info', 'Burn redemptions ready', {
          readyBurnIds,
          totalReady: readyBurnIds.length,
          totalPending: pendingBurnIds.length
        });
      }

      this.logger.info('Burn redemption check completed', {
        pendingBurnIds,
        readyBurnIds
      });

    } catch (error) {
      this.logger.error('Failed to check burn redemptions', { error: error.message });
    }
  }

  // Check rate limits (commented out - not implemented yet)
  // async checkRateLimits() {
  //   try {
  //     const rateLimitStatus = await this.contractManager.getRateLimitStatus();
  //     
  //     if (rateLimitStatus.period === 0) {
  //       // Rate limiting not configured
  //       return;
  //     }

  //     const usageRatio = rateLimitStatus.callsMade / rateLimitStatus.allowedCallsPerPeriod;

  //     if (usageRatio >= config.alerts.rateLimitCritical) {
  //       await this.sendAlert('critical', 'Rate limit critical', rateLimitStatus);
  //     } else if (usageRatio >= config.alerts.rateLimitWarning) {
  //       await this.sendAlert('warning', 'Rate limit warning', rateLimitStatus);
  //     }

  //     this.logger.debug('Rate limit check completed', rateLimitStatus);

  //   } catch (error) {
  //     this.logger.error('Failed to check rate limits', { error: error.message });
  //   }
  // }

  // Send alert with cooldown mechanism
  async sendAlert(type, message, severity = 'medium', metadata = {}) {
    const alertKey = `${type}_${severity}`;
    const now = Date.now();
    
    // Check cooldown
    if (this.alertCooldowns.has(alertKey)) {
      const lastAlert = this.alertCooldowns.get(alertKey);
      const cooldownPeriod = this.getCooldownPeriod(severity);
      
      if (now - lastAlert < cooldownPeriod) {
        return; // Skip alert due to cooldown
      }
    }

    const alertData = {
      id: `alert_${now}_${Math.random().toString(36).substr(2, 9)}`,
      type,
      message,
      severity,
      timestamp: new Date().toISOString(),
      blockNumber: metadata.blockNumber || 0,
      metadata,
      acknowledged: false
    };

    // Log alert with structured data
    this.logger.alert(message, alertData);

    // Persist alert to file for dashboard
    await this.persistAlert(alertData);

    // Send webhook if configured
    if (config.monitoring.webhookUrl) {
      try {
        const fetch = require('node-fetch');
        await fetch(config.monitoring.webhookUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(alertData)
        });
      } catch (error) {
        this.logger.error('Failed to send webhook alert:', error);
      }
    }

    // Update cooldown
    this.alertCooldowns.set(alertKey, now);
  }

  // Get current monitoring status
  async getMonitoringStatus() {
    try {
      const [vaultHealth, strategyStats, pendingBurns] = await Promise.all([
        this.contractManager.checkVaultHealth(),
        this.contractManager.getStrategyStats(),
        // this.contractManager.getRateLimitStatus(),
        this.contractManager.getPendingBurnIds()
      ]);

      return {
        timestamp: new Date().toISOString(),
        isRunning: this.isRunning,
        vaultHealth,
        strategyStats,
        // rateLimitStatus,
        pendingBurnIds: pendingBurns,
        alertCooldowns: Object.fromEntries(this.alertCooldowns)
      };

    } catch (error) {
      this.logger.error('Failed to get monitoring status', { error: error.message });
      throw error;
    }
  }

  // Manual health check trigger
  async triggerHealthCheck() {
    this.logger.info('Manual health check triggered');
    return await this.performHealthCheck();
  }

  // Manual burn check trigger
  async triggerBurnCheck() {
    this.logger.info('Manual burn check triggered');
    return await this.checkBurnRedemptions();
  }

  // Check burn redemption queue status with enhanced tracking
  async checkBurnRedemption() {
    try {
      const burnStatus = {
        timestamp: new Date().toISOString(),
        blockNumber: await this.contractManager.provider.getBlockNumber(),
        pendingBurns: [],
        readyForRedemption: [],
        totalPendingAmount: '0',
        averageWaitTime: 0,
        queueHealth: 'healthy'
      };

      // Get burn queue from overseer
      const burnQueue = await this.contractManager.getPendingBurnIds();
      
      let totalPending = 0n;
      let totalWaitTime = 0;
      const currentTime = Math.floor(Date.now() / 1000);

      for (const burnId of burnQueue) {
        const isReady = await this.contractManager.isBurnReady(burnId);
        const burnData = {
          id: burnId.toString(),
          isReady: isReady,
          waitTimeRemaining: isReady ? 0 : 3600 // Simplified - 1 hour estimate
        };

        if (burnData.isReady) {
          burnStatus.readyForRedemption.push(burnData);
        } else {
          burnStatus.pendingBurns.push(burnData);
          totalWaitTime += burnData.waitTimeRemaining;
        }
      }

      burnStatus.totalPendingAmount = '0'; // not gonna use burnredemption for now
      burnStatus.averageWaitTime = burnStatus.pendingBurns.length > 0 ? 
        Math.floor(totalWaitTime / burnStatus.pendingBurns.length) : 0;

      // Determine queue health
      if (burnStatus.readyForRedemption.length > 10) {
        burnStatus.queueHealth = 'congested';
      } else if (burnStatus.averageWaitTime > 7 * 24 * 3600) { // > 7 days
        burnStatus.queueHealth = 'delayed';
      }

      this.logger.info('Burn redemption status', {
        pendingCount: burnStatus.pendingBurns.length,
        readyCount: burnStatus.readyForRedemption.length,
        totalPending: ethers.formatEther(burnStatus.totalPendingAmount),
        averageWaitHours: Math.floor(burnStatus.averageWaitTime / 3600),
        queueHealth: burnStatus.queueHealth
      });

      return burnStatus;
    } catch (error) {
      this.logger.error('Error checking burn redemption:', error);
      throw error;
    }
  }

  // Monitor vault health metrics with enhanced tracking
  async monitorVaultHealth() {
    try {
      const health = {
        timestamp: new Date().toISOString(),
        blockNumber: 0,
        totalAssets: '0',
        totalShares: '0',
        sharePrice: '0',
        isPaused: false,
        merkleRoot: '',
        // rateLimitStatus: {
        //   isActive: false,
        //   remainingCalls: 0,
        //   resetTime: 0
        // },
        protocolHealth: {
          felixCollateralization: '0',
          hyperliquidBalance: '0',
          overseerBurnQueue: 0
        },
        // Risk metrics removed - not needed for basic monitoring
      };

      // Get current block number
      health.blockNumber = await this.contractManager.provider.getBlockNumber();

      // Get vault metrics - using available contract methods
      const [vaultHealth, isPaused] = await Promise.all([
        this.contractManager.checkVaultHealth(),
        this.contractManager.isPaused()
      ]);

      // Extract total assets from vault health
      const totalAssets = BigInt(vaultHealth.totalWHypeBalance || '0') + 
                         BigInt(vaultHealth.totalStHypeBalance || '0') + 
                         BigInt(vaultHealth.totalWstHypeBalance || '0');
      const totalShares = await this.contractManager.boringVault.totalSupply();

      health.totalAssets = totalAssets.toString();
      health.totalShares = totalShares.toString();
      health.sharePrice = totalShares > 0n ? 
        (totalAssets * ethers.parseEther('1') / totalShares).toString() : '0';
      health.isPaused = isPaused;

      // Get current Merkle root
      try {
        health.merkleRoot = getMerkleRoot();
      } catch (error) {
        this.logger.warn('Could not get Merkle root:', error.message);
      }

      // Check rate limiting (commented out - not implemented yet)
      // const rateLimitStatus = await contractManager.getRateLimitStatus();
      // health.rateLimitStatus = rateLimitStatus;

      // Enhanced protocol health checks
      await this.checkProtocolHealth(health);

      // Log comprehensive health status
      this.logger.info('Vault health check completed', {
        blockNumber: health.blockNumber,
        totalAssets: ethers.formatEther(health.totalAssets),
        totalShares: ethers.formatEther(health.totalShares),
        sharePrice: ethers.formatEther(health.sharePrice),
        isPaused: health.isPaused,
        // rateLimitActive: health.rateLimitStatus.isActive
      });

      return health;
    } catch (error) {
      this.logger.error('Error monitoring vault health:', error);
      throw error;
    }
  }

  /**
   * Check protocol health across integrations
   * @param {Object} health - Health object to populate
   */
  async checkProtocolHealth(health) {
    try {
      // Check Felix protocol health using available methods
      const vaultHealth = await this.contractManager.checkVaultHealth();
      health.protocolHealth.felixCollateralization = vaultHealth.collateralizationRatio || '0';

      // Check wHYPE balance 
      health.protocolHealth.hyperliquidBalance = vaultHealth.totalWHypeBalance || '0';

      // Check Overseer burn queue length
      const burnQueue = await this.contractManager.getPendingBurnIds();
      health.protocolHealth.overseerBurnQueue = burnQueue.length;

    } catch (error) {
      this.logger.warn('Error checking protocol health:', error.message);
    }
  }


  /**
   * Persist alert to file system for dashboard access
   * @param {Object} alertData - Alert data to persist
   */
  async persistAlert(alertData) {
    try {
      const alertsDir = path.join(__dirname, '../logs/alerts');
      if (!fs.existsSync(alertsDir)) {
        fs.mkdirSync(alertsDir, { recursive: true });
      }

      const alertFile = path.join(alertsDir, 'recent_alerts.json');
      let alerts = [];
      
      if (fs.existsSync(alertFile)) {
        const data = fs.readFileSync(alertFile, 'utf8');
        alerts = JSON.parse(data);
      }

      alerts.unshift(alertData);
      
      // Keep only last 100 alerts
      if (alerts.length > 100) {
        alerts = alerts.slice(0, 100);
      }

      fs.writeFileSync(alertFile, JSON.stringify(alerts, null, 2));
    } catch (error) {
      this.logger.error('Error persisting alert:', error);
    }
  }

  // Get cooldown period based on alert severity
  getCooldownPeriod(severity) {
    switch (severity) {
      case 'critical':
        return config.alerts.cooldownPeriodCritical;
      case 'warning':
        return config.alerts.cooldownPeriodWarning;
      default:
        return config.alerts.cooldownPeriodMedium;
    }
  }
}

module.exports = StrategyMonitor;
