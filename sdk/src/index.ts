/**
 * @berry/juicer-sdk
 *
 * A small, dependency-light client for Berry Juicer. It wraps the public vault
 * surface so wallets and agents can read positions and build transactions
 * without hand-assembling ABI calls. It speaks only to the open contracts; it
 * has no knowledge of the proprietary position strategy.
 */
import {
  type Address,
  type PublicClient,
  type WalletClient,
} from "viem";

/** How a creator elects to receive yield. Mirrors the on-chain enum. */
export enum YieldMode {
  Quote = 0,
  Inference = 1,
}

/** Minimal ABI for the public vault surface the SDK needs. */
export const berryJuicerAbi = [
  {
    type: "function",
    name: "deposit",
    stateMutability: "nonpayable",
    inputs: [
      { name: "token", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "mode", type: "uint8" },
    ],
    outputs: [{ name: "positionId", type: "uint256" }],
  },
  {
    type: "function",
    name: "withdraw",
    stateMutability: "nonpayable",
    inputs: [{ name: "positionId", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "setYieldMode",
    stateMutability: "nonpayable",
    inputs: [
      { name: "positionId", type: "uint256" },
      { name: "mode", type: "uint8" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "protocolFeeBps",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "pendingYield",
    stateMutability: "view",
    inputs: [{ name: "positionId", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "positionInfo",
    stateMutability: "view",
    inputs: [{ name: "positionId", type: "uint256" }],
    outputs: [
      { name: "creator", type: "address" },
      { name: "token", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "mode", type: "uint8" },
    ],
  },
] as const;

export interface PositionInfo {
  creator: Address;
  token: Address;
  amount: bigint;
  mode: YieldMode;
}

export interface JuicerClientConfig {
  vault: Address;
  publicClient: PublicClient;
  /** Optional. Required only for write calls (deposit, withdraw, setYieldMode). */
  walletClient?: WalletClient;
}

/**
 * Typed client for a single Berry Juicer vault deployment.
 *
 * Reads work with just a public client. Writes require a wallet client; the
 * SDK never holds or sees a private key, it only asks the provided wallet to
 * sign.
 */
export class JuicerClient {
  private readonly vault: Address;
  private readonly publicClient: PublicClient;
  private readonly walletClient?: WalletClient;

  constructor(config: JuicerClientConfig) {
    this.vault = config.vault;
    this.publicClient = config.publicClient;
    this.walletClient = config.walletClient;
  }

  /** The protocol fee, in basis points. */
  async protocolFeeBps(): Promise<bigint> {
    return this.publicClient.readContract({
      address: this.vault,
      abi: berryJuicerAbi,
      functionName: "protocolFeeBps",
    });
  }

  /** Static parameters of a position. */
  async positionInfo(positionId: bigint): Promise<PositionInfo> {
    const [creator, token, amount, mode] = await this.publicClient.readContract({
      address: this.vault,
      abi: berryJuicerAbi,
      functionName: "positionInfo",
      args: [positionId],
    });
    return { creator, token, amount, mode: mode as YieldMode };
  }

  /** Accrued, undistributed yield for a position, in quote-asset terms. */
  async pendingYield(positionId: bigint): Promise<bigint> {
    return this.publicClient.readContract({
      address: this.vault,
      abi: berryJuicerAbi,
      functionName: "pendingYield",
      args: [positionId],
    });
  }

  /** Split pending yield into creator and protocol shares, off-chain. */
  async pendingSplit(positionId: bigint): Promise<{ creator: bigint; protocol: bigint }> {
    const [pending, feeBps] = await Promise.all([
      this.pendingYield(positionId),
      this.protocolFeeBps(),
    ]);
    const protocol = (pending * feeBps) / 10_000n;
    return { creator: pending - protocol, protocol };
  }

  /** Open a position. Requires a wallet client and a prior token approval. */
  async deposit(token: Address, amount: bigint, mode: YieldMode): Promise<`0x${string}`> {
    const wallet = this.requireWallet();
    return wallet.writeContract({
      address: this.vault,
      abi: berryJuicerAbi,
      functionName: "deposit",
      args: [token, amount, mode],
      account: wallet.account ?? null,
      chain: wallet.chain,
    });
  }

  /** Change how a position's yield is paid out. */
  async setYieldMode(positionId: bigint, mode: YieldMode): Promise<`0x${string}`> {
    const wallet = this.requireWallet();
    return wallet.writeContract({
      address: this.vault,
      abi: berryJuicerAbi,
      functionName: "setYieldMode",
      args: [positionId, mode],
      account: wallet.account ?? null,
      chain: wallet.chain,
    });
  }

  /** Withdraw a position in full. */
  async withdraw(positionId: bigint): Promise<`0x${string}`> {
    const wallet = this.requireWallet();
    return wallet.writeContract({
      address: this.vault,
      abi: berryJuicerAbi,
      functionName: "withdraw",
      args: [positionId],
      account: wallet.account ?? null,
      chain: wallet.chain,
    });
  }

  private requireWallet(): WalletClient {
    if (!this.walletClient) {
      throw new Error("A walletClient is required for write operations.");
    }
    return this.walletClient;
  }
}
