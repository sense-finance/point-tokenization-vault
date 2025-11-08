import "dotenv/config";
import fs from "fs";
import path from "path";
import {
  Address,
  createPublicClient,
  decodeEventLog,
  encodePacked,
  getContract,
  http,
  keccak256,
  parseAbiItem,
} from "viem";
import { mainnet } from "viem/chains";
import { MerkleTree } from "merkletreejs";
import { pointTokenVaultABI } from "./abis/point-token-vault.ts";

// Minimal, inline-config generator for Ethena S4 Redemption Rights
// Edit these constants directly before running.
const CONFIG = {
  RPC_URL: process.env.MAINNET_RPC_URL || "https://ethereum-rpc.publicnode.com",
  POINT_TOKEN_VAULT: "0xe47F9Dbbfe98d6930562017ee212C1A1Ae45ba61" as Address, // Rumpel vault
  PTOKEN_ADDRESS: "0x8659c0994C8EC73A66E7587c4c6b3aB38d1223bE" as Address,
  POINTS_ID: "0x1552756d70656c206b50743a20457468656e61205334086b70534154532d3400" as `0x${string}`,
  REWARDS_PER_PTOKEN_FULL: 15732130985341739n, // floor( full_total_sENA / pTokenSupply * 1e18 )
  FRACTION_NUM: 25n, // 2.5%
  FRACTION_DEN: 35n, // of 3.5%
  SNAPSHOT_BLOCK: undefined as bigint | undefined, // optional: pin a block; else latest
  OUT_FILE: "js-scripts/generateRedemptionRights/out/ethena-s4-rights.json",
};

const WAD = 10n ** 18n;

function entitlementFull(ptBal: bigint, rewardsPerPTokenFull: bigint) {
  return (ptBal * rewardsPerPTokenFull) / WAD; // floor
}

function rightsNow(fullEntitlement: bigint) {
  return (fullEntitlement * CONFIG.FRACTION_NUM) / CONFIG.FRACTION_DEN; // floor
}

async function main() {
  if (
    CONFIG.PTOKEN_ADDRESS ===
      ("0x0000000000000000000000000000000000000000" as Address) ||
    CONFIG.POINTS_ID ===
      ("0x0000000000000000000000000000000000000000000000000000000000000000" as `0x${string}`) ||
    CONFIG.REWARDS_PER_PTOKEN_FULL === 0n
  ) {
    throw new Error("Fill PTOKEN_ADDRESS, POINTS_ID, and REWARDS_PER_PTOKEN_FULL in CONFIG");
  }

  const client = createPublicClient({ chain: mainnet, transport: http(CONFIG.RPC_URL) });
  const block = CONFIG.SNAPSHOT_BLOCK ?? (await client.getBlockNumber());
  console.log(`Snapshotting pToken holders at block ${block}`);

  const transferEvent = parseAbiItem(
    "event Transfer(address indexed from, address indexed to, uint256 value)"
  );
  const logs = await client.getLogs({
    address: CONFIG.PTOKEN_ADDRESS,
    fromBlock: 0n,
    toBlock: block,
  });

  const balances = new Map<Address, bigint>();
  const zero = "0x0000000000000000000000000000000000000000" as Address;
  for (const log of logs) {
    try {
      const decoded = decodeEventLog({
        abi: [transferEvent],
        data: log.data,
        topics: log.topics,
      });
      const { from, to, value } = decoded.args as any;
      if (!from || !to) continue;
      if (from !== zero) balances.set(from, (balances.get(from) || 0n) - value);
      if (to !== zero) balances.set(to, (balances.get(to) || 0n) + value);
    } catch {}
  }

  const holders = Array.from(balances.entries()).filter(([, v]) => v > 0n);
  holders.sort((a, b) => (b[1] > a[1] ? 1 : -1));
  console.log(`Holders with balance > 0: ${holders.length}`);

  const rights = new Map<Address, bigint>();
  let totalRights = 0n;
  let totalEntFull = 0n;
  for (const [addr, bal] of holders) {
    const full = entitlementFull(bal, CONFIG.REWARDS_PER_PTOKEN_FULL);
    const now = rightsNow(full);
    if (now > 0n) {
      rights.set(addr, now);
      totalRights += now;
      totalEntFull += full;
    }
  }
  console.log(`Total full entitlement: ${totalEntFull.toString()}`);
  console.log(`Total rights now (2.5/3.5): ${totalRights.toString()}`);

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

