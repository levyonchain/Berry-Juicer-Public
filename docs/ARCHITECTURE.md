# Architecture

Berry Juicer deploys one isolated vault per position and keeps the proprietary
position strategy closed. This document describes the public components in this
repository and the seam where the proprietary logic plugs in.

## Components

```
   creator / agent
        │  createVault(token, amount)   (creator triggers + pays gas)
        ▼
  ┌─────────────────────┐   clones (EIP-1167)   ┌────────────────────────┐
  │  BerryJuicerFactory  │ ───────────────────▶ │  BerryJuicerVault (×N)  │  one per position
  │  - shared config      │                      │  - custodies ONLY its   │
  │  - operator (handler) │                      │    own principal + fees │
  │  - per-position index │                      │  - fee split + payout   │
  └─────────────────────┘                       └───────────┬────────────┘
                                                             │ IJuicerStrategy (seam)
                                                             ▼
                                                 ┌────────────────────────┐
                                                 │   Juicer Strategy        │  proprietary, NOT in repo
                                                 │   - single-sided V4 math │
                                                 │   - ranging/rebalancing  │
                                                 └────────────────────────┘
                                                             │ creator share (quote)
                                                             ▼
                                                 ┌────────────────────────┐
                                                 │  IInferenceRouter        │  records entitlement;
                                                 │  (off-chain fulfillment) │  backend provisions
                                                 └────────────────────────┘  inference via partners
```

## Why one vault per position

A single shared vault holding every creator's funds would be one contract, one
bug, everyone's principal, a large honeypot and a single point of failure. Berry
Juicer instead deploys an isolated vault per position as an EIP-1167 minimal-proxy
clone:

- **Isolated custody.** Each clone has its own storage and its own balance and
  holds only its own creator's principal and fees. A problem in one position's
  vault cannot reach another's.
- **Cheap deploys.** A clone is a ~45-byte proxy delegating to one shared
  implementation, far cheaper than deploying full bytecode per position. The
  creator pays this gas.
- **Funds custody lives in the clone, not the strategy.** The strategy is logic
  the vault calls; it is not a shared pot. This is what makes the isolation real
  rather than cosmetic.

## The master handler

The `operator` recorded on the factory and clones is the master-handler wallet,
intended to be a policy-scoped server wallet (e.g. Privy) that triggers harvests
across many vaults. `harvest` is permissionless and always routes the creator
share to the position's creator (as inference) and the margin to the protocol, so
the operator can only trigger work, never divert funds.

## Inference is fulfilled off-chain

AI inference is not an on-chain asset. On harvest, a vault forwards the creator's
share (in the quote asset) to the `InferenceRouter` and records an on-chain
entitlement (an event). Berry's backend watches those entitlements and provisions
inference to the creator through partner programs. Because inference is sourced at
a discount, the creator's credited value typically buys more compute than its face
value, but that conversion happens off-chain and is not part of the contracts.

## Open vs closed

| Open (this repo)                | Closed (not in repo)                       |
| ------------------------------- | ------------------------------------------ |
| Factory, vault, interfaces      | Single-sided V4 ranging & rebalancing      |
| YieldSplit (published split)    | Fee accounting internals                   |
| JuicerLens (read-only)          | Off-chain inference provisioning backend   |
| TypeScript SDK                  |                                            |

## Trust properties

- **Isolated, per-position custody** as above.
- **Permissionless harvest** that cannot divert funds.
- **Principal is always returned** on withdraw; if inference is unavailable at
  exit, the creator's fee share falls back to quote so funds are never trapped.
- **Creator-share floor.** `YieldSplit` rejects any configuration putting the
  creator below 50%, so the split cannot be quietly turned against them.
- **Single-initialization** clones; a vault cannot be re-initialized.
- **Reentrancy-guarded** state-changing entry points.

The strategy carries its own risk surface (concentrated-liquidity behaviour),
documented separately at release.
