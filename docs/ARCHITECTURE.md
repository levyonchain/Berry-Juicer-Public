# Architecture

Berry Juicer is split into an open orchestration layer and a closed position
strategy. This document describes the public components in this repository and
the seam where the proprietary logic plugs in.

## Components

```
                         ┌─────────────────────────┐
   creator / agent ─────▶│   BerryJuicerVault       │  (open, this repo)
                         │   - custody               │
                         │   - access control        │
                         │   - yield split           │
                         │   - payout routing         │
                         └────────────┬──────────────┘
                                      │ IJuicerStrategy (seam)
                                      ▼
                         ┌─────────────────────────┐
                         │  Juicer Strategy          │  (proprietary, NOT in repo)
                         │  - single-sided V4 ranging │
                         │  - placement & rebalancing │
                         │  - fee accounting          │
                         └─────────────────────────┘
```

### Open (in this repository)

- **`interfaces/IBerryJuicer.sol`** — the public vault surface: deposit,
  withdraw, set yield mode, read positions.
- **`interfaces/IJuicerStrategy.sol`** — the seam to the position strategy. The
  interface is public so integrators understand the boundary; the
  implementation is not.
- **`interfaces/IInferenceRouter.sol`** — the seam to the inference partner that
  fulfils the `Inference` yield mode.
- **`BerryJuicerVault.sol`** — the orchestration layer. Holds creator deposits,
  enforces who can do what, splits yield via `YieldSplit`, and routes payouts in
  quote asset or inference. Reviewable in full.
- **`libraries/YieldSplit.sol`** — pure split math. The split is a published
  protocol parameter, so it is open.
- **`periphery/JuicerLens.sol`** — read-only convenience layer for frontends and
  agents.
- **`sdk/`** — a TypeScript client over the public surface.

### Closed (not in this repository)

- The **Juicer position strategy**: how a single-sided range is chosen on
  Uniswap V4, how liquidity is placed and rebalanced, and how fees are accounted.
  This is the novel part of the system and is kept proprietary. It plugs in
  behind `IJuicerStrategy`.

## Why this split

The vault holds funds and enforces authorization, so it benefits most from being
public and reviewable: anyone can verify that the protocol cannot move a
creator's assets outside the defined paths, and that the yield split is exactly
as published. The strategy is where the genuine intellectual property lives, so
it stays closed. The interface boundary makes both possible at once.

## Trust properties

- **Non-custodial intent.** The vault custodies a creator's deposit only to
  deploy it via the strategy and to settle yield. Admin powers are limited to
  configuration (fee, fee recipient, inference router), never to seizing funds.
- **Permissionless distribution.** Anyone may trigger `distribute` for a
  position, but proceeds always go to that position's creator, so automation
  cannot divert yield.
- **Bounded fee.** `YieldSplit` rejects any split above its maximum, so a
  misconfigured fee reverts rather than over-charging.
- **Reentrancy-guarded** state-changing entry points.

These are the public, reviewable guarantees. The strategy carries its own risk
surface (concentrated-liquidity behaviour), documented separately at release.
