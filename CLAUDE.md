# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Discovery contract for CSM and Curated Module v2 via StakingRouter integration.

## Core Architecture

### SMDiscovery Contract: `src/SMDiscovery.sol`

**Purpose**: Node Operator search/pagination for CSM and CMv2 via moduleId routing

**Module Support**:

- **CSM (Community Staking Module)**: Full support - basic discovery + queue operations
- **CMv2 (Curated Module v2)**: Basic discovery only - queue operations not available
- **Future modules**: Will work if they implement IStakingModule interface

**Key Features**:
- Dynamic module discovery through StakingRouter
- Explicit cache management with `updateModuleCache()`
- Interface detection for module-specific features
- Support for current/proposed/all address searches
- CSM deposit queue operations (when module supports it)

**Search Modes**:

- `SearchMode.CURRENT_ADDRESSES` - Search by manager/reward addresses
- `SearchMode.PROPOSED_ADDRESSES` - Search by proposed addresses
- `SearchMode.ALL_ADDRESSES` - Search both current and proposed

**Dependencies**:
- `IStakingRouter` for module discovery
- `IStakingModule` for common operations
- `ICSModule` for CSM-specific features

### Interface Hierarchy

```
IStakingModule (base methods all modules implement)
    └─> ICSModule (CSM extensions: queues, Batch type)
```

### Deployment Scripts

```
script/
├── DeployBase.s.sol              ← Abstract base deployment class
├── DeployMainnet.s.sol           ← Mainnet deployment
└── DeployHoodi.s.sol             ← Hoodi testnet deployment
```

## Development Commands

### Build and Test
```bash
just              # Clean and build (default)
just build        # Build contracts
just clean        # Clean artifacts
```

### Deployment
```bash
# Local fork (requires Anvil)
just deploy

# Dry run (recommended first)
just deploy-live-dry

# Live deployment (requires confirmation)
just deploy-live

# Deploy without confirmation
just deploy-live-no-confirm

# Verify on block explorer
just verify-live
```

## Environment Configuration

- `CHAIN`: Target chain (mainnet, hoodi) - defaults to mainnet
- `RPC_URL`: RPC endpoint for live deployments
- `ANVIL_IP_ADDR`: Anvil host (defaults to 127.0.0.1)

## Module IDs

### Mainnet (Chain ID: 1)

| Module                          | ID | Contract Address                             |
|---------------------------------|----|----------------------------------------------|
| Community Staking Module (CSM)  | 3  | `0xdA7dE2ECdDfccC6c3AF10108Db212ACBBf9EA83F` |
| Curated Module (CM)             | 4  | TBD                                          |

### Hoodi Testnet (Chain ID: 560048)

| Module                          | ID | Contract Address                             |
|---------------------------------|----|----------------------------------------------|
| Community Staking Module (CSM)  | 4  | `0x79CEf36D84743222f37765204Bec41E92a93E59d` |
| Curated Module (CM)             | 5  | `0x87EB69Ae51317405FD285efD2326a4a11f6173b9` |

## Deployed Contracts

| Chain          | StakingRouter                                | SMDiscovery (proxy)                          | Implementation |
|----------------|----------------------------------------------|----------------------------------------------|----------------|
| Mainnet (1)    | `0xFdDf38947aFB03C621C71b06C9C70bce73f12999` | pending proxy migration                      | pending        |
| Hoodi (560048) | `0xCc820558B39ee15C7C45B59390B503b83fb499A8` | pending proxy migration                      | pending        |

Pre-proxy deployments, deprecated once the proxies are live and kept only for reference:
mainnet `0x6a9c16626D64dFe7A185eb6378F8eB901f96281C`,
hoodi `0xb3dFdcE02a83454F38Fd127E6261F7AdcDA86B47`.

## Key Technical Details

### Cache Management Pattern

```solidity
// Populate cache (permissionless, anyone can call)
discovery.updateModuleCache(moduleId);

// Use cached address for efficient queries
discovery.findNodeOperatorsByAddress(moduleId, address, offset, limit, mode);
```

### Proxy Pattern

`SMDiscovery` sits behind Lido's `OssifiableProxy` (`src/lib/proxy/OssifiableProxy.sol`,
vendored from CSM with the pragma relaxed to 0.8.24). The address is stable across releases.

- `SMDiscovery` has no initializer: `STAKING_ROUTER` is `immutable` and lives in the
  implementation bytecode; `moduleCache` is filled by the permissionless `updateModuleCache()`.
- `moduleCache` occupies storage slot 0. New state variables may only be appended.
- Releasing a new implementation: `CHAIN=<chain> PROXY_ADDRESS=<proxy> just upgrade-live`.
  If the broadcaster is the proxy admin the upgrade is sent directly; otherwise the script
  logs the `proxy__upgradeTo` calldata for the admin multisig to submit.
- `proxy__ossify()` freezes the implementation permanently once the ABI settles.

Environment variables: `PROXY_ADMIN` (required by deploy scripts), `PROXY_ADDRESS`
(required by upgrade scripts).

### Interface Detection (CSM-specific features)

SMDiscovery gracefully handles module-specific operations:

- Probes `depositQueuePointers()` (CSM-only) via `try/catch`; the priority bound itself is read from `PARAMETERS_REGISTRY().QUEUE_LOWEST_PRIORITY()`, since non-CSM modules may also expose a registry
- If successful: queue operations available
- If fails: reverts with `ModuleDoesNotSupportQueueOperations`

### Data Structures

**NodeOperatorShort** (returned by getNodeOperatorsByAddress):

- id, managerAddress, rewardAddress, extendedManagerPermissions, curveId

**NodeOperatorProposed** (returned by getNodeOperatorsByProposedAddress):

- id, proposedManagerAddress, proposedRewardAddress, curveId

**DepositQueueBatchInfo**:

- nodeOperatorId, keysCount, next (linked-list pointer)

### Common Patterns

- **Stateless**: All functions are view only
- **Immutable StakingRouter**: References governance-approved router
- **Explicit caching**: `updateModuleCache()` for efficiency
- **Offset-limit pagination**: Standard pattern
- **Array trimming**: Dynamic sizing for gas efficiency
- **Custom errors**: Gas-efficient error handling
- **Security limits**: MAX_BATCH_SIZE (1000) prevents DoS

### Deployment Artifacts

Artifacts stored in `./artifacts/latest/` with transactions in `transactions.json`

## Testing

**Current Status**: Proxy mechanics covered by local-mock tests; queue detection and the
deploy script are covered by Hoodi fork tests that skip when `RPC_URL` is unset.

| File | Covers |
|------|--------|
| `test/Proxy.t.sol` | immutables through delegatecall, cache preservation across upgrade, admin control, ossification |
| `test/SelectorCollision.t.sol` | no proxy selector shadows an implementation method |
| `test/StorageLayout.t.sol` | `moduleCache` is the only storage variable, at slot 0 |
| `test/QueueDetection.t.sol` | CSM queue detection, direct and proxied (fork) |
| `test/DeployScript.t.sol` | deploy script wires proxy and seeds cache (fork) |
| `test/UpgradeScript.t.sol` | upgrade script admin/non-admin branches |

**Framework**: Foundry with forge-std

```bash
forge test                          # Run all tests
forge test --match-test testName    # Specific test
forge test --gas-report             # With gas reporting
```

## Dependencies

- **Foundry**: Smart contract framework
- **Just**: Command runner
- **forge-std**: Testing/scripting library
