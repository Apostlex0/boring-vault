require('dotenv').config();

const config = {
  // Blockchain Configuration
  rpcUrl: process.env.RPC_URL,
  chainId: parseInt(process.env.CHAIN_ID) || 1,

  // Private Keys
  strategistPrivateKey: process.env.STRATEGIST_PRIVATE_KEY,
  adminPrivateKey: process.env.ADMIN_PRIVATE_KEY,

  // Contract Addresses
  contracts: {
    strategyManager: process.env.STRATEGY_MANAGER_ADDRESS,
    manager: process.env.MANAGER_ADDRESS,
    boringVault: process.env.BORING_VAULT_ADDRESS,
    teller: process.env.TELLER_ADDRESS,
    accountant: process.env.ACCOUNTANT_ADDRESS,
    
    // Protocol Addresses
    wHype: process.env.WHYPE_ADDRESS,
    stHype: process.env.STHYPE_ADDRESS,
    wstHype: process.env.WSTHYPE_ADDRESS,
    overseer: process.env.OVERSEER_ADDRESS,
    felixMarkets: process.env.FELIX_MARKETS_ADDRESS,
    felixOracle: process.env.FELIX_ORACLE_ADDRESS,
    felixIrm: process.env.FELIX_IRM_ADDRESS
  },

  // Strategy Parameters
  strategy: {
    minAmount: process.env.MIN_AMOUNT || '1000000000000000000', // 1 wHYPE
    maxAmount: process.env.MAX_AMOUNT || '100000000000000000000', // 100 wHYPE
    maxLeverageLoops: parseInt(process.env.MAX_LEVERAGE_LOOPS) || 3,
    leverageRatio: parseInt(process.env.LEVERAGE_RATIO) || 8000 // 80%
  },

  // Rate Limiting (not implemented for assignment purpose)
  // rateLimit: {
  //   period: parseInt(process.env.RATE_LIMIT_PERIOD) || 3600, // 1 hour
  //   calls: parseInt(process.env.RATE_LIMIT_CALLS) || 5
  // },

  // Monitoring
  monitoring: {
    healthCheckInterval: parseInt(process.env.HEALTH_CHECK_INTERVAL) || 60000, // 1 minute
    logLevel: process.env.LOG_LEVEL || 'info',
    alertWebhookUrl: process.env.ALERT_WEBHOOK_URL
  },

  // Gas Configuration
  gas: {
    limit: parseInt(process.env.GAS_LIMIT) || 2000000,
    priceMultiplier: parseFloat(process.env.GAS_PRICE_MULTIPLIER) || 1.1
  },

  // Alert Thresholds
  alerts: {
    criticalCollateralRatio: 120,
    warningCollateralRatio: 150,
    // rateLimitWarning: 0.8,
    // rateLimitCritical: 0.95,
    cooldownPeriod: 300000 // 5 minutes
  }
};

module.exports = config;
