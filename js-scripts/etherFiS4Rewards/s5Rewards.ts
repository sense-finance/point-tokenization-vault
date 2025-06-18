import { formatEther } from "ethers";
import * as fs from "fs";
import * as path from "path";

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

function generateKingRedemptionTx(): void {
  const rewardData = parseKingRewards();
}

function parseKingRewards(): any[] {
  const filePath = path.join(__dirname, "KingRewards_6_17_25.json");
  const data = JSON.parse(fs.readFileSync(filePath, "utf8")) as Record<
    string,
    KingRewardEntry
  >;

  const kingPrice = 800;
  const results: any[] = [];
  Object.entries(data).forEach(([user, entry]) => {
    if (!entry.HistoricalRewards || entry.HistoricalRewards.length < 3) {
      results.push({
        user,
        rewardAndYield: Number(formatEther(entry.Amount)),
        rewardValue: Number(formatEther(entry.Amount)) * kingPrice,
        history: false,
      });
      return;
    }
    const amountRaw_6_1 = entry.HistoricalRewards[0].Amount;
    const amount_6_1 = Number(formatEther(amountRaw_6_1 || "0"));

    const amountRaw_5_25 = entry.HistoricalRewards[1].Amount;
    const amount_5_25 = Number(formatEther(amountRaw_5_25 || "0"));

    const amountRaw_5_18 = entry.HistoricalRewards[2].Amount;
    const amount_5_18 = Number(formatEther(amountRaw_5_18 || "0"));

    const amountRaw_5_11 = entry.HistoricalRewards[3].Amount;
    const amount_5_11 = Number(formatEther(amountRaw_5_11 || "0"));

    const rewardAndYield = amount_6_1 - amount_5_25;
    const yieldEstimate1 = amount_5_25 - amount_5_18;
    const yieldEstimate2 = amount_5_18 - amount_5_11;
    const reward = rewardAndYield - yieldEstimate1;

    results.push({
      user,
      rewardAndYield: rewardAndYield.toFixed(8),
      reward: reward.toFixed(8),
      estimatedYield: yieldEstimate1.toFixed(8),
      // yieldEstimate2: yieldEstimate2.toFixed(8),
      rewardValue: (reward * kingPrice).toFixed(2),
      estimatedYieldValue: (yieldEstimate1 * kingPrice).toFixed(2),
      // yieldValue2: (yieldEstimate2 * kingPrice).toFixed(2),
      estimatedYieldPercentage: ((yieldEstimate1 / reward) * 100).toFixed(2),
      // yieldPercentage2: ((yieldEstimate2 / reward) * 100).toFixed(2),
      history: true,
    });
  });
  logResults(results, kingPrice);
}

function logResults(results: any[], kingPrice: number): void {
  const resultsSmallRewardFilter = results.filter((r) => r.rewardValue < 1);
  const resultsRewardFilter = results.filter((r) => r.rewardValue >= 1);
  const resultsYieldFilter = results.filter((r) => r.estimatedYieldValue > 5);
  console.table(resultsRewardFilter);
  console.table(resultsYieldFilter);
  const sum = resultsSmallRewardFilter.reduce(
    (acc, curr) => acc + Number(curr.rewardAndYield),
    0
  );
  console.log(
    `${resultsSmallRewardFilter.length} wallets with: ${sum * kingPrice}`
  );
}
logKingRewardsKeys();
