/**
 * @berry/juicer-sdk
 *
 * A small, dependency-light client for Berry Juicer. Berry Juicer deploys one
 * isolated vault per position (via a factory); this SDK wraps both the factory
 * (to create positions and enumerate them) and individual position vaults (to
 * read state and exit). It speaks only to the open contracts; it has no
 * knowledge of the proprietary position strategy.
 *
 * Payout model: a position's deposited supply is the creator's principal and is
 * returned on withdraw. The fees it earns are split; the creator's share is
 * credited as AI inference (fulfilled off-chain via partner programs) and the
 * protocol keeps the remainder as margin. The creator does not receive the quote
 * asset for their fee share.
 */
import { type Address, type PublicClient, type WalletClient } from "viem";

/** ABI for the factory that deploys per-position vaults. */
export const factoryAbi = [
  {
    type: "function",
    name: "createVault",
    stateMutability: "nonpayable",
    inputs: [
      { name: "token", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "vault", type: "address" }],
  },
  {
    type: "function",
    name: "vaultsOf",
    stateMutability: "view",
    inputs: [{ name: "creator", type: "address" }],
    outputs: [{ name: "", type: "address[]" }],
  },
  {
    type: "function",
    name: "creatorShareBps",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

/** ABI for an individual position vault. */
export const vaultAbi = [
  { type: "function", name: "harvest", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "withdraw", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "creator", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "address" }] },
  {
    type: "function",
    name: "creatorShareBps",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "pendingFees",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "position",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "token", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "open", type: "bool" },
    ],
  },
] as const;

export interface PositionInfo {
  token: Address;
  amount: bigint;
  open: boolean;
}

interface ClientCtx {
  publicClient: PublicClient;
  walletClient?: WalletClient;
}

function requireWallet(ctx: ClientCtx): WalletClient {
  if (!ctx.walletClient) throw new Error("A walletClient is required for write operations.");
  return ctx.walletClient;
}

/** Client for the Berry Juicer factory: create positions and enumerate them. */
export class JuicerFactoryClient {
  constructor(
    private readonly factory: Address,
    private readonly ctx: ClientCtx,
  ) {}

  /** Create an isolated position vault, depositing `amount` of `token`. Requires approval to the factory. */
  async createVault(token: Address, amount: bigint): Promise<`0x${string}`> {
    const wallet = requireWallet(this.ctx);
    return wallet.writeContract({
      address: this.factory,
      abi: factoryAbi,
      functionName: "createVault",
      args: [token, amount],
      account: wallet.account ?? null,
      chain: wallet.chain,
    });
  }

  /** All vault addresses a creator owns. */
  async vaultsOf(creator: Address): Promise<readonly Address[]> {
    return this.ctx.publicClient.readContract({
      address: this.factory,
      abi: factoryAbi,
      functionName: "vaultsOf",
      args: [creator],
    });
  }
}

/** Client for a single Berry Juicer position vault. */
export class JuicerVaultClient {
  constructor(
    private readonly vault: Address,
    private readonly ctx: ClientCtx,
  ) {}

  async creator(): Promise<Address> {
    return this.ctx.publicClient.readContract({ address: this.vault, abi: vaultAbi, functionName: "creator" });
  }

  async creatorShareBps(): Promise<bigint> {
    return this.ctx.publicClient.readContract({ address: this.vault, abi: vaultAbi, functionName: "creatorShareBps" });
  }

  async position(): Promise<PositionInfo> {
    const [token, amount, open] = await this.ctx.publicClient.readContract({
      address: this.vault,
      abi: vaultAbi,
      functionName: "position",
    });
    return { token, amount, open };
  }

  async pendingFees(): Promise<bigint> {
    return this.ctx.publicClient.readContract({ address: this.vault, abi: vaultAbi, functionName: "pendingFees" });
  }

  /** Project how pending fees split: creator value (credited as inference) and protocol margin. */
  async pendingSplit(): Promise<{ creatorValue: bigint; protocolMargin: bigint }> {
    const [fees, shareBps] = await Promise.all([this.pendingFees(), this.creatorShareBps()]);
    const marginBps = 10_000n - shareBps;
    const protocolMargin = (fees * marginBps) / 10_000n;
    return { creatorValue: fees - protocolMargin, protocolMargin };
  }

  /** Harvest fees (permissionless; proceeds route to the creator and protocol). */
  async harvest(): Promise<`0x${string}`> {
    const wallet = requireWallet(this.ctx);
    return wallet.writeContract({
      address: this.vault,
      abi: vaultAbi,
      functionName: "harvest",
      args: [],
      account: wallet.account ?? null,
      chain: wallet.chain,
    });
  }

  /** Withdraw the position in full (creator only). */
  async withdraw(): Promise<`0x${string}`> {
    const wallet = requireWallet(this.ctx);
    return wallet.writeContract({
      address: this.vault,
      abi: vaultAbi,
      functionName: "withdraw",
      args: [],
      account: wallet.account ?? null,
      chain: wallet.chain,
    });
  }
}
