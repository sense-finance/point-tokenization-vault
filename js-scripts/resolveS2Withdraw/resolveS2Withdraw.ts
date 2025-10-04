import { TxBuilder } from "@morpho-labs/gnosis-tx-builder";
import fs from "fs/promises";
import path from "path";
import {
  RUMPEL_ADMIN_SAFE,
  RUMPEL_MODULE,
  RUMPEL_MODULE_INTERFACE,
} from "../resolvS1Registration/resolveS1Constants";
import { Interface, JsonRpcProvider, formatUnits } from "ethers";
import { Contract } from "ethers";

const STAKED_RESOLV_ADDRESS = "0xFE4BCE4b3949c35fB17691D8b03c3caDBE2E5E23";
const RUMPEL_VAULT = "0xe47F9Dbbfe98d6930562017ee212C1A1Ae45ba61";
const DATA_DIR = path.join(process.cwd(), "js-scripts/resolvS2Claim");
const CLAIMS_FILE = path.join(DATA_DIR, "resolvS2Claims.json");
const CSV_FILE = path.join(DATA_DIR, "resolvS2Earners.csv");
const SAFE_BATCH_FILE = path.join(
  process.cwd(),
  "js-scripts/resolveS2Withdraw/safe-batches/resolvS2Withdraw.json"
);

const canonical = (value: string) => value.toLowerCase();

type ClaimPayload = {
  id: number;
  minorAmount: string;
  proof: string[];
};

type ClaimMap = Record<string, ClaimPayload>;

type PointMap = Record<string, number>;

const readClaims = async (): Promise<ClaimMap> => {
  const raw = await fs.readFile(CLAIMS_FILE, "utf8");
  return JSON.parse(raw);
};

const readPoints = async (): Promise<PointMap> => {
  const raw = await fs.readFile(CSV_FILE, "utf8");
  const lines = raw
    .trim()
    .split("\n")
    .filter((line) => line.length > 0);
  lines.shift();
  const entries = lines.map((line) => line.split(","));
  return entries.reduce<PointMap>((acc, [address, points]) => {
    if (!address || !points) {
      return acc;
    }
    acc[canonical(address)] = Number(points);
    return acc;
  }, {});
};

const getProvider = () => {
  const rpcUrl = process.env.MAINNET_RPC_URL;
  if (!rpcUrl) {
    throw new Error("Missing MAINNET_RPC_URL");
  }
  return new JsonRpcProvider(rpcUrl);
};

const withdrawInterface = new Interface([
  "function withdraw(bool _claimRewards, address _receiver) external",
  "function usersData(address user) external view returns (tuple(address rewardReceiver, address checkpointDelegatee, tuple(uint256 totalAccumulated, uint256 lastUpdate) stakeAgeInfo, uint256 effectiveBalance, tuple(uint256 amount, uint256 cooldownEnd) pendingWithdrawal))",
]);

const buildWithdrawTx = (safe: string, data: string) =>
  RUMPEL_MODULE_INTERFACE.encodeFunctionData("exec", [
    [
      {
        safe,
        to: STAKED_RESOLV_ADDRESS,
        data,
        operation: 0,
      },
    ],
  ]);

const main = async () => {
  const [claims, points] = await Promise.all([readClaims(), readPoints()]);
  const provider = getProvider();
  const contract = new Contract(
    STAKED_RESOLV_ADDRESS,
    withdrawInterface,
    provider
  );
  const withdrawCalldata = withdrawInterface.encodeFunctionData("withdraw", [
    false,
    RUMPEL_VAULT,
  ]);

  const latestBlock = await provider.getBlock("latest");
  const now = latestBlock?.timestamp ?? 0;

  let totalRewards = 0n;
  let totalPoints = 0;

  for (const pointsAmount of Object.values(points)) {
    totalPoints += pointsAmount;
  }

  const rows: Array<Record<string, unknown>> = [];
  const txs: Array<{ to: string; value: string; data: string }> = [];
  const missingPoints: string[] = [];
  const processedSafes = new Set<string>();

  for (const [safe, payload] of Object.entries(claims)) {
    const userData = await contract.usersData(safe);
    const pending = userData.pendingWithdrawal;
    const withdrawalAmount = BigInt(pending.amount ?? 0n);
    const cooldownEnd = Number(pending.cooldownEnd ?? 0n);

    const claimAmount = BigInt(payload.minorAmount);
    const amountMatchesClaim = withdrawalAmount === claimAmount;
    if (!amountMatchesClaim) {
      console.warn(
        `Withdrawal amount mismatch for ${safe}: chain ${withdrawalAmount} vs claim ${claimAmount}`
      );
    }

    const key = canonical(safe);
    const hasPoints = Object.prototype.hasOwnProperty.call(points, key);
    if (!hasPoints) {
      missingPoints.push(safe);
    }
    const pointsForSafe = hasPoints ? points[key] : 0;
    processedSafes.add(key);

    totalRewards += withdrawalAmount;

    txs.push({
      to: RUMPEL_MODULE,
      value: "0",
      data: buildWithdrawTx(safe, withdrawCalldata),
    });

    rows.push({
      safe,
      points: pointsForSafe,
      rewards: Number(formatUnits(withdrawalAmount, 18)),
      matches: amountMatchesClaim,
      cooldownRemaining: cooldownEnd - now,
    });
  }

  // Add wallets that have points but no rewards/claims
  for (const [address, pointsAmount] of Object.entries(points)) {
    if (!processedSafes.has(address)) {
      rows.push({
        safe: address,
        points: pointsAmount,
        rewards: 0,
        matches: "N/A",
        cooldownRemaining: "N/A",
      });
    }
  }

  const rewardsTokens = Number(formatUnits(totalRewards, 18));
  const kPoints = totalPoints / 1000;
  const rewardPerKPoint = kPoints === 0 ? 0 : rewardsTokens / kPoints;

  // Calculate reward per kPoint scaled to 1e18: (totalRewards * 1000) / totalPoints
  // Note: totalRewards is already in wei (1e18), so we just need to multiply by 1000 for kPoints
  const rewardPerKPointScaled =
    totalPoints === 0
      ? 0n
      : (totalRewards * BigInt(1000)) / BigInt(totalPoints) - 1n;

  console.log(`Processed ${rows.length} safes`);
  console.log(`Total rewards: ${rewardsTokens}`);
  console.log(`Total points: ${totalPoints}`);
  console.log(`Total kPoints: ${kPoints}`);
  console.log(`Reward per kPoint: ${rewardPerKPoint}`);
  console.log(`Reward per kPoint (1e18 scaled): ${rewardPerKPointScaled}`);
  if (missingPoints.length) {
    console.warn(`Missing points for ${missingPoints.length} safes`);
    console.warn(JSON.stringify(missingPoints, null, 2));
  }

  console.table(rows);

  const batchJson = TxBuilder.batch(RUMPEL_ADMIN_SAFE, txs);
  await fs.mkdir(path.dirname(SAFE_BATCH_FILE), { recursive: true });
  await fs.writeFile(SAFE_BATCH_FILE, JSON.stringify(batchJson, null, 2));
};

void main();
