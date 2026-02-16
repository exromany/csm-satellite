# Lido Staking Module Discovery

Node Operator search and pagination for CSM and Curated Module v2 through a single, efficient contract.

## Why SMDiscovery?

- **CSM & CMv2 Support**: Works with Community Staking Module (full support) and Curated Module v2 (basic discovery)
- **Dynamic Routing**: Module addresses resolved via StakingRouter
- **Stateless & Simple**: No ownership, explicit cache management
- **Interface Detection**: Gracefully handles CSM-specific features (deposit queues)
- **Future-Proof**: Compatible with any module implementing IStakingModule

## Architecture

### Core Contract: SMDiscovery.sol

Provides Node Operator discovery for CSM and CMv2:

- `findNodeOperatorsByAddress(moduleId, ...)` - Search by address with pagination
- `getNodeOperatorsByAddress(moduleId, ...)` - Get operator details by current address
- `getNodeOperatorsByProposedAddress(moduleId, ...)` - Get operator details by proposed address
- `updateModuleCache(moduleId)` - Cache module address for efficient queries

### CSM-Specific Features

When querying CSM modules, additional functions available:

- `getNodeOperatorsDepositableValidatorsCount(moduleId, offset, limit)` - Paginated depositable validator counts per operator
- `getDepositQueueBatches(moduleId, queuePriority, cursorIndex, limit)` - Traverse deposit queue using linked-list with `batch.next()`

Returns structs with operator IDs, key counts, and next pointers for efficient queue traversal.

**Note:** These queue operations only work with CSM. Calling them on CMv2 will revert with `ModuleDoesNotSupportQueueOperations`.

### Module IDs

#### Mainnet (Chain ID: 1)

| Module                          | ID | Contract Address                             |
|---------------------------------|----|----------------------------------------------|
| Community Staking Module (CSM)  | 3  | `0xdA7dE2ECdDfccC6c3AF10108Db212ACBBf9EA83F` |
| Curated Module (CM)             | 4  | TBD                                          |

#### Hoodi Testnet (Chain ID: 560048)

| Module                          | ID | Contract Address                             |
|---------------------------------|----|----------------------------------------------|
| Community Staking Module (CSM)  | 4  | `0x79CEf36D84743222f37765204Bec41E92a93E59d` |
| Curated Module (CM)             | 5  | TBD                                          |

## Deployment

### Local Fork
```bash
just deploy
```

### Live Network
```bash
# Dry run (recommended first)
CHAIN=mainnet just deploy-live-dry

# Deploy to mainnet
CHAIN=mainnet RPC_URL=<your-rpc> just deploy-live

# Verify on block explorer
CHAIN=mainnet RPC_URL=<your-rpc> just verify-live
```

### Environment Variables

- `CHAIN`: Target chain (`mainnet`, `hoodi`) - defaults to `mainnet`
- `RPC_URL`: RPC endpoint for live deployments
- `ANVIL_IP_ADDR`: Anvil host address (defaults to `127.0.0.1`)

## Usage Example

```solidity
// Deploy SMDiscovery
SMDiscovery discovery = new SMDiscovery(stakingRouterAddress);

// Initialize cache for modules you need
discovery.updateModuleCache(3); // CSM (mainnet)
discovery.updateModuleCache(4); // Curated Module (mainnet)

// Search for Node Operators by address
uint256[] memory operatorIds = discovery.findNodeOperatorsByAddress(
    3,                                      // moduleId (CSM on mainnet)
    0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb,
    0,                                      // offset
    100,                                    // limit
    SearchMode.CURRENT_ADDRESSES            // search mode enum
);

// Get operator details by current address
SMDiscovery.NodeOperatorShort[] memory operators =
    discovery.getNodeOperatorsByAddress(3, targetAddress, 0, 100);
// Returns: id, managerAddress, rewardAddress, extendedManagerPermissions, curveId

// Get CSM-specific data (deposit queue)
SMDiscovery.DepositQueueBatchInfo[] memory batches =
    discovery.getDepositQueueBatches(
        3,          // moduleId
        0,          // queuePriority (0 = highest priority)
        0,          // cursorIndex (start of queue)
        10          // limit
    );
```

## Build Commands

```bash
just                # Clean and build (default)
just build          # Build contracts
just clean          # Clean artifacts
```

## Contract Addresses

| Chain          | StakingRouter                                | SMDiscovery                                  |
|----------------|----------------------------------------------|----------------------------------------------|
| Mainnet (1)    | `0xFdDf38947aFB03C621C71b06C9C70bce73f12999` | `0x32893B74064160C626652c2c21A849fDd0bDDFd6` |
| Hoodi (560048) | `0xCc820558B39ee15C7C45B59390B503b83fb499A8` | `0x2E04CC1F1dac245f66a5C7c5288Bdd4f7cF0c8b4` |

## Testing

Tests forthcoming. Framework: Foundry with forge-std.

```bash
forge test                          # Run all tests
forge test --match-test testName    # Specific test
forge test --gas-report             # With gas reporting
```

## License

MIT
