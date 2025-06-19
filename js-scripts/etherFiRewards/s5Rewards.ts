import { TxBuilder } from "@morpho-labs/gnosis-tx-builder";
import { Contract, Provider, Interface } from "ethers";
import { JsonRpcProvider } from "ethers";
import { formatEther } from "ethers";
import fs from "fs/promises";
import * as path from "path";
import {
  RUMPEL_MODULE,
  RUMPEL_MODULE_INTERFACE,
  RUMPEL_ADMIN_SAFE,
} from "../resolvS1Registration/resolveS1Constants";

interface HistoricalReward {
  Amount: string;
  AwardDate: string;
  Root: string;
}

interface KingRewardEntry {
  Amount: string;
  Root: string;
  Proofs: string[];
  HistoricalRewards: HistoricalReward[];
}

const safeABI = [
  {
    inputs: [],
    name: "getOwners",
    outputs: [{ internalType: "address[]", name: "", type: "address[]" }],
    stateMutability: "view",
    type: "function",
  },
];

const erc20TransferABI = [
  {
    inputs: [
      { internalType: "address", name: "to", type: "address" },
      { internalType: "uint256", name: "amount", type: "uint256" },
    ],
    name: "transfer",
    outputs: [{ internalType: "bool", name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
];
const erc20Interface = new Interface(erc20TransferABI);

const KingClaimAbi = [
  {
    inputs: [
      { internalType: "address", name: "account", type: "address" },
      { internalType: "uint256", name: "cumulativeAmount", type: "uint256" },
      { internalType: "bytes32", name: "expectedMerkleRoot", type: "bytes32" },
      { internalType: "bytes32[]", name: "merkleProof", type: "bytes32[]" },
    ],
    name: "claim",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ internalType: "address", name: "", type: "address" }],
    name: "cumulativeClaimed",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
];

const KING_CLAIM_ADDRESS = "0x6Db24Ee656843E3fE03eb8762a54D86186bA6B64";
const KING_ADDRESS = "0x8F08B70456eb22f6109F57b8fafE862ED28E6040";
const RUMPEL_POINT_TOKENIZATION_VAULT =
  "0xe47F9Dbbfe98d6930562017ee212C1A1Ae45ba61";

let provider: Provider | null = null;

function getProvider(): Provider {
  if (provider) {
    return provider;
  } else {
    const url = process.env.MAINNET_RPC_URL;
    return new JsonRpcProvider(url);
  }
}

async function getWalletOwner(wallet: string): Promise<string> {
  const safe = new Contract(wallet, safeABI, getProvider());
  const owners = await safe.getOwners();
  return owners[0];
}

function format18Dec(input: bigint): number {
  return Number(Number(formatEther(input)).toFixed(2));
}

function encodeKingTransferFromModule(
  wallet: string,
  to: string,
  amount: bigint
): {
  to: string;
  value: string;
  data: string;
} {
  const transferData = erc20Interface.encodeFunctionData("transfer", [
    to,
    amount,
  ]);

  const executeTransferData = RUMPEL_MODULE_INTERFACE.encodeFunctionData(
    "exec",
    [
      [
        {
          safe: wallet,
          to: KING_ADDRESS,
          data: transferData,
          operation: 0, // call
        },
      ],
    ]
  );

  return {
    to: RUMPEL_MODULE,
    value: "0",
    data: executeTransferData,
  };
}

async function parseKingRewards(): Promise<any[]> {
  const filePath = path.join(__dirname, "KingRewards_6_19_25.json");
  const data = JSON.parse(await fs.readFile(filePath, "utf8")) as Record<
    string,
    KingRewardEntry
  >;
  const filteredData = Object.entries(data).filter(([wallet, entry]) => {
    return Object.keys(entry).length > 0;
  });

  const provider = getProvider();
  const kingClaimContract = new Contract(
    KING_CLAIM_ADDRESS,
    KingClaimAbi,
    provider
  );

  const kingPrice = BigInt(800);
  const results: any[] = [];
  const transactions: any[] = [];
  let totalClaimed = 0n;
  let totalVaultRewards = 0n;
  let totalYieldTransferred = 0n;
  for (const [wallet, entry] of filteredData) {
    const amountRaw_6_8 = BigInt(entry.HistoricalRewards[0].Amount);
    const amountRaw_6_1 = BigInt(entry.HistoricalRewards[1].Amount);
    const amountRaw_5_25 = BigInt(entry.HistoricalRewards[2]?.Amount || 0);
    const amountRaw_5_18 = BigInt(entry.HistoricalRewards[3]?.Amount || 0);

    const rewardAndYield = amountRaw_6_1 - amountRaw_5_25;
    const yieldEstimate = amountRaw_5_25 - amountRaw_5_18;
    const yieldEstimate2 = amountRaw_6_8 - amountRaw_6_1;

    let yieldAdjustedReward = rewardAndYield;
    let adjusted = false;
    const yieldEstimateNumber = Number(formatEther(yieldEstimate * kingPrice));
    if (yieldEstimateNumber > 1) {
      yieldAdjustedReward = rewardAndYield - yieldEstimate;
      adjusted = true;
    }

    const [owner, previouslyClaimed] = await Promise.all([
      getWalletOwner(wallet),
      kingClaimContract.cumulativeClaimed(wallet),
    ]);

    const unclaimed = amountRaw_6_8 - previouslyClaimed;
    const netToClaim = unclaimed > 0n ? unclaimed : 0n;
    totalClaimed += netToClaim;

    results.push({
      wallet,
      owner,
      previouslyClaimed,
      amountRaw_6_8,
      amountRaw_6_1,
      amountRaw_5_25,
      amountRaw_5_18,
      netToClaim,
      yieldAdjustedReward,
      yieldEstimate,
      yieldEstimate2,
      adjusted,
    });

    if (netToClaim == 0n) {
      continue;
    }

    const claimData = kingClaimContract.interface.encodeFunctionData("claim", [
      wallet,
      amountRaw_6_8,
      entry.Root,
      entry.Proofs,
    ]);

    transactions.push({
      to: KING_CLAIM_ADDRESS,
      value: "0",
      data: claimData,
    });

    if (netToClaim <= yieldAdjustedReward) {
      const rewardTransfer = encodeKingTransferFromModule(
        wallet,
        RUMPEL_POINT_TOKENIZATION_VAULT,
        netToClaim
      );
      transactions.push(rewardTransfer);
      totalVaultRewards += netToClaim;
    } else {
      const rewardTransfer = encodeKingTransferFromModule(
        wallet,
        RUMPEL_POINT_TOKENIZATION_VAULT,
        yieldAdjustedReward
      );

      const yieldTransfer = encodeKingTransferFromModule(
        wallet,
        owner,
        netToClaim - yieldAdjustedReward
      );
      transactions.push(rewardTransfer);
      transactions.push(yieldTransfer);
      totalVaultRewards += yieldAdjustedReward;
      totalYieldTransferred += netToClaim - yieldAdjustedReward;
    }
  }

  const batchJson = TxBuilder.batch(RUMPEL_ADMIN_SAFE, transactions);

  const safeBatchesFolder = path.join(
    process.cwd(),
    "/js-scripts/etherFiRewards/safe-batches"
  );
  const outputPath = path.join(safeBatchesFolder, `etherFiS5ClaimBatch.json`);
  await fs.writeFile(outputPath, JSON.stringify(batchJson, null, 2));

  const printTable = results.map((r) => {
    return {
      wallet: r.wallet,
      owner: r.owner,
      previouslyClaimed: format18Dec(r.previouslyClaimed * kingPrice),
      amount_6_8: format18Dec(r.amountRaw_6_8 * kingPrice),
      amount_6_1: format18Dec(r.amountRaw_6_1 * kingPrice),
      amount_5_25: format18Dec(r.amountRaw_5_25 * kingPrice),
      amount_5_18: format18Dec(r.amountRaw_5_18 * kingPrice),
      yieldAdjustedReward: format18Dec(r.yieldAdjustedReward * kingPrice),
      yieldEstimate: format18Dec(r.yieldEstimate * kingPrice),
      // yieldEstimate2: format18Dec(r.yieldEstimate2 * kingPrice),
      adjusted: r.adjusted,
    };
  });
  console.table(printTable);
  const expectedVaultRewards = results.reduce(
    (acc, curr) => acc + Number(curr.yieldAdjustedReward),
    0
  );

  console.log(`expected vault rewards:  ${expectedVaultRewards}`);
  console.log(`actual vault rewards:    ${totalVaultRewards}`);

  console.log(`total yield transferred: ${totalYieldTransferred}`);
  console.log(
    `expected total claimed:  ${totalYieldTransferred + totalVaultRewards}`
  );
  console.log(`total claimed:           ${totalClaimed}`);
  console.log();
  console.log(
    `formatted vault bal increase: ${format18Dec(totalVaultRewards)}`
  );

  return results;
}

await parseKingRewards();
