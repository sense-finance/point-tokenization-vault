import "dotenv/config";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { TxBuilder } = require("@morpho-labs/gnosis-tx-builder");
import { TypedDataEncoder } from "ethers";
import fs from "fs";
import path from "path";
import {
  SIGN_MESSAGE_LIB,
  SIGN_MESSAGE_LIB_INTERFACE,
  HYPEREVM_ADMIN_SAFE,
  HYPEREVM_MODULE,
  RUMPEL_MODULE_INTERFACE,
  KINETIQ_DOMAIN,
  ACCEPT_TERMS_TYPES,
  TERMS_MESSAGE,
  TERMS_CID,
  HYPERLIQUID_CHAIN,
} from "./kinetiqS1Constants";
import { POINTS_ID_KINETIQ_S1 } from "./utils";

const { KV_REST_API_URL: kvUrl, KV_REST_API_TOKEN: kvToken } = process.env;

if (!kvUrl || !kvToken) {
  throw new Error("Missing KV_REST_API_URL or KV_REST_API_TOKEN");
}

const KV_URL = kvUrl.replace(/\/$/, "");
const KV_TOKEN = kvToken;

type DistributionMeta = {
  timestamp: string;
  root?: string;
};

type WalletMap = Record<string, Record<string, string>>;

async function kvGet<T>(key: string): Promise<T | null> {
  const url = `${KV_URL}/get/${encodeURIComponent(key)}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${KV_TOKEN}` },
  });
  if (!res.ok) {
    throw new Error(`KV get failed for ${key}: ${res.status} ${res.statusText}`);
  }
  const json = (await res.json()) as { result?: T };
  const value = json.result;
  if (value == null) return null;
  if (typeof value === "string") {
    try {
      return JSON.parse(value) as T;
    } catch {
      return value as T;
    }
  }
  return value;
}

async function fetchDistribution(timestamp: string): Promise<DistributionMeta> {
  const meta = await kvGet<DistributionMeta>(`hl:distributions:${timestamp}`);
  if (!meta) throw new Error(`Distribution ${timestamp} not found`);
  return meta;
}

async function fetchWallets(timestamp: string): Promise<WalletMap> {
  const wallets = await kvGet<WalletMap>(
    `hl:distributions:${timestamp}:wallets`
  );
  if (!wallets) {
    throw new Error(`Distribution ${timestamp} has no wallet snapshot`);
  }
  return wallets;
}

function createEIP712Hash(timestamp: number): string {
  const message = {
    message: TERMS_MESSAGE,
    time: BigInt(timestamp),
    cid: TERMS_CID,
    hyperliquidChain: HYPERLIQUID_CHAIN,
  };

  // Create EIP-712 hash
  // Note: The wallet address is bound via Safe's ERC-1271 signature verification,
  // not in the typed data itself
  const hash = TypedDataEncoder.hash(
    KINETIQ_DOMAIN,
    ACCEPT_TERMS_TYPES,
    message
  );

  return hash;
}

function writeBatch(
  timestamp: string,
  transactions: { to: string; value: string; data: string }[]
): string {
  const batch = TxBuilder.batch(HYPEREVM_ADMIN_SAFE, transactions, {
    chainId: 999,
  });
  const dir = path.join(
    process.cwd(),
    "js-scripts",
    "kinetiqS1Registration",
    "safe-batches"
  );
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(
    dir,
    `KinetiqS1Registration_${timestamp.replace(/[:.]/g, "-")}.json`
  );
  fs.writeFileSync(file, JSON.stringify(batch, null, 2));
  return file;
}

async function main() {
  const args = process.argv.slice(2);
  const flags = {
    timestamp: undefined as string | undefined,
    signedAt: undefined as number | undefined,
  };

  for (const arg of args) {
    if (arg.startsWith("--timestamp=")) {
      flags.timestamp = arg.split("=")[1];
    } else if (arg.startsWith("--signed-at=")) {
      flags.signedAt = Number(arg.split("=")[1]);
    }
  }

  // Fetch executed distributions from HyperEVM (with hl: prefix)
  const executed = await kvGet<string[]>("hl:distributions:executed");
  if (!executed || executed.length === 0) {
    throw new Error("No executed distributions in KV for HyperEVM");
  }

  const timestamp =
    flags.timestamp && executed.includes(flags.timestamp)
      ? flags.timestamp
      : executed[executed.length - 1];

  if (flags.timestamp && flags.timestamp !== timestamp) {
    console.warn(
      `Provided timestamp ${flags.timestamp} not executed. Using ${timestamp}.`
    );
  }

  const meta = await fetchDistribution(timestamp);
  const wallets = await fetchWallets(timestamp);

  // Filter addresses with positive Kinetiq S1 balances
  const addressesWithKinetiq = Object.entries(wallets)
    .filter(([, points]) => {
      const value = points[POINTS_ID_KINETIQ_S1];
      return value !== undefined && value !== "0";
    })
    .map(([address]) => address);

  if (addressesWithKinetiq.length === 0) {
    console.log("No wallets with Kinetiq S1 balances found");
    return;
  }

  console.log(`Distribution: ${timestamp} (root: ${meta.root || "N/A"})`);
  console.log(`Wallets to process: ${addressesWithKinetiq.length}`);

  // Use deterministic timestamp: explicit flag, or derive from distribution timestamp
  // This ensures regenerated batches are identical for auditing
  const signTimestamp = flags.signedAt ?? new Date(timestamp).getTime();
  const transactions: { to: string; value: string; data: string }[] = [];

  // Create single EIP-712 hash that all wallets will sign
  // The wallet address is bound via Safe's ERC-1271 verification, not in the typed data
  const messageHash = createEIP712Hash(signTimestamp);

  for (const address of addressesWithKinetiq) {
    const balance = wallets[address][POINTS_ID_KINETIQ_S1];

    // Encode signMessage call
    const signMessageData = SIGN_MESSAGE_LIB_INTERFACE.encodeFunctionData(
      "signMessage",
      [messageHash]
    );

    // Encode exec call to Rumpel module
    const executeTransactionData = RUMPEL_MODULE_INTERFACE.encodeFunctionData(
      "exec",
      [
        [
          {
            safe: address,
            to: SIGN_MESSAGE_LIB,
            data: signMessageData,
            operation: 1, // Delegatecall
          },
        ],
      ]
    );

    transactions.push({
      to: HYPEREVM_MODULE,
      value: "0",
      data: executeTransactionData,
    });

    console.log(`${address}: ${balance} Kinetiq points`);
  }

  const file = writeBatch(timestamp, transactions);
  console.log(`\nSafe batch written to ${file}`);
  console.log(`Total transactions: ${transactions.length}`);
  console.log(`Signature timestamp: ${new Date(signTimestamp).toISOString()}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
