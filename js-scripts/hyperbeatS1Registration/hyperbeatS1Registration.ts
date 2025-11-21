import "dotenv/config";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { TxBuilder } = require("@morpho-labs/gnosis-tx-builder");
import { getAddress, keccak256, toUtf8Bytes } from "ethers";
import fs from "fs";
import path from "path";
import {
  SIGN_MESSAGE_LIB,
  SIGN_MESSAGE_LIB_INTERFACE,
  HYPEREVM_ADMIN_SAFE,
  HYPEREVM_MODULE,
  RUMPEL_MODULE_INTERFACE,
  HYPERBEAT_TERMS_MESSAGE,
} from "./hyperbeatS1Constants";
import { POINTS_ID_HYPERBEAT_S1 } from "../points";

const {
  KV_REST_API_URL: kvUrl,
  KV_REST_API_TOKEN: kvToken,
  HYPERBEAT_DISTRIBUTION_TIMESTAMP,
  HYPERBEAT_SIGNED_AT_MS,
  HYPERBEAT_BATCH_SIZE,
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

type WalletSummary = {
  address: string;
  balance: string;
  message: string;
  timestamp: string;
  hash: string;
  batchIndex: number;
  signedInTransaction: string | null;
  signatureEventLogIndex: number | null;
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

function buildMessage(address: string, timestampMs: number) {
  const checksumAddress = getAddress(address);
  const timestampIso = new Date(timestampMs).toISOString();
  const message = `${HYPERBEAT_TERMS_MESSAGE}\n\nAddress: ${checksumAddress}\nTimestamp: ${timestampIso}`;
  const hash = keccak256(toUtf8Bytes(message));
  return { message, hash, timestampIso, checksumAddress };
}

function writeBatch(
  timestamp: string,
  transactions: { to: string; value: string; data: string }[],
  part: number,
  totalParts: number
) {
  const batch = TxBuilder.batch(HYPEREVM_ADMIN_SAFE, transactions, {
    chainId: 999,
  });
  const dir = path.join(
    process.cwd(),
    "js-scripts",
    "hyperbeatS1Registration",
    "safe-batches"
  );
  fs.mkdirSync(dir, { recursive: true });
  const sanitizedTs = timestamp.replace(/[:.]/g, "-");
  const suffix = totalParts > 1 ? `_part${part + 1}-of-${totalParts}` : "";
  const baseName = `HyperbeatS1Registration_${sanitizedTs}${suffix}`;
  const file = path.join(dir, `${baseName}.json`);
  fs.writeFileSync(file, JSON.stringify(batch, null, 2));
  return { file, baseName, dir };
}

function writeSummary(options: {
  timestamp: string;
  signTimestamp: number;
  wallets: WalletSummary[];
  batchFile: string;
  baseName: string;
  dir: string;
  part: number;
  totalParts: number;
}) {
  const { timestamp, signTimestamp, wallets, batchFile, baseName, dir, part, totalParts } =
    options;

  const messageExample = wallets[0]
    ? {
        address: wallets[0].address,
        message: wallets[0].message,
        timestamp: wallets[0].timestamp,
        hash: wallets[0].hash,
      }
    : null;

  const summary = {
    timestamp,
    signTimestamp,
    signTimestampIso: new Date(signTimestamp).toISOString(),
    pointsId: POINTS_ID_HYPERBEAT_S1,
    messageExample,
    batchPart: part + 1,
    batchParts: totalParts,
    files: {
      batch: path.basename(batchFile),
    },
    wallets: wallets.map((wallet) => ({
      address: wallet.address,
      hyperbeatPoints: wallet.balance,
      message: wallet.message,
      timestamp: wallet.timestamp,
      hash: wallet.hash,
      batchIndex: wallet.batchIndex,
      signedInTransaction: wallet.signedInTransaction,
      signatureEventLogIndex: wallet.signatureEventLogIndex,
    })),
  };

  const summaryFile = path.join(dir, `${baseName}_summary.json`);
  fs.writeFileSync(summaryFile, JSON.stringify(summary, null, 2));
  return summaryFile;
}

async function main() {
  const executed = await kvGet<string[]>("hl:distributions:executed");
  if (!executed || executed.length === 0) {
    throw new Error("No executed distributions in KV for HyperEVM");
  }

  const timestamp =
    HYPERBEAT_DISTRIBUTION_TIMESTAMP && executed.includes(HYPERBEAT_DISTRIBUTION_TIMESTAMP)
      ? HYPERBEAT_DISTRIBUTION_TIMESTAMP
      : executed[executed.length - 1];

  if (HYPERBEAT_DISTRIBUTION_TIMESTAMP && HYPERBEAT_DISTRIBUTION_TIMESTAMP !== timestamp) {
    console.warn(
      `Provided timestamp ${HYPERBEAT_DISTRIBUTION_TIMESTAMP} not executed. Using ${timestamp}.`
    );
  }

  const meta = await fetchDistribution(timestamp);
  const wallets = await fetchWallets(timestamp);

  const walletsWithHyperbeat = Object.entries(wallets)
    .map(([address, points]) => {
      const value = points[POINTS_ID_HYPERBEAT_S1];
      if (value === undefined || value === "0") return null;
      return { address, balance: value };
    })
    .filter((entry): entry is { address: string; balance: string } => entry !== null);

  if (walletsWithHyperbeat.length === 0) {
    console.log("No wallets with Hyperbeat S1 balances found");
    return;
  }

  console.log(`Distribution: ${timestamp} (root: ${meta.root || "N/A"})`);
  console.log(`Wallets to process: ${walletsWithHyperbeat.length}`);

  const manualSignedAt = HYPERBEAT_SIGNED_AT_MS ? Number(HYPERBEAT_SIGNED_AT_MS) : undefined;
  if (HYPERBEAT_SIGNED_AT_MS && Number.isNaN(manualSignedAt)) {
    throw new Error(`Invalid HYPERBEAT_SIGNED_AT_MS value: ${HYPERBEAT_SIGNED_AT_MS}`);
  }
  const signTimestamp = manualSignedAt ?? Date.now();
  const transactions: { to: string; value: string; data: string }[] = [];
  const walletSummaries: WalletSummary[] = [];

  for (const { address, balance } of walletsWithHyperbeat) {
    const batchIndex = transactions.length;

    const { message, hash: messageHash, timestampIso, checksumAddress } = buildMessage(
      address,
      signTimestamp
    );

    const signMessageData = SIGN_MESSAGE_LIB_INTERFACE.encodeFunctionData(
      "signMessage",
      [messageHash]
    );

    const executeTransactionData = RUMPEL_MODULE_INTERFACE.encodeFunctionData(
      "exec",
      [
        [
          {
            safe: address,
            to: SIGN_MESSAGE_LIB,
            data: signMessageData,
            operation: 1,
          },
        ],
      ]
    );

    transactions.push({
      to: HYPEREVM_MODULE,
      value: "0",
      data: executeTransactionData,
    });

    walletSummaries.push({
      address: checksumAddress,
      balance,
      message,
      timestamp: timestampIso,
      hash: messageHash,
      batchIndex,
      signedInTransaction: null,
      signatureEventLogIndex: null,
    });

    console.log(`${address}: ${balance} Hyperbeat points`);
  }

  const batchSize = HYPERBEAT_BATCH_SIZE ? Number(HYPERBEAT_BATCH_SIZE) : 75;
  if (Number.isNaN(batchSize) || batchSize <= 0) {
    throw new Error(`Invalid HYPERBEAT_BATCH_SIZE: ${HYPERBEAT_BATCH_SIZE}`);
  }

  const parts: { txs: typeof transactions; wallets: WalletSummary[] }[] = [];
  for (let i = 0; i < transactions.length; i += batchSize) {
    parts.push({
      txs: transactions.slice(i, i + batchSize),
      wallets: walletSummaries.slice(i, i + batchSize),
    });
  }

  console.log(`Splitting into ${parts.length} batches of up to ${batchSize} txs each`);

  parts.forEach((part, idx) => {
    const { file: batchFile, baseName, dir } = writeBatch(timestamp, part.txs, idx, parts.length);
    const summaryFile = writeSummary({
      timestamp,
      signTimestamp,
      wallets: part.wallets,
      batchFile,
      baseName,
      dir,
      part: idx,
      totalParts: parts.length,
    });

    console.log(`\nBatch ${idx + 1}/${parts.length} written to ${batchFile}`);
    console.log(`Summary written to ${summaryFile}`);
    console.log(`Transactions in batch: ${part.txs.length}`);
  });

  console.log(`\nTotal transactions: ${transactions.length}`);
  console.log(`Signature timestamp: ${new Date(signTimestamp).toISOString()}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
