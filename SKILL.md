# Berry Juicer — Agent Skill

Turn idle token supply into yield, and take that yield as USD or as AI inference.
Built so agents operate on the same contracts and API as humans, with no
agent-specific path.

Chain: Base. Vault address and quote asset: see `GET /api/config`.

## Concepts

- **Position** — a single-sided liquidity position opened from a creator's
  deposited token supply. It earns swap fees over time.
- **Yield mode** — how the creator's share of yield is paid:
  - `Quote` (0): the pool's quote asset (e.g. WETH/USDC).
  - `Inference` (1): routed into AI inference credits via a partner program. An
    agent's idle supply becomes the compute it runs on.
- **Split** — accrued yield is divided between the creator and the protocol. The
  protocol fee (basis points) is published at `GET /api/config` and on-chain via
  `protocolFeeBps()`.

## On-chain surface (verify without trusting the API)

- `deposit(token, amount, mode) -> positionId` — open a position. Requires a
  prior ERC-20 approval of `amount` to the vault.
- `setYieldMode(positionId, mode)` — switch between `Quote` and `Inference`.
- `withdraw(positionId)` — exit in full at any time; settles outstanding yield,
  then returns remaining token and quote.
- `pendingYield(positionId) -> uint256` — accrued, undistributed yield (quote
  terms).
- `positionInfo(positionId) -> (creator, token, amount, mode)`.

`distribute(positionId)` is permissionless; proceeds always go to the position's
creator, so an automation agent may trigger payouts without being able to divert
them.

## SDK

`@berry/juicer-sdk` wraps the surface above:

```ts
import { JuicerClient, YieldMode } from "@berry/juicer-sdk";

const juicer = new JuicerClient({ vault, publicClient, walletClient });

// open a position, taking yield as inference
const tx = await juicer.deposit(token, amount, YieldMode.Inference);

// check the projected split
const { creator, protocol } = await juicer.pendingSplit(positionId);
```

## Typical agent flow

1. Read `GET /api/config` for the vault address, quote asset, and protocol fee.
2. Approve the token to the vault.
3. `deposit(token, amount, YieldMode.Inference)` to put idle supply to work and
   take yield as compute.
4. Poll `pendingYield` / `pendingSplit`; call `distribute` when worthwhile.
5. `withdraw` to exit at any time.
