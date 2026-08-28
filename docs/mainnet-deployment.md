# Mainnet Deployment Runbook

Step-by-step procedure for deploying and upgrading `SMDiscovery` on Ethereum mainnet.
The flow below was rehearsed end-to-end on a Hoodi anvil fork and then executed on Hoodi
itself; mainnet differs only in the values called out here.

**This spends real ETH and publishes a contract other systems will depend on.
Do not run steps 3+ without an explicit go-ahead.**

## Reference values

| Field | Value |
|---|---|
| Chain ID | `1` |
| StakingRouter | `0xFdDf38947aFB03C621C71b06C9C70bce73f12999` |
| CSM module (id 3) | `0xdA7dE2ECdDfccC6c3AF10108Db212ACBBf9EA83F` |
| CM module (id 4) | `0xDa5F930cE326EB5205085D66c72A4E79d60cB8C1` |
| Deployer | `0x3e8f6e55601bef766634e43b26c99c4c01f71863` (keystore `acc2`) |
| Account flags | `--account acc2 --sender 0x3e8f6e55601bef766634e43b26c99c4c01f71863` |
| Scripts | `DeployMainnet` / `UpgradeMainnet` |
| Artifacts | `artifacts/mainnet/transactions.json` |

The mainnet keystore is **encrypted** — never pass `--password=""` (that is a Hoodi-only
convenience). You will be prompted for the password.

## Open decisions before a first deploy

Two things must be settled explicitly; neither has a safe default.

1. **Proxy admin.** `PROXY_ADMIN` is required and must not be zero. On Hoodi it is the
   deployer EOA. **On mainnet it should be a multisig**, not an EOA. The admin can replace
   the implementation and therefore change what every consumer reads, so it carries the
   same trust weight as the contract itself. Decide the address before step 3.

2. **Which modules to seed.** `script/DeployMainnet.s.sol` currently enables **only CSM
   (id 3)**; CM (id 4) is still commented out from when it was unregistered. It is
   registered now, at the address in the table above, and it exposes a working
   `ACCOUNTING()`, so it can be cached. Uncomment it if CM discovery is wanted at launch —
   otherwise queries against module 4 revert `ModuleCacheNotInitialized` until someone
   calls `updateModuleCache(4)`.

   Caching a module never requires an upgrade: `updateModuleCache` is permissionless and
   can be called any time after deployment.

---

## 1. Pre-flight

Point the environment at mainnet — in `.env`, uncomment the mainnet `RPC_URL` and set
`CHAIN=mainnet`. Then load it into the shell (`just`'s dotenv only applies inside recipes,
so outer-shell `$VAR` would otherwise be empty):

```bash
set -a; source .env; set +a
cast chain-id --rpc-url=$RPC_URL      # → 1
```

Confirm the registry matches the deploy script before trusting either:

```bash
cast call 0xFdDf38947aFB03C621C71b06C9C70bce73f12999 "getStakingModuleIds()(uint256[])" --rpc-url=$RPC_URL
```

Check gas budget:

```bash
cast balance 0x3e8f6e55601bef766634e43b26c99c4c01f71863 --rpc-url=$RPC_URL --ether
cast gas-price --rpc-url=$RPC_URL
```

A first deploy is ~6.5M gas, an upgrade ~5.1M. Multiply against the live gas price rather
than assuming — the cost swings by two orders of magnitude with network conditions:

| Gas price | First deploy | Upgrade |
|---|---|---|
| 0.05 gwei | ~0.0003 ETH | ~0.0003 ETH |
| 5 gwei | ~0.033 ETH | ~0.026 ETH |
| 30 gwei | ~0.20 ETH | ~0.15 ETH |

Export the admin (it is deliberately not in `.env`; shell environment beats `just`'s
dotenv, so an exported value always wins):

```bash
export PROXY_ADMIN=<multisig address>
```

Finally, run the test suite. `test/StorageLayout.t.sol` and `test/SelectorCollision.t.sol`
are the guards that make an upgrade safe, and there is no CI — they only run when you run
them:

```bash
forge test
```

## 2. Dry run — mandatory

```bash
TERM=xterm-256color just deploy-live-dry --account acc2 --sender 0x3e8f6e55601bef766634e43b26c99c4c01f71863
```

`TERM` must be set because the `_warn` recipe calls `tput`.

Expect `Initialized cache for moduleId=<id>` for **every** configured module, `ChainId: 1`,
and `SIMULATION COMPLETE`. A `Warning: Could not initialize cache for moduleId=<id>` means
that module is not registered — stop and resolve it. If the dry run fails at all, stop.

## 3. Broadcast

**Get explicit confirmation first.**

Use `deploy-live-no-confirm`; the `deploy-live` recipe wraps `[confirm(...)]`, which needs
interactive stdin and will not run non-interactively.

```bash
TERM=xterm-256color just deploy-live-no-confirm \
  --etherscan-api-key=$ETHERSCAN_API_KEY \
  --account acc2 --sender 0x3e8f6e55601bef766634e43b26c99c4c01f71863
```

Expect `ONCHAIN EXECUTION COMPLETE & SUCCESSFUL`. The recipe copies the broadcast to
`artifacts/latest/transactions.json`.

## 4. Extract addresses

A first deploy emits two CREATE transactions. Select by contract name, not receipt index:

```bash
F=broadcast/DeployMainnet.s.sol/1/run-latest.json
IMPL=$(cast to-check-sum-address $(jq -r '.transactions[] | select(.contractName=="SMDiscovery" and .transactionType=="CREATE") | .contractAddress' $F))
PROXY=$(cast to-check-sum-address $(jq -r '.transactions[] | select(.contractName=="OssifiableProxy" and .transactionType=="CREATE") | .contractAddress' $F))
echo "impl=$IMPL proxy=$PROXY"
```

`$PROXY` is the public address. `$IMPL` is needed only for verification and doc bookkeeping.

## 5. Verify on Etherscan

Use the **Etherscan V2 unified endpoint**. The per-chain V1 subdomains are Cloudflare-walled
and reject automated POSTs. Mainnet needs Etherscan only — Blockscout is a Hoodi-only step.

Implementation:

```bash
forge verify-contract $IMPL src/SMDiscovery.sol:SMDiscovery \
  --chain 1 --verifier etherscan \
  --verifier-url "https://api.etherscan.io/v2/api?chainid=1" \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address)" 0xFdDf38947aFB03C621C71b06C9C70bce73f12999)
```

Proxy — three-arg constructor, **empty bytes** as the third argument (the deploy passes `""`
because `SMDiscovery` has no initializer):

```bash
forge verify-contract $PROXY src/lib/proxy/OssifiableProxy.sol:OssifiableProxy \
  --chain 1 --verifier etherscan \
  --verifier-url "https://api.etherscan.io/v2/api?chainid=1" \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address,address,bytes)" $IMPL $PROXY_ADMIN 0x)
```

Each submission returns a GUID. Check it after a few seconds:

```bash
forge verify-check <GUID> --chain 1 --verifier etherscan \
  --verifier-url "https://api.etherscan.io/v2/api?chainid=1" \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

Expect `Pass - Verified` for both. Then, on the proxy's Etherscan page, use
**More Options → Is this a proxy?** so the explorer renders the implementation ABI against
the proxy address. Cosmetic, but it is what makes the contract usable from Etherscan's UI.

## 6. On-chain checks

Query the **proxy**, never the implementation:

```bash
cast call $PROXY "proxy__getImplementation()(address)" --rpc-url=$RPC_URL   # → $IMPL
cast call $PROXY "proxy__getAdmin()(address)"          --rpc-url=$RPC_URL   # → $PROXY_ADMIN
cast call $PROXY "proxy__getIsOssified()(bool)"        --rpc-url=$RPC_URL   # → false

cast call $PROXY "STAKING_ROUTER()(address)" --rpc-url=$RPC_URL
# → 0xFdDf38947aFB03C621C71b06C9C70bce73f12999
# Works despite the proxy storing nothing: STAKING_ROUTER is immutable, so it lives in the
# implementation's bytecode and resolves correctly under delegatecall.

cast call $PROXY "moduleCache(uint256)(address,address)" 3 --rpc-url=$RPC_URL
# → (module address, accounting address); both non-zero. Repeat for every configured id.
```

One real read, to prove the whole path end to end:

```bash
cast call $PROXY "getAllNodeOperators(uint256,uint256,uint256)((uint256,address,address,bool,address,address,uint256)[])" 3 0 3 --rpc-url=$RPC_URL
```

## 7. Record the deployment

`artifacts/latest/` is gitignored scratch. Sync the durable record:

```bash
cp artifacts/latest/transactions.json artifacts/mainnet/transactions.json
jq -r '.transactions[] | select(.transactionType=="CREATE") | "\(.contractName) \(.contractAddress)"' artifacts/mainnet/transactions.json
```

Update the mainnet row in the address tables of `README.md` and `CLAUDE.md` — proxy address,
implementation address, and the admin. Commit script changes too if module ids moved.

---

# Upgrading an existing mainnet proxy

The proxy address does not change, and `moduleCache` is preserved — it lives in the proxy's
storage, so it never needs re-seeding.

`UpgradeBase` reads `STAKING_ROUTER` off the live proxy and feeds it to the new
implementation's constructor. The router therefore cannot drift from a stale hardcoded
constant, which is the single most dangerous mistake available here.

**Storage-layout rule:** `moduleCache` occupies slot 0. New state variables may only be
**appended** — reordering or inserting corrupts live state. Run `forge test` first;
`test/StorageLayout.t.sol` is the guard.

```bash
set -a; source .env; set +a
export PROXY_ADDRESS=<mainnet proxy>
cast call $PROXY_ADDRESS "proxy__getAdmin()(address)" --rpc-url=$RPC_URL

TERM=xterm-256color just upgrade-live-dry --account acc2 --sender 0x3e8f6e55601bef766634e43b26c99c4c01f71863
TERM=xterm-256color just upgrade-live-no-confirm --etherscan-api-key=$ETHERSCAN_API_KEY --account acc2 --sender 0x3e8f6e55601bef766634e43b26c99c4c01f71863
```

Because the mainnet admin is a multisig and the deployer is not, the script takes its
**non-admin branch**: it deploys the new implementation and then prints the transaction for
the admin to submit, rather than upgrading itself.

```
Broadcaster is not the proxy admin, not upgrading.
Submit this transaction from the admin:
  to: <proxy>
  data: 0x3ebdd0eb<32-byte padded new implementation>
```

This split is deliberate. The expensive, failure-prone step (deploying and verifying the
implementation) happens without admin keys; the multisig then signs one cheap call against
bytecode already on chain and independently verifiable.

Before handing the payload to signers:

- confirm the selector: `cast sig 'proxy__upgradeTo(address)'` → `0x3ebdd0eb`
- confirm the trailing 32 bytes decode to the implementation address you just verified
- verify that implementation on Etherscan (step 5) **first**, so signers can read the code
  they are about to point the proxy at

After the multisig executes:

```bash
cast call $PROXY_ADDRESS "proxy__getImplementation()(address)" --rpc-url=$RPC_URL  # → new impl
cast call $PROXY_ADDRESS "proxy__getAdmin()(address)"          --rpc-url=$RPC_URL  # → unchanged
cast call $PROXY_ADDRESS "STAKING_ROUTER()(address)"           --rpc-url=$RPC_URL  # → unchanged
cast call $PROXY_ADDRESS "moduleCache(uint256)(address,address)" 3 --rpc-url=$RPC_URL
# → identical to pre-upgrade. If this changed, STOP: the storage layout was broken.
```

Then sync artifacts and update the **implementation** column in the docs. The proxy address
stays put.

---

# Ossification (irreversible)

`proxy__ossify()` sets the admin slot to `address(0)`, permanently freezing the current
implementation. There is no undo — `proxy__changeAdmin` is itself admin-gated, so no path
back to a non-zero admin exists.

Only run it once the ABI has settled, and only on an explicit decision.

```bash
cast send $PROXY_ADDRESS "proxy__ossify()" --rpc-url=$RPC_URL --account acc2 ...   # from the admin

cast call $PROXY_ADDRESS "proxy__getIsOssified()(bool)" --rpc-url=$RPC_URL  # → true
cast call $PROXY_ADDRESS "proxy__getAdmin()(address)"   --rpc-url=$RPC_URL  # → 0x0
```

Afterwards `proxy__upgradeTo`, `proxy__upgradeToAndCall` and `proxy__changeAdmin` revert
`ProxyIsOssified` (`0xb83646a9`) for **every** caller including the former admin —
`_onlyAdmin` checks the zero-admin case before the identity case, so the error is never a
misleading `NotAdmin`. `just upgrade-live-*` fails during simulation and deploys nothing.

All reads and `updateModuleCache` keep working. Ossification freezes the code, not the
contract.

---

## Error selectors

| Selector | Error | Meaning |
|---|---|---|
| `0xb83646a9` | `ProxyIsOssified()` | proxy frozen; no admin action possible |
| `0x7bfa4b9f` | `NotAdmin()` | caller is not the proxy admin |
| `0x469d37e5` | `ModuleCacheNotInitialized(uint256)` | call `updateModuleCache` for that id |
| `0x952a9010` | `ModuleDoesNotSupportQueueOperations(address)` | non-CSM module; queue ops unavailable |
| `0x109cdd5b` | `InvalidQueuePriority(uint256,uint256)` | requested priority > `QUEUE_LOWEST_PRIORITY` |
