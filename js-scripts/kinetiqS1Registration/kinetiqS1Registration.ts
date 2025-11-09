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

const {
  KV_REST_API_URL: kvUrl,
  KV_REST_API_TOKEN: kvToken,
  KINETIQ_DISTRIBUTION_TIMESTAMP,
  KINETIQ_SIGNED_AT_MS,
} = process.env;

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
type AcceptTermsMessage = {
  hyperliquidChain: string;
  message: string;
  cid: string;
  time: bigint;
};

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

function buildTypedData(timestamp: number) {
  const message: AcceptTermsMessage = {
    hyperliquidChain: HYPERLIQUID_CHAIN,
    message: TERMS_MESSAGE,
    cid: TERMS_CID,
    time: BigInt(timestamp),
  };

  const typedData = {
    primaryType: "AcceptTerms" as const,
    domain: KINETIQ_DOMAIN,
    types: ACCEPT_TERMS_TYPES,
    message,
  };

  const hash = TypedDataEncoder.hash(
    typedData.domain,
    typedData.types,
    typedData.message
  );

  return { typedData, hash };
}

function writeBatch(
  timestamp: string,
  transactions: { to: string; value: string; data: string }[]
) {
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
  const sanitizedTs = timestamp.replace(/[:.]/g, "-");
  const baseName = `KinetiqS1Registration_${sanitizedTs}`;
  const file = path.join(dir, `${baseName}.json`);
  fs.writeFileSync(file, JSON.stringify(batch, null, 2));
  return { file, baseName, dir };
}

function writeSummary(options: {
  timestamp: string;
  signTimestamp: number;
  wallets: { address: string; balance: string }[];
  hash: string;
  typedData: ReturnType<typeof buildTypedData>["typedData"];
  batchFile: string;
  baseName: string;
  dir: string;
}) {
  const { timestamp, signTimestamp, wallets, hash, typedData, batchFile, baseName, dir } =
    options;

  const displayMessage = {
    hyperliquidChain: typedData.message.hyperliquidChain,
    message: typedData.message.message,
    cid: typedData.message.cid,
    time: typedData.message.time.toString(),
  };

  const summary = {
    timestamp,
    signTimestamp,
    signTimestampIso: new Date(signTimestamp).toISOString(),
    pointsId: POINTS_ID_KINETIQ_S1,
    hash,
    typedData: {
      primaryType: typedData.primaryType,
      domain: typedData.domain,
      types: typedData.types,
      message: displayMessage,
    },
    files: {
      batch: path.basename(batchFile),
    },
    wallets: wallets.map(({ address, balance }, batchIndex) => ({
      address,
      kinetiqPoints: balance,
      rawData: { ...displayMessage },
      hash,
      batchIndex,
      signedInTransaction: null as string | null,
      signatureEventLogIndex: null as number | null,
    })),
  };

  const summaryFile = path.join(dir, `${baseName}_summary.json`);
  fs.writeFileSync(summaryFile, JSON.stringify(summary, null, 2));
  return summaryFile;
}

async function main() {
  // Fetch executed distributions from HyperEVM (with hl: prefix)
  const executed = await kvGet<string[]>("hl:distributions:executed");
  if (!executed || executed.length === 0) {
    throw new Error("No executed distributions in KV for HyperEVM");
  }

  const timestamp =
    KINETIQ_DISTRIBUTION_TIMESTAMP && executed.includes(KINETIQ_DISTRIBUTION_TIMESTAMP)
      ? KINETIQ_DISTRIBUTION_TIMESTAMP
      : executed[executed.length - 1];

  if (KINETIQ_DISTRIBUTION_TIMESTAMP && KINETIQ_DISTRIBUTION_TIMESTAMP !== timestamp) {
    console.warn(
      `Provided timestamp ${KINETIQ_DISTRIBUTION_TIMESTAMP} not executed. Using ${timestamp}.`
    );
  }

  const meta = await fetchDistribution(timestamp);
  const wallets = await fetchWallets(timestamp);

  // Filter addresses with positive Kinetiq S1 balances
  const walletsWithKinetiq = Object.entries(wallets)
    .map(([address, points]) => {
      const value = points[POINTS_ID_KINETIQ_S1];
      if (value === undefined || value === "0") return null;
      return { address, balance: value };
    })
    .filter((entry): entry is { address: string; balance: string } => entry !== null);

  if (walletsWithKinetiq.length === 0) {
    console.log("No wallets with Kinetiq S1 balances found");
    return;
  }

  console.log(`Distribution: ${timestamp} (root: ${meta.root || "N/A"})`);
  console.log(`Wallets to process: ${walletsWithKinetiq.length}`);

  // Use provided timestamp override or capture the current queue time
  const manualSignedAt = KINETIQ_SIGNED_AT_MS ? Number(KINETIQ_SIGNED_AT_MS) : undefined;
  if (KINETIQ_SIGNED_AT_MS && Number.isNaN(manualSignedAt)) {
    throw new Error(`Invalid KINETIQ_SIGNED_AT_MS value: ${KINETIQ_SIGNED_AT_MS}`);
  }
  const signTimestamp = manualSignedAt ?? Date.now();
  const transactions: { to: string; value: string; data: string }[] = [];

  // Create single EIP-712 hash that all wallets will sign
  // The wallet address is bound via Safe's ERC-1271 verification, not in the typed data
  const { typedData, hash: messageHash } = buildTypedData(signTimestamp);

  for (const { address, balance } of walletsWithKinetiq) {
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

  const { file: batchFile, baseName, dir } = writeBatch(timestamp, transactions);
  const summaryFile = writeSummary({
    timestamp,
    signTimestamp,
    wallets: walletsWithKinetiq,
    hash: messageHash,
    typedData,
    batchFile,
    baseName,
    dir,
  });

  console.log(`\nSafe batch written to ${batchFile}`);
  console.log(`Summary written to ${summaryFile}`);
  console.log(`Total transactions: ${transactions.length}`);
  console.log(`Signature timestamp: ${new Date(signTimestamp).toISOString()}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
