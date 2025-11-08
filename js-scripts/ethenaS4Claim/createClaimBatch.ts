import { TxBuilder } from "@morpho-labs/gnosis-tx-builder";
import "dotenv/config";
import { AbiCoder, formatUnits, getAddress } from "ethers";
import fs from "fs";
import path from "path";
import { createPublicClient, http, Hex } from "viem";
import { mainnet } from "viem/chains";

import {
  RUMPEL_ADMIN_SAFE,
  RUMPEL_MODULE,
  RUMPEL_MODULE_INTERFACE,
} from "../resolvS1Registration/resolveS1Constants";

type DistributionMeta = {
  timestamp: string;
  root?: string;
};

type WalletMap = Record<string, Record<string, string>>;

type EthenaEvent = {
  proofs: string[];
  awardAmount: string;
  releaseTime: number;
};

type EthenaResponse = {
  events?: EthenaEvent[];
  claimed?: boolean;
};

type WalletClaim = {
  address: Hex;
  amount: bigint;
  release: bigint;
  proof: string[];
};

const {
  KV_REST_API_URL: kvUrl,
  KV_REST_API_TOKEN: kvToken,
  MAINNET_RPC_URL: rpcUrl,
} = process.env;

if (!kvUrl || !kvToken) {
  throw new Error("Missing KV_REST_API_URL or KV_REST_API_TOKEN");
}

const KV_URL = kvUrl.replace(/\/$/, "");
const KV_TOKEN = kvToken;
const RPC_URL = rpcUrl || "https://ethereum-rpc.publicnode.com";
const ETHENA_DATA_BASE =
  "https://airdrop-data-ethena-s4.s3.us-west-2.amazonaws.com";

// Edit these toggles directly before running the script.
const CONFIG = {
  DISTRIBUTION_TIMESTAMP: undefined as string | undefined,
  ETHENA_MERKLE_ROOT:
    "0x3d99219fbd49ace3f48d6ca1340e505ec1bdf27d1f8d0e15ec9f286cc9215fcd" as string,
  LIMIT: undefined as number | undefined,
  SIMULATE: false,
};
const POINT_ID_ETHENA_S4 =
  "0x1552756d70656c206b50743a20457468656e61205334086b70534154532d3400";
const CLAIM_SELECTOR = "0x8132b321";
const abiCoder = AbiCoder.defaultAbiCoder();

const publicClient = createPublicClient({
  chain: mainnet,
  transport: http(RPC_URL),
});

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
  const meta = await kvGet<DistributionMeta>(`distributions:${timestamp}`);
  if (!meta) throw new Error(`Distribution ${timestamp} not found`);
  if (!meta.root) throw new Error(`Distribution ${timestamp} missing root`);
  return meta;
}

async function fetchWallets(timestamp: string): Promise<WalletMap> {
  const wallets = await kvGet<WalletMap>(
    `distributions:${timestamp}:wallets`
  );
  if (!wallets) {
    throw new Error(`Distribution ${timestamp} has no wallet snapshot`);
  }
  return wallets;
}

async function fetchEthenaEvent(
  address: Hex,
  root: string
): Promise<EthenaEvent | null> {
  const folder = getAddress(address);
  const url = `${ETHENA_DATA_BASE}/${folder}/${root}-${folder}.json`;
  const res = await fetch(url);
  if (!res.ok) {
    console.warn(`skipping ${folder} (S3 ${res.status})`);
    return null;
  }
  const json = (await res.json()) as EthenaResponse;
  const event = json.events && json.events[0];
  if (!event) return null;
  if (json.claimed) {
    console.log(`already claimed, skipping ${folder}`);
    return null;
  }
  return event;
}

function encodeClaimData(record: WalletClaim): Hex {
  const { address, amount, release, proof } = record;
  const encodedArgs = abiCoder.encode(
    [
      "address[]",
      "uint256[]",
      "uint256[]",
      "uint256[]",
      "uint256[]",
      "bytes32[][]",
    ],
    [[address], [amount], [amount], [release], [0], [proof]]
  );
  return (CLAIM_SELECTOR + encodedArgs.slice(2)) as Hex;
}

async function simulateClaim(address: Hex, data: Hex): Promise<boolean> {
  try {
    await publicClient.call({
      account: address,
      to: "0xC3b7D4ada2Af58E6dc7b4fb303A0de47Ade894C9",
      data,
    });
    return true;
  } catch (error) {
    console.warn(
      `simulation failed for ${address}: ${(error as Error).message}`
    );
    return false;
  }
}

function formatAmount(amount: bigint): string {
  return formatUnits(amount, 18);
}

function writeBatch(
  timestamp: string,
  transactions: { to: string; value: string; data: string }[]
): string {
  const batch = TxBuilder.batch(RUMPEL_ADMIN_SAFE, transactions);
  const dir = path.join(process.cwd(), "js-scripts", "ethenaS4Claim", "safe-batches");
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(
    dir,
    `EthenaS4Claims_${timestamp.replace(/[:.]/g, "-")}.json`
  );
  fs.writeFileSync(file, JSON.stringify(batch, null, 2));
  return file;
}

async function main() {
  const desiredTimestamp = CONFIG.DISTRIBUTION_TIMESTAMP;
  const limit = CONFIG.LIMIT;
  const simulate = CONFIG.SIMULATE;
  const ethenaRoot = CONFIG.ETHENA_MERKLE_ROOT;
  if (!ethenaRoot) {
    throw new Error("CONFIG.ETHENA_MERKLE_ROOT must be set");
  }

  const executed = await kvGet<string[]>("distributions:executed");
  if (!executed || executed.length === 0) {
    throw new Error("No executed distributions in KV");
  }

  const timestamp =
    desiredTimestamp && executed.includes(desiredTimestamp)
      ? desiredTimestamp
      : executed[executed.length - 1];

  if (desiredTimestamp && desiredTimestamp !== timestamp) {
    console.warn(
      `Configured timestamp ${desiredTimestamp} not executed. Using ${timestamp}.`
    );
  }

  const meta = await fetchDistribution(timestamp);
  const wallets = await fetchWallets(timestamp);
  const addresses = Object.entries(wallets)
    .filter(([, points]) => {
      const value = points[POINT_ID_ETHENA_S4];
      return value !== undefined && value !== "0";
    })
    .map(([address]) => getAddress(address) as Hex);

  const slice = limit && limit > 0 ? addresses.slice(0, limit) : addresses;

  if (slice.length === 0) {
    console.log("No wallets with Ethena S4 balances found");
    return;
  }

  console.log(
    `Distribution: ${timestamp} (ui root ${meta.root}, ethena root ${ethenaRoot})`
  );
  console.log(`Wallets to process: ${slice.length}`);

  const claims: WalletClaim[] = [];
  let total = 0n;

  for (const address of slice) {
    const event = await fetchEthenaEvent(address, ethenaRoot);
    if (!event) continue;
    const amount = BigInt(event.awardAmount);
    if (amount === 0n) continue;
    const record: WalletClaim = {
      address,
      amount,
      release: BigInt(event.releaseTime),
      proof: event.proofs,
    };
    claims.push(record);
    total += amount;
  }

  if (claims.length === 0) {
    console.log("No claimable wallets after filtering");
    return;
  }

  claims.sort((a, b) => (b.amount > a.amount ? 1 : -1));

  console.log(`Collected ${claims.length} wallets worth ${formatAmount(total)} sENA`);
  console.log("Top wallets:");
  for (const row of claims.slice(0, 10)) {
    console.log(`  ${row.address} -> ${formatAmount(row.amount)} sENA`);
  }

  let simPassed = 0;
  if (simulate) {
    for (const record of claims) {
      const callData = encodeClaimData(record);
      if (await simulateClaim(record.address, callData)) {
        simPassed += 1;
      }
    }
    console.log(`Simulation summary: ${simPassed}/${claims.length} passed`);
  }

  const txs = claims.map((record) => {
    const claimData = encodeClaimData(record);
    const execData = RUMPEL_MODULE_INTERFACE.encodeFunctionData("exec", [
      [
        {
          safe: record.address,
          to: "0xC3b7D4ada2Af58E6dc7b4fb303A0de47Ade894C9",
          data: claimData,
          operation: 0,
        },
      ],
    ]);
    return { to: RUMPEL_MODULE, value: "0", data: execData };
  });

  const file = writeBatch(timestamp, txs);
  console.log(`Safe batch written to ${file}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
