# Berry Juicer — Agent Skill

Put idle token supply to work and receive AI inference in return. Berry Juicer
deploys one isolated vault per position; agents use the same factory and vaults
as humans, with no agent-specific path.

Chain: Base. Factory address, quote asset, and creator share: see `GET /api/config`.

## Concepts

- **Factory** — deploys one isolated **vault** per deposit. The creator triggers
  creation and pays the gas.
- **Position vault** — a single position. It custodies only its own creator's
  principal and fees (positions are isolated from one another).
- **Principal** — the deposited supply (and any quote it converts into) belongs
  to the creator and is returned on withdraw.
- **Fees** — split: the **creator share** (e.g. 80%) is credited as **AI
  inference** (fulfilled off-chain via partner programs); the **protocol margin**
  (the remainder) is retained by the protocol. The creator does not receive the
  quote asset for their fee share. Because inference is sourced at a discount, the
  credited value typically buys more compute than its face value.

## On-chain surface (verify without trusting the API)

Factory:
- `createVault(token, amount) -> vault` — deploy an isolated position vault and
  deposit into it. Requires a prior ERC-20 approval of `amount` to the factory.
- `vaultsOf(creator) -> address[]` — all vaults a creator owns.

Vault (one per position):
- `harvest()` — permissionless; credits the creator inference for their share and
  sends the protocol its margin. Proceeds always route to the creator/protocol, so
  automation can trigger it without diverting funds.
- `withdraw()` — creator only; settles fees, then returns principal.
- `pendingFees() -> uint256`, `position() -> (token, amount, open)`, `creator()`.

## SDK

```ts
import { JuicerFactoryClient, JuicerVaultClient } from "@berry/juicer-sdk";

const factory = new JuicerFactoryClient(factoryAddress, { publicClient, walletClient });
await factory.createVault(token, amount); // approve the factory first

const vaults = await factory.vaultsOf(myAddress);
const vault = new JuicerVaultClient(vaults[0], { publicClient, walletClient });
const { creatorValue, protocolMargin } = await vault.pendingSplit();
```

## Typical agent flow

1. Read `GET /api/config` for the factory address, quote asset, and creator share.
2. Approve the token to the factory.
3. `createVault(token, amount)` to open an isolated position.
4. Poll the vault's `pendingFees` / `pendingSplit`; the creator share accrues as
   inference on harvest.
5. `withdraw()` to exit at any time and reclaim principal.
