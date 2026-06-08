# Berry Juicer

Single-sided yield on idle token supply, built for AI agents.

Berry Juicer lets a creator, human or autonomous agent, put idle token supply to
work as a single-sided liquidity position that earns swap fees. Each deposit gets
its own isolated vault (deployed per position), so funds are never pooled across
creators. The fees are
split: the creator's share is credited as AI inference, idle supply becomes the
compute the agent runs on, while the protocol retains a margin. The deposited
supply remains the creator's principal and is returned on withdraw.

This repository contains the **public** components of Berry Juicer: the
interfaces, the orchestration vault, periphery, and the TypeScript SDK. The
proprietary position strategy (how single-sided ranges are chosen and
maintained on Uniswap V4) is **not** included; it plugs in behind a public
interface. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full
open/closed boundary.

> Part of the Berry Finance aftermarket suite on Base.

## Layout

```
contracts/
  interfaces/        IBerryJuicer, IJuicerStrategy, IInferenceRouter
  libraries/         YieldSplit (open split math)
  periphery/         JuicerLens (read-only convenience layer)
  BerryJuicerVault.sol     one isolated position vault (clone target)
  BerryJuicerFactory.sol   deploys one vault per position (EIP-1167 clones)
sdk/                 @berry/juicer-sdk (TypeScript client)
test/                Foundry tests + reference mocks
script/              deployment scripts
docs/                architecture and design notes
```

## Build and test

This repo supports both Foundry and Hardhat.

### Foundry

```bash
forge install foundry-rs/forge-std   # first time only
forge build
forge test -vvv
```

### Hardhat

```bash
npm install
npx hardhat compile
```

### SDK

```bash
cd sdk
npm install
npm run build
```

## Deployment

The vault is deployed against an already-deployed strategy address:

```bash
JUICER_STRATEGY=0x... FEE_RECIPIENT=0x... PROTOCOL_FEE_BPS=2000 \
forge script script/Deploy.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --verify
```

Copy `.env.example` to `.env` and fill in your values first. Never commit `.env`.

## Security

See [`SECURITY.md`](SECURITY.md). Report vulnerabilities privately to
`security@berryfi.org`. A bug bounty runs alongside the independent audit prior
to mainnet.

## License

Business Source License 1.1. See [`LICENSE`](LICENSE).
