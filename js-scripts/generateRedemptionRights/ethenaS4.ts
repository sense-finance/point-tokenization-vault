import "dotenv/config";
import fs from "fs";
import path from "path";
import {
  createPublicClient,
  decodeEventLog,
  encodePacked,
  getContract,
  http,
  keccak256,
  parseAbiItem,
  zeroAddress
} from "viem";
import type { Address, } from "viem";
import { mainnet } from "viem/chains";
import { MerkleTree } from "merkletreejs";
import { pointTokenVaultABI } from "./abis/point-token-vault.ts";

// REWARDS_PER_PTOKEN_FULL Calculation:
//
// This value represents the full (3.5/3.5) sENA redemption rate per pToken.
// It is calculated as: (total_sENA_claimable_instant × 3.5/2.5) / total_kPoints
//
// Derivation (as of Nov 2024):
//   - Total kPoints (from KV distribution): 1,401,572,131.69
//   - Total sENA claimable instant (2.5/3.5, from Ethena S3): 10,703,804.37
//   - Total sENA full (3.5/3.5): 10,703,804.37 × 3.5/2.5 = 14,985,326.118
//   - REWARDS_PER_PTOKEN_FULL = 14,985,326.118 / 1,401,572,131.69 = 0.010691798002514229
//
// Run `npx tsx js-scripts/generateRedemptionRights/validateEthenaS4.ts` to verify.

// Overrides for special cases (e.g., UNI pools)
// Format: { "contract_address": { "recipient_address": "amount_in_wei" } }
const OVERRIDES: Record<string, Record<string, string>> = {};

const ALCHEMY_KEY = process.env.ALCHEMY_KEY;
const RPC_URL = ALCHEMY_KEY
  ? `https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}` : process.env.MAINNET_RPC_URL;

const CONFIG = {
  RPC_URL,
  KV_URL: process.env.KV_REST_API_URL?.replace(/\/$/, ""),
  KV_TOKEN: process.env.KV_REST_API_TOKEN,
  POINT_TOKEN_VAULT: "0xe47F9Dbbfe98d6930562017ee212C1A1Ae45ba61" as Address,
  PTOKEN_ADDRESS: "0x8659c0994C8EC73A66E7587c4c6b3aB38d1223bE" as Address,
  POINTS_ID: "0x1552756d70656c206b50743a20457468656e61205334086b70534154532d3400" as `0x${string}`,
  REWARDS_PER_PTOKEN_FULL: 10691798002514229n,
  FRACTION_NUM: 25n, // 2.5 of 3.5 released now
  FRACTION_DEN: 35n, // remaining 1.0 released later
  SNAPSHOT_BLOCK: undefined as bigint | undefined,
  OUT_FILE: "js-scripts/generateRedemptionRights/out/ethena-s4-rights.json",
};

const WAD = 10n ** 18n;

if (!CONFIG.KV_URL || !CONFIG.KV_TOKEN) {
  throw new Error("Missing KV_REST_API_URL or KV_REST_API_TOKEN");
}

type WalletMap = Record<string, Record<string, string>>;

async function kvGet<T>(key: string): Promise<T | null> {
  const res = await fetch(`${CONFIG.KV_URL}/get/${encodeURIComponent(key)}`, {
    headers: { Authorization: `Bearer ${CONFIG.KV_TOKEN}` },
  });
  const json = (await res.json()) as { result?: T };
  const v = json.result;
  return v == null ? null : typeof v === "string" ? JSON.parse(v) : v;
}

function entitlementFull(ptBal: bigint) {
  return (ptBal * CONFIG.REWARDS_PER_PTOKEN_FULL) / WAD;
}

function rightsNow(fullEntitlement: bigint) {
  return (fullEntitlement * CONFIG.FRACTION_NUM) / CONFIG.FRACTION_DEN;
}

async function main() {
  if (
    CONFIG.PTOKEN_ADDRESS === zeroAddress ||
    CONFIG.POINTS_ID === "0x0000000000000000000000000000000000000000000000000000000000000000" ||
    CONFIG.REWARDS_PER_PTOKEN_FULL === 0n
  ) {
    throw new Error("Fill PTOKEN_ADDRESS, POINTS_ID, and REWARDS_PER_PTOKEN_FULL in CONFIG");
  }

  const client = createPublicClient({ chain: mainnet, transport: http(CONFIG.RPC_URL) });
  const block = CONFIG.SNAPSHOT_BLOCK ?? (await client.getBlockNumber());
  console.log(`Snapshotting at block ${block}`);

  // Get kPoints from KV distribution (represents total accumulating points)
  const exec = await kvGet<string[]>("distributions:executed");
  if (!exec || exec.length === 0) throw new Error("No executed distributions in KV");
  const timestamp = exec[exec.length - 1];
  console.log(`Using distribution: ${timestamp}`);

  const wallets = await kvGet<WalletMap>(`distributions:${timestamp}:wallets`);
  if (!wallets) throw new Error(`No wallets found for distribution ${timestamp}`);

  const kPoints = new Map<Address, bigint>();
  for (const [addr, points] of Object.entries(wallets)) {
    const kp = points[CONFIG.POINTS_ID];
    if (kp && kp !== "0") {
      // Normalize to lowercase for consistent lookups
      const normalized = addr.toLowerCase() as Address;
      kPoints.set(normalized, BigInt(kp));
    }
  }
  console.log(`Addresses with kPoints: ${kPoints.size}`);

  // Get minted pToken balances from Transfer events
  const transferEvent = parseAbiItem(
    "event Transfer(address indexed from, address indexed to, uint256 value)"
  );
  const logs = await client.getLogs({
    address: CONFIG.PTOKEN_ADDRESS,
    event: transferEvent,
    fromBlock: 0n,
    toBlock: block,
  });

  const mintedBalances = new Map<Address, bigint>();
  for (const log of logs) {
    try {
      const decoded = decodeEventLog({
        abi: [transferEvent],
        data: log.data,
        topics: log.topics,
      });
      const { from, to, value } = decoded.args as any;
      if (!from || !to) continue;
      // Normalize addresses to lowercase
      const fromLower = from.toLowerCase() as Address;
      const toLower = to.toLowerCase() as Address;
      if (fromLower !== zeroAddress.toLowerCase()) {
        mintedBalances.set(fromLower, (mintedBalances.get(fromLower) || 0n) - value);
      }
      if (toLower !== zeroAddress.toLowerCase()) {
        mintedBalances.set(toLower, (mintedBalances.get(toLower) || 0n) + value);
      }
    } catch {}
  }
  console.log(`Holders with minted pTokens: ${Array.from(mintedBalances.values()).filter(b => b > 0n).length}`);

  // Apply overrides
  for (const [contractAddr, redistributions] of Object.entries(OVERRIDES)) {
    const contractAddrLower = contractAddr.toLowerCase() as Address;
    const contractBalance = mintedBalances.get(contractAddrLower) || 0n;
    if (contractBalance > 0n) {
      mintedBalances.set(contractAddrLower, 0n);
      for (const [recipient, amount] of Object.entries(redistributions)) {
        const recipientLower = recipient.toLowerCase() as Address;
        const overrideAmount = BigInt(amount);
        mintedBalances.set(
          recipientLower,
          (mintedBalances.get(recipientLower) || 0n) + overrideAmount
        );
      }
    }
  }

  // Query vault for claimed pTokens and add unminted balances
  const vault = getContract({
    address: CONFIG.POINT_TOKEN_VAULT,
    abi: pointTokenVaultABI,
    client,
  });

  const totalBalances = new Map<Address, bigint>();
  let skipped = 0;
  for (const [addr, kp] of kPoints.entries()) {
    try {
      const claimed = (await vault.read.claimedPTokens([addr, CONFIG.POINTS_ID])) as bigint;
      const unminted = kp - claimed;
      const minted = mintedBalances.get(addr) || 0n;
      const total = minted + unminted;

      if (total > 0n) {
        totalBalances.set(addr, total);
      } else {
        skipped++;
      }
    } catch (err) {
      console.warn(`Failed to query claimed for ${addr}: ${(err as Error).message}`);
      // On error, assume not claimed and use kPoints as balance
      const minted = mintedBalances.get(addr) || 0n;
      const total = minted + kp;
      if (total > 0n) {
        totalBalances.set(addr, total);
      }
      skipped++;
    }
  }

  // Add minted-only holders (addresses with minted pTokens but no kPoints entry)
  let mintedOnly = 0;
  for (const [addr, minted] of mintedBalances.entries()) {
    if (minted > 0n && !totalBalances.has(addr)) {
      totalBalances.set(addr, minted);
      mintedOnly++;
    }
  }

  console.log(`Total holders (minted + unminted): ${totalBalances.size}`);
  if (skipped > 0) console.log(`Skipped ${skipped} addresses (zero balance or error)`);
  if (mintedOnly > 0) console.log(`Added ${mintedOnly} minted-only holders`);

  // Calculate redemption rights
  const rights = new Map<Address, bigint>();
  let totalRights = 0n;
  let totalEntFull = 0n;

  for (const [addr, bal] of totalBalances.entries()) {
    const full = entitlementFull(bal);
    const now = rightsNow(full);
    if (now > 0n) {
      rights.set(addr, now);
      totalRights += now;
      totalEntFull += full;
    }
  }

  console.log(`Total full entitlement: ${totalEntFull.toString()}`);
  console.log(`Total rights now (2.5/3.5): ${totalRights.toString()}`);

  // Generate merkle tree
  const prefix = keccak256(encodePacked(["string"], ["REDEMPTION_RIGHTS"]));
  const leaves = Array.from(rights.entries()).map(([addr, amt]) =>
    keccak256(
      encodePacked(
        ["bytes32", "address", "bytes32", "uint256"],
        [prefix, addr, CONFIG.POINTS_ID, amt]
      )
    )
  );
  const tree = new MerkleTree(leaves.sort(), keccak256, { sortPairs: true });
  const root = tree.getHexRoot() as `0x${string}`;
  console.log(`Merkle root: ${root}`);

  // Build output
  const out: any = { root, redemptionRights: {} };
  for (const [addr, amt] of rights.entries()) {
    out.redemptionRights[addr] = {
      [CONFIG.POINTS_ID]: {
        amount: amt.toString(),
        proof: tree.getHexProof(
          keccak256(
            encodePacked(
              ["bytes32", "address", "bytes32", "uint256"],
              [prefix, addr, CONFIG.POINTS_ID, amt]
            )
          )
        ),
      },
    };
  }

  fs.mkdirSync(path.dirname(CONFIG.OUT_FILE), { recursive: true });
  fs.writeFileSync(CONFIG.OUT_FILE, JSON.stringify(out, null, 2));
  console.log(`Wrote ${CONFIG.OUT_FILE}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
