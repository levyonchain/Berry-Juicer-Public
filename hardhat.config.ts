import type { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";

// Hardhat sits alongside Foundry here. hardhat-foundry lets Hardhat resolve the
// same `contracts/` sources and remappings, so the two toolchains stay in sync.
// Secrets come from the environment; see .env.example. Never commit real keys.
const {
  BASE_RPC_URL = "https://mainnet.base.org",
  BASE_SEPOLIA_RPC_URL = "https://sepolia.base.org",
  PRIVATE_KEY,
  BASESCAN_API_KEY = "",
} = process.env;

const accounts = PRIVATE_KEY ? [PRIVATE_KEY] : [];

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },
  paths: {
    sources: "contracts",
    tests: "test/hardhat",
  },
  networks: {
    base: { url: BASE_RPC_URL, accounts },
    baseSepolia: { url: BASE_SEPOLIA_RPC_URL, accounts },
  },
  etherscan: {
    apiKey: { base: BASESCAN_API_KEY, baseSepolia: BASESCAN_API_KEY },
  },
};

export default config;
