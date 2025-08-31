# WstHYPE Looping Strategy - JavaScript 

Execution and monitoring system for the WstHYPE Looping Strategy on HL.

## Overview

This automation system provides:
- **Strategy Execution**: looping and unwinding operations
- **Continuous Monitoring**: Real-time health checks and alerts
- **Burn Redemption**: Automated completion of delayed unstaking
- **Rate Limit Management**: Built-in protection against excessive calls
- **Emergency Controls**: Pause/unpause and emergency procedures

## Quick Start

### 1. Installation

```bash
cd wstHYPE_script_js
npm install
```

### 2. Configuration

```bash
cp .env.example .env
# Edit .env with your configuration
```

Required environment variables:
- `RPC_URL`: Hyperliquid RPC endpoint
- `STRATEGIST_PRIVATE_KEY`: Private key with STRATEGIST_ROLE
- `ADMIN_PRIVATE_KEY`: Private key with ADMIN_ROLE
- Contract addresses from deployment

### 3. Basic Usage

```bash
# Check vault health
npm run health

# Execute looping strategy (1 wHYPE, 2 loops)
npm run execute -- --amount 1 --loops 2

# Unwind positions (0.5 wHYPE collateral)
npm run unwind -- --amount 0.5

# Complete burn redemptions
npm run redeem

# Start continuous monitoring
npm run monitor
```

## Commands

### Strategy Operations

#### Execute Looping Strategy
```bash
node src/index.js execute --amount <wHYPE_amount> --loops <1-3>
```
- Executes leveraged looping: wHYPE → stHYPE → Felix collateral → borrow wHYPE
- Supports 1-3 leverage loops with 80% LTV
- Requires valid Merkle proofs for all operations

#### Unwind Positions
```bash
node src/index.js unwind --amount <collateral_amount>
```
- Unwinds leveraged positions for withdrawals
- Repays debt and withdraws collateral
- Initiates unstaking process

#### Complete Burn Redemption
```bash
node src/index.js redeem
```
- Checks for ready burn IDs
- Completes delayed unstaking redemptions
- Converts redeemed HYPE back to wHYPE

### Monitoring & Health

#### Health Check
```bash
node src/index.js health
```
Displays:
- Vault balances (wHYPE, stHYPE, wstHYPE)
- Felix positions (collateral, debt)
- Collateralization ratio
- Strategy statistics
- Rate limit status
- Pending burn queue

#### Continuous Monitoring
```bash
node src/index.js monitor --daemon
```
- Real-time health monitoring
- Automated alert system
- Burn redemption checks
- Rate limit tracking

### Configuration

#### Rate Limits
```bash
node src/index.js configure --period 3600 --calls 5
```
- Sets rate limiting parameters
- Prevents excessive strategy calls
- Configurable periods and call limits

#### Emergency Controls
```bash
node src/index.js pause    # Pause all operations
node src/index.js unpause  # Resume operations
```

## Architecture

### Core Components

1. **ContractManager** (`src/contracts.js`)
   - Web3 contract interactions

2. **StrategyExecutor** (`src/execute.js`)
   - Strategy execution logic
   - Pre/post execution checks
   - Input validation

3. **MerkleProofGenerator** (`src/merkle.js`)
   - Generates Merkle proofs for operations
   - Supports all strategy operations

4. **StrategyMonitor** (`src/monitor.js`)
   - Continuous health monitoring
   - Alert system with cooldowns

5. **Logger** (`src/logger.js`)
   - Structured logging
   - File and console output
   - Alert logging

### Security Features

- **Role-Based Access**: Uses STRATEGIST_ROLE and ADMIN_ROLE
- **Rate Limiting**: Configurable call limits per period
- **Merkle Verification**: All operations require valid proofs
- **Health Monitoring**: Continuous collateralization tracking
- **Emergency Pause**: Immediate operation suspension

## Monitoring System

### Health Metrics
- **Vault Balances**: Real-time token balances
- **Collateralization Ratio**: Felix position health
- **Strategy Performance**: Loop execution statistics
- **Rate Limit Usage**: Call tracking and limits

### Alert Levels
- **Critical**: Immediate action required (liquidation risk, rate limits)
- **Warning**: Monitor closely (low collateral, high usage)
- **Info**: General updates (successful operations, burn readiness)

### Alert Delivery
- **Console Logs**: Real-time structured logging
- **File Logs**: Persistent log files with rotation
- **Webhook Alerts**: Discord/Slack notifications
- **Cooldown System**: Prevents alert spam

## Configuration Reference

### Environment Variables

```bash
# Blockchain
RPC_URL=https://rpc.hyperliquid.xyz/evm
CHAIN_ID=999

# Authentication
STRATEGIST_PRIVATE_KEY=0x...
ADMIN_PRIVATE_KEY=0x...

# Contracts (from deployment)
STRATEGY_MANAGER_ADDRESS=0x...
MANAGER_ADDRESS=0x...
BORING_VAULT_ADDRESS=0x...

# Strategy Parameters
MIN_AMOUNT=1000000000000000000    # 1 wHYPE
MAX_AMOUNT=100000000000000000000  # 100 wHYPE
MAX_LEVERAGE_LOOPS=3
LEVERAGE_RATIO=8000               # 80% LTV

# Rate Limiting
RATE_LIMIT_PERIOD=3600            # 1 hour
RATE_LIMIT_CALLS=5                # 5 calls per hour

# Monitoring
HEALTH_CHECK_INTERVAL=60000       # 1 minute
ALERT_WEBHOOK_URL=https://...     # Discord/Slack webhook if want alerts
```

## Error Handling

### Common Issues

1. **Rate Limit Exceeded**
   - Wait for next period reset
   - Check rate limit configuration
   - Monitor call frequency

2. **Merkle Verification Failed**
   - Verify contract addresses
   - Check proof generation logic
   - Ensure Merkle root is set

3. **Insufficient Collateral**
   - Check vault balances
   - Monitor collateralization ratio
   - Consider position unwinding

4. **Transaction Failures**
   - Check gas limits and prices
   - Verify network connectivity
   - Review contract state

### Recovery Procedures

1. **Emergency Pause**
   ```bash
   node src/index.js pause
   ```

2. **Health Assessment**
   ```bash
   node src/index.js health
   ```

3. **Manual Intervention**
   - Review logs for error details
   - Check contract states
   - Contact development team

## Development

### Adding New Features

1. Update contract ABIs in `src/contracts.js`
2. Add new functions to appropriate modules
3. Update CLI commands in `src/index.js`
4. Add monitoring for new operations
5. Update documentation

### Testing

```bash
# Test configuration
node src/index.js health

# Test monitoring
node src/index.js monitor

# Test with small amounts first
node src/index.js execute --amount 0.1 --loops 1
```
