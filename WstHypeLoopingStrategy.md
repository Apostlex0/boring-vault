# WstHYPE Looping Strategy - Complete Documentation

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Contract Components](#contract-components)
4. [Strategy Flow](#strategy-flow)
5. [Deployment Guide](#deployment-guide)
6. [Testing Guide](#testing-guide)
7. [Operations Guide](#operations-guide)
8. [Security Considerations](#security-considerations)
9. [Basic Checks](#Basic-Checks)

## Overview

The WstHYPE Looping Strategy is a sophisticated DeFi yield farming strategy that leverage Hype Staking Through StakedHype.fi and Felix's lending protocol to create a leveraged staking position. The strategy automatically loops through multiple protocols to maximize yield while managing risk through proper collateralization.

### Key Features
- **Leveraged Staking**: Amplifies staking rewards through borrowing and re-staking
- **Multi-Protocol Integration**: Integrates Hype Staking and Felix protocol
- **Risk Management**: Built-in safety checks and emergency functions
- **Flexible Unwinding**: Supports both immediate and delayed position unwinding

### Strategy Flow Summary
```
wHYPE → HYPE → stHYPE → wstHYPE → Felix Collateral → Borrow wHYPE → Repeat
```

## Architecture

### Core Components
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   BoringVault   │◄──►│ManagerWithMerkle │◄──►│ WstHypeLooping  │
│   (Asset Store) │    │  Verification    │    │   UManagerNew   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                        │
         ▼                        ▼                        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ AccountantWith  │    │ TellerWithMulti  │    │  HyperLiquid    │
│ RateProviders   │    │ AssetSupport     │    │   Decoder       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Protocol Integration
- **StakedHype.fi**: wHYPE, stHYPE, wstHYPE tokens and Overseer contract
- **Felix Vanilla**: Morpho-based lending protocol for borrowing against collateral
- **Boring Vault Ecosystem**: Vault management, accounting, and access control

## Contract Components

### 1. WstHypeLoopingUManagerNew.sol
**Location**: `src/micro-managers/WstHypeLoopingUManagerNew.sol`

The main strategy contract that orchestrates all looping and unwinding operations.

**Key Functions**:
- `executeLoopingStrategy(uint256, bytes32[][])`: Execute leveraged looping
- `unwindPositions(uint256, bytes32[][])`: Unwind positions for withdrawals
- `completeBurnRedemptions(uint256[], bytes32[][])`: Complete delayed burn redemptions
- `wrapHypeToWHype(uint256, bytes32[])`: Wrap HYPE to wHYPE after redemptions

### 2. HyperLiquidDecoderAndSanitizer.sol
**Location**: `src/base/DecodersAndSanitizers/HyperLiquidDecoderAndSanitizer.sol`

Validates and sanitizes all function calls to StakedHype.fi and Felix protocols.

**Supported Functions**:
- **wHYPE**: `deposit()`, `withdraw(uint256)`
- **Overseer**: `mint(address)`, `mint(address,string)`, `burnAndRedeemIfPossible(address,uint256,string)`, `redeem(uint256)`
- **Felix**: `supplyCollateral()`, `borrow()`, `repay()`, `withdrawCollateral()`
- **ERC20**: `transfer()`, `transferFrom()`, `approve()`

### 3. Interface Contracts
**Location**: `src/interfaces/Hyperliquidinterfaces.sol`

Defines interfaces for all external protocol interactions:

### 4. Core Vault Infrastructure
- **BoringVault**: Main asset storage and execution contract
- **ManagerWithMerkleVerification**: Merkle-proof based operation authorization
- **AccountantWithRateProviders**: Exchange rate management and fee calculation
- **TellerWithMultiAssetSupport**: User deposit/withdrawal interface
- **RolesAuthority**: Role-based access control system

## Strategy Flow

### Looping Operations (Leverage Building)

**Operation Sequence**:
1. **wHYPE Withdraw** (`wHYPE.withdraw(amount)`)
   - Unwraps wHYPE to native HYPE
   - Prepares HYPE for staking

2. **Overseer Mint** (`overseer.mint(vault)`)
   - Stakes HYPE to receive stHYPE
   - Uses native HYPE value transfer

3. **wstHYPE Approve** (`wstHYPE.approve(felix, amount)`)
   - Approves Felix to spend wstHYPE as collateral
   - Note: stHYPE and wstHYPE are dual interfaces to same data

4. **Felix Supply Collateral** (`felix.supplyCollateral(params, amount, vault, "")`)
   - Supplies wstHYPE as collateral to Felix
   - Enables borrowing against this collateral

5. **Felix Borrow** (`felix.borrow(params, amount, 0, vault, vault)`)
   - Borrows wHYPE against wstHYPE collateral
   - Creates leveraged position

**Looping**: The borrowed wHYPE can be used to repeat the process, creating multiple loops for increased leverage.

### Unwinding Operations (Position Closure)

**Operation Sequence**:
1. **wHYPE Approve** (`wHYPE.approve(felix, debtAmount)`)
   - Approves Felix for debt repayment

2. **Felix Repay** (`felix.repay(params, debtAmount, 0, vault, "")`)
   - Repays borrowed wHYPE to Felix
   - Reduces debt position

3. **Felix Withdraw Collateral** (`felix.withdrawCollateral(params, collateralAmount, vault, vault)`)
   - Withdraws wstHYPE collateral after debt repayment
   - Recovers staked assets

4. **stHYPE Approve** (`stHYPE.approve(overseer, stHypeAmount)`)
   - Approves overseer for unstaking

5. **Overseer Burn** (`overseer.burnAndRedeemIfPossible(vault, stHypeAmount, "")`)
   - Burns stHYPE to unstake and get HYPE
   - May be immediate or delayed based on protocol state

6. **wHYPE Deposit** (`wHYPE.deposit()`)
   - Wraps received HYPE back to wHYPE
   - Completes the unwinding cycle

### Delayed Redemption Handling

For cases where `burnAndRedeemIfPossible()` cannot immediately redeem:

1. **Complete Burn Redemptions** (`overseer.redeem(burnId)`)
   - Completes delayed burn requests when ready
   - Returns HYPE to vault

2. **Wrap HYPE** (`wrapHypeToWHype(amount, proof)`)
   - Converts redeemed HYPE to wHYPE
   - Separate function

## Deployment

### Environment Setup
```bash
# Clone repository
git clone <repository-url>
cd boring-vault

# Install dependencies
forge install

# Set up environment variables
cp .env.example .env
# Edit .env with your configuration
```

### Deployment Script
**Location**: `script/Deployment_Script/DeployWstHypeLoopingStrategy.s.sol`

**Features**:
- ✅ Complete infrastructure deployment
- ✅ Automatic Merkle root generation and setting
- ✅ Role-based access control configuration
- ✅ All 12 strategy operations pre-approved

**Deployment Command**:
```bash
# Dry run (simulation)
forge script script/Deployment_Script/DeployWstHypeLoopingStrategy.s.sol \
    --rpc-url $HYPERLIQUID_RPC_URL \
    --sender $DEPLOYER_ADDRESS

# Actual deployment
forge script script/Deployment_Script/DeployWstHypeLoopingStrategy.s.sol \
    --rpc-url $HYPERLIQUID_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

### Deployment Phases
1. **Phase 1**: Deploy RolesAuthority
2. **Phase 2**: Deploy BoringVault
3. **Phase 3**: Deploy Accountant and Teller
4. **Phase 4**: Deploy Manager and Decoder
5. **Phase 5**: Deploy Strategy Manager
6. **Phase 6**: Configure roles and permissions
7. **Phase 7**: Generate and set Merkle root

### Post-Deployment Verification
```bash
# Verify all contracts deployed
cast call $BORING_VAULT "totalSupply()" --rpc-url $HYPERLIQUID_RPC_URL

# Check Merkle root is set
cast call $MANAGER "manageRoot(address)" $DEPLOYER_ADDRESS --rpc-url $HYPERLIQUID_RPC_URL

# Verify strategy manager configuration
cast call $STRATEGY_MANAGER "wHYPE()" --rpc-url $HYPERLIQUID_RPC_URL
```

## Testing

### Test Structure
- **Integration Tests**: `test/integrations/WstHypeLoopingIntegrationTest.t.sol`
- **Unit Tests**: `test/HyperLiquidDecoderAndSanitizer.t.sol`
- **Mock Contracts**: Built-in for isolated testing

### Running Tests

**All Integration Tests**:
```bash
forge test --match-path "**/WstHypeLoopingIntegrationTest.t.sol" -v
```

**Specific Test Functions**:
```bash
# Basic looping flow
forge test --match-test testBasicLoopingFlow -vv

# Position unwinding
forge test --match-test testUnwindPosition -vv

# Burn redemption handling
forge test --match-test testBurnWithDelayedRedemption -vv

# Access control
forge test --match-test testAccessControl -vv
```

**Unit Tests**:
```bash
# Decoder validation tests
forge test --match-path "**/HyperLiquidDecoderAndSanitizer.t.sol" -v
```

**Test Coverage**:
```bash
forge coverage --match-path "**/WstHypeLoopingIntegrationTest.t.sol"
```

### Test Scenarios Covered
- ✅ **Basic Looping Flow**: Complete strategy execution
- ✅ **Position Unwinding**: Full and partial unwinding
- ✅ **Delayed Redemptions**: Asynchronous burn handling
- ✅ **Access Control**: Role-based permission testing
- ✅ **Edge Cases**: Minimum amounts, zero balances
- ✅ **Error Conditions**: Invalid inputs, unauthorized access

## Operations Guide

### User Deposit Flow
```bash
# 1. User deposits wHYPE through Teller
cast send $TELLER "deposit(address,uint256,uint256)" \
    $WHYPE_ADDRESS $AMOUNT $MIN_SHARES \
    --private-key $USER_PRIVATE_KEY

# 2. User receives vault shares representing their position
```

### Strategy Execution
```bash
# Execute looping strategy (STRATEGIST_ROLE required)
cast send $STRATEGY_MANAGER "executeLoopingStrategy(uint256,bytes32[][])" \
    $AMOUNT $MERKLE_PROOFS \
    --private-key $STRATEGIST_PRIVATE_KEY
```

### Position Management
```bash
# Unwind positions for withdrawals
cast send $STRATEGY_MANAGER "unwindPositions(uint256,bytes32[][])" \
    $COLLATERAL_AMOUNT $MERKLE_PROOFS \
    --private-key $STRATEGIST_PRIVATE_KEY

# Complete delayed burn redemptions
cast send $STRATEGY_MANAGER "completeBurnRedemptions(uint256[],bytes32[][])" \
    [$BURN_ID1,$BURN_ID2] $MERKLE_PROOFS \
    --private-key $STRATEGIST_PRIVATE_KEY
```

### Monitoring Commands
```bash
# Check Felix position
cast call $FELIX_MARKETS "position(bytes32,address)" $MARKET_ID $BORING_VAULT

# Check vault balance
cast call $WHYPE_ADDRESS "balanceOf(address)" $BORING_VAULT
```

## Security Considerations

### Access Control
- **STRATEGIST_ROLE**: Can execute strategy operations
- **ADMIN_ROLE**: Can set Merkle roots and emergency controls
- **MANAGER_ROLE**: Vault management permissions
- **Rate Limiting**: Built-in protection against rapid operations

### Merkle Proof Verification
- All operations require valid Merkle proofs
- Pre-approved operation set prevents unauthorized calls
- Decoder validation ensures parameter safety

### Exchange Rate Protection
- AccountantWithRateProviders manages rate queries
- Built-in slippage protection
- Rate change limits prevent manipulation

### Emergency Mechanisms
- Strategy pausing capability
- Decoder replacement for upgrades
- Emergency action logging

## Basic Checks

```bash
# Check contract deployment
cast code $CONTRACT_ADDRESS --rpc-url $RPC_URL

# Verify Merkle root
cast call $MANAGER "manageRoot(address)" $ADMIN_ADDRESS --rpc-url $RPC_URL

# Check role assignments
cast call $ROLES_AUTHORITY "doesUserHaveRole(address,uint8)" $USER_ADDRESS $ROLE_ID --rpc-url $RPC_URL

# Monitor events
cast logs --address $STRATEGY_MANAGER --rpc-url $RPC_URL
```

---
