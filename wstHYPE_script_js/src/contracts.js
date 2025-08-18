const { ethers } = require('ethers');
const config = require('./config');

// Contract ABIs - Essential functions only
const STRATEGY_MANAGER_ABI = [
  "function executeLoopingStrategy(uint256 initialAmount, uint256 leverageLoops, bytes32[][] calldata allProofs) external",
  "function unwindPositions(uint256 collateralAmount, bytes32[][] calldata allProofs) external",
  "function completeBurnRedemption(uint256[] calldata burnIds, bytes32[][] calldata allProofs) external",
  "function checkVaultHealth() external view returns (uint256 totalWHypeBalance, uint256 totalStHypeBalance, uint256 totalWstHypeBalance, uint256 felixCollateral, uint256 felixDebt)",
  "function getStrategyStats() external view returns (uint256 loops, uint256 collateral, uint256 debt)",
  "function getPendingBurnIds() external view returns (uint256[] memory)",
  "function isBurnReady(uint256 burnId) external view returns (bool)",
  "function getMaxRedeemable() external view returns (uint256)",
  "function setPeriod(uint16 _period) external",
  "function setAllowedCallsPerPeriod(uint16 _allowedCallsPerPeriod) external",
  "function callCountPerPeriod(uint256 period) external view returns (uint256)",
  "function period() external view returns (uint16)",
  "function allowedCallsPerPeriod() external view returns (uint16)"
];

const MANAGER_ABI = [
  "function manageVaultWithMerkleVerification(bytes32[][] calldata manageProofs, address[] calldata decodersAndSanitizers, address[] calldata targets, bytes[] calldata targetData, uint256[] calldata values) external",
  "function isPaused() external view returns (bool)",
  "function pause() external",
  "function unpause() external",
  "function setManageRoot(address strategist, bytes32 _manageRoot) external"
];

const BORING_VAULT_ABI = [
  "function totalSupply() external view returns (uint256)",
  "function balanceOf(address account) external view returns (uint256)"
];

const ERC20_ABI = [
  "function balanceOf(address account) external view returns (uint256)",
  "function totalSupply() external view returns (uint256)",
  "function decimals() external view returns (uint8)"
];

const FELIX_ABI = [
  "function position(bytes32 id, address user) external view returns (uint256 supplyShares, uint128 borrowShares, uint128 collateral)",
  "function market(bytes32 id) external view returns (uint128 totalSupplyAssets, uint128 totalSupplyShares, uint128 totalBorrowAssets, uint128 totalBorrowShares, uint256 lastUpdate, uint128 fee)"
];

const OVERSEER_ABI = [
  "function maxRedeemable() external view returns (uint256)",
  "function redeemable(uint256 burnId) external view returns (bool)",
  "function totalSupply() external view returns (uint256)"
];

class ContractManager {
  constructor() {
    this.provider = new ethers.JsonRpcProvider(config.rpcUrl);
    this.strategistWallet = new ethers.Wallet(config.strategistPrivateKey, this.provider);
    this.adminWallet = new ethers.Wallet(config.adminPrivateKey, this.provider);
    
    this.initializeContracts();
  }

  initializeContracts() {
    // Strategy Manager Contract
    this.strategyManager = new ethers.Contract(
      config.contracts.strategyManager,
      STRATEGY_MANAGER_ABI,
      this.strategistWallet
    );

    // Manager Contract
    this.manager = new ethers.Contract(
      config.contracts.manager,
      MANAGER_ABI,
      this.adminWallet
    );

    // Boring Vault Contract
    this.boringVault = new ethers.Contract(
      config.contracts.boringVault,
      BORING_VAULT_ABI,
      this.provider
    );

    // Token Contracts
    this.wHype = new ethers.Contract(
      config.contracts.wHype,
      ERC20_ABI,
      this.provider
    );

    this.stHype = new ethers.Contract(
      config.contracts.stHype,
      ERC20_ABI,
      this.provider
    );

    this.wstHype = new ethers.Contract(
      config.contracts.wstHype,
      ERC20_ABI,
      this.provider
    );

    // Protocol Contracts
    this.felixMarkets = new ethers.Contract(
      config.contracts.felixMarkets,
      FELIX_ABI,
      this.provider
    );

    this.overseer = new ethers.Contract(
      config.contracts.overseer,
      OVERSEER_ABI,
      this.provider
    );
  }

  // Strategy Execution Functions
  async executeLoopingStrategy(initialAmount, leverageLoops, proofs) {
    const gasPrice = await this.provider.getFeeData();
    const adjustedGasPrice = gasPrice.gasPrice * BigInt(Math.floor(config.gas.priceMultiplier * 100)) / 100n;

    return await this.strategyManager.executeLoopingStrategy(
      initialAmount,
      leverageLoops,
      proofs,
      {
        gasLimit: config.gas.limit,
        gasPrice: adjustedGasPrice
      }
    );
  }

  async unwindPositions(collateralAmount, proofs) {
    const gasPrice = await this.provider.getFeeData();
    const adjustedGasPrice = gasPrice.gasPrice * BigInt(Math.floor(config.gas.priceMultiplier * 100)) / 100n;

    return await this.strategyManager.unwindPositions(
      collateralAmount,
      proofs,
      {
        gasLimit: config.gas.limit,
        gasPrice: adjustedGasPrice
      }
    );
  }

  async completeBurnRedemption(burnIds, proofs) {
    const gasPrice = await this.provider.getFeeData();
    const adjustedGasPrice = gasPrice.gasPrice * BigInt(Math.floor(config.gas.priceMultiplier * 100)) / 100n;

    return await this.strategyManager.completeBurnRedemption(
      burnIds,
      proofs,
      {
        gasLimit: config.gas.limit,
        gasPrice: adjustedGasPrice
      }
    );
  }

  // Monitoring Functions
  async checkVaultHealth() {
    try {
      const [totalWHypeBalance, totalStHypeBalance, totalWstHypeBalance, felixCollateral, felixDebt] = 
        await this.strategyManager.checkVaultHealth();
      
      return {
        totalWHypeBalance: ethers.formatEther(totalWHypeBalance),
        totalStHypeBalance: ethers.formatEther(totalStHypeBalance),
        totalWstHypeBalance: ethers.formatEther(totalWstHypeBalance),
        felixCollateral: ethers.formatEther(felixCollateral),
        felixDebt: ethers.formatEther(felixDebt),
        collateralizationRatio: felixDebt > 0 ? (Number(ethers.formatEther(felixCollateral)) / Number(ethers.formatEther(felixDebt))) * 100 : 0
      };
    } catch (error) {
      throw new Error(`Failed to check vault health: ${error.message}`);
    }
  }

  async getStrategyStats() {
    try {
      const [loops, collateral, debt] = await this.strategyManager.getStrategyStats();
      
      return {
        totalLoops: Number(loops),
        totalCollateral: ethers.formatEther(collateral),
        totalDebt: ethers.formatEther(debt),
        effectiveLeverage: debt > 0 ? Number(ethers.formatEther(collateral)) / (Number(ethers.formatEther(collateral)) - Number(ethers.formatEther(debt))) : 1
      };
    } catch (error) {
      throw new Error(`Failed to get strategy stats: ${error.message}`);
    }
  }

  async getPendingBurnIds() {
    try {
      const burnIds = await this.strategyManager.getPendingBurnIds();
      return burnIds.map(id => Number(id));
    } catch (error) {
      throw new Error(`Failed to get pending burn IDs: ${error.message}`);
    }
  }

  async isBurnReady(burnId) {
    try {
      return await this.strategyManager.isBurnReady(burnId);
    } catch (error) {
      throw new Error(`Failed to check burn readiness: ${error.message}`);
    }
  }

  async getMaxRedeemable() {
    try {
      const maxRedeemable = await this.strategyManager.getMaxRedeemable();
      return ethers.formatEther(maxRedeemable);
    } catch (error) {
      throw new Error(`Failed to get max redeemable: ${error.message}`);
    }
  }

  // Rate Limiting Functions (commented out - not implemented yet)
  // async getRateLimitStatus() {
  //   try {
  //     const period = await this.strategyManager.period();
  //     const allowedCalls = await this.strategyManager.allowedCallsPerPeriod();
  //     const currentPeriod = Math.floor(Date.now() / 1000) % Number(period);
  //     const callsMade = await this.strategyManager.callCountPerPeriod(currentPeriod);
  //
  //     return {
  //       period: Number(period),
  //       allowedCallsPerPeriod: Number(allowedCalls),
  //       currentPeriod,
  //       callsMade: Number(callsMade),
  //       callsRemaining: Number(allowedCalls) - Number(callsMade),
  //       nextReset: new Date((Math.floor(Date.now() / 1000 / Number(period)) + 1) * Number(period) * 1000)
  //     };
  //   } catch (error) {
  //     throw new Error(`Failed to get rate limit status: ${error.message}`);
  //   }
  // }

  // Admin Functions (commented out - not implemented yet)
  // async configureRateLimits(period, allowedCalls) {
  //   try {
  //     const tx1 = await this.strategyManager.connect(this.adminWallet).setPeriod(period);
  //     await tx1.wait();
  //     
  //     const tx2 = await this.strategyManager.connect(this.adminWallet).setAllowedCallsPerPeriod(allowedCalls);
  //     await tx2.wait();
  //     
  //     return { period, allowedCalls };
  //   } catch (error) {
  //     throw new Error(`Failed to configure rate limits: ${error.message}`);
  //   }
  // }

  async pauseStrategy() {
    try {
      const tx = await this.manager.pause();
      await tx.wait();
      return true;
    } catch (error) {
      throw new Error(`Failed to pause strategy: ${error.message}`);
    }
  }

  async unpauseStrategy() {
    try {
      const tx = await this.manager.unpause();
      await tx.wait();
      return true;
    } catch (error) {
      throw new Error(`Failed to unpause strategy: ${error.message}`);
    }
  }

  async isPaused() {
    try {
      return await this.manager.isPaused();
    } catch (error) {
      throw new Error(`Failed to check pause status: ${error.message}`);
    }
  }
}

module.exports = ContractManager;
