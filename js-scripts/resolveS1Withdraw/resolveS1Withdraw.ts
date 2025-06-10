import { TxBuilder } from "@morpho-labs/gnosis-tx-builder";
import fs from "fs/promises";
import path from "path";
import { distro } from "../resolvS1Registration/rumpelPoints";
import {
  RUMPEL_ADMIN_SAFE,
  RUMPEL_MODULE,
  RUMPEL_MODULE_INTERFACE,
} from "../resolvS1Registration/resolveS1Constants";
import { formatUnits, Interface } from "ethers";
import { Contract } from "ethers";
import { JsonRpcProvider } from "ethers";
import { getBlock } from "viem/actions";

const STAKED_RESOLV_ADDRESS = "0xFE4BCE4b3949c35fB17691D8b03c3caDBE2E5E23";
const RUMPEL_VAULT = "0xe47F9Dbbfe98d6930562017ee212C1A1Ae45ba61";

const generateWithdrawalBatch = async () => {
  const rpcUrl = process.env.MAINNET_RPC_URL;
  if (!rpcUrl) {
    throw new Error("ERROR: no provider url");
  }
  const provider = new JsonRpcProvider(rpcUrl);

  const s1FinalPointsPath = path.join(
    process.cwd(),
    "/js-scripts/resolvS1Claim/"
  );
  const s1FinalPointsRaw = await fs.readFile(
    path.join(s1FinalPointsPath, "resolvS1TotalPointsFinal.json"),
    "utf8"
  );

  const finalPoints = JSON.parse(s1FinalPointsRaw);

  const s1ClaimPath = path.join(process.cwd(), "/js-scripts/resolvS1Claim/");
  const claimDataRaw = await fs.readFile(
    path.join(s1ClaimPath, "resolvS1Claims.json"),
    "utf8"
  );
  const claimData = JSON.parse(claimDataRaw);

  const stkResolvInterface = new Interface([
    "function initiateWithdrawal(uint256 _amount) external",
    "function withdraw(bool _claimRewards, address _receiver) external",
    "function usersData(address user) external view returns (tuple(address rewardReceiver, address checkpointDelegatee, tuple(uint256 totalAccumulated, uint256 lastUpdate) stakeAgeInfo, uint256 effectiveBalance, tuple(uint256 amount, uint256 cooldownEnd) pendingWithdrawal))",
  ]);

  const stkResolveContract = new Contract(
    STAKED_RESOLV_ADDRESS,
    stkResolvInterface,
    provider
  );

  const block = await provider.getBlock(await provider.getBlockNumber());
  let blockTimestamp = block?.timestamp;
  if (!blockTimestamp) {
    throw new Error("No Current Block Timestamp");
  }

  let totalPoints = 0;
  let totalRewards = 0n;
  const results: any = [];
  const transactions: any[] = [];
  for (const address of Object.keys(claimData)) {
    const usersData = await stkResolveContract.usersData(address);
    const withdrawalAmount = usersData.pendingWithdrawal.amount;
    const cooldownEnd = usersData.pendingWithdrawal.cooldownEnd;

    const amountCheck = claimData[address].minorAmount == withdrawalAmount;
    const cooldownRemaining = Number(cooldownEnd) - blockTimestamp;
    console.log(
      `${address}: ${withdrawalAmount} - amount check: ${amountCheck} - Cooldown Remaining: ${cooldownRemaining}`
    );
    const withdrawMessageData = stkResolvInterface.encodeFunctionData(
      "withdraw(bool,address)",
      [false, RUMPEL_VAULT]
    );
    const executeClaimTransactionData =
      RUMPEL_MODULE_INTERFACE.encodeFunctionData("exec", [
        [
          {
            safe: address,
            to: STAKED_RESOLV_ADDRESS,
            data: withdrawMessageData,
            operation: 0, // call
          },
        ],
      ]);
    transactions.push({
      to: RUMPEL_MODULE,
      value: "0",
      data: executeClaimTransactionData,
    });
    totalRewards += withdrawalAmount;
    totalPoints += finalPoints[address].previous.seasonOnePoints;
  }

  // Calculate appropriate rewardPerPToken
  const adminAddress = "0xaEb00366474D62CC8f653820f6c45F775Cf0977A";
  const adminPoints = finalPoints[adminAddress].previous.seasonOnePoints;

  const adminPercentBurned = 92.4 / 100;
  const pointsToBurn = adminPoints * adminPercentBurned;
  const adminPointsRemaining = adminPoints - pointsToBurn;

  const totalPointsAdjusted = totalPoints - pointsToBurn;
  const socializedRatio = totalPoints / Number(formatUnits(totalRewards, 18));
  const adjustedRatio =
    totalPointsAdjusted / Number(formatUnits(totalRewards, 18));

  const rewardsPerPToken = 1 / adjustedRatio;
  const rewardsPerPTokenBig =
    (BigInt(Math.pow(10, 18)) * BigInt(Math.pow(10, 18))) /
    BigInt(adjustedRatio * Math.pow(10, 18));

  console.log(`rewardsPerPToken (number): ${rewardsPerPToken}`);
  console.log(`rewardsPerPToken (uint256): ${Number(rewardsPerPTokenBig)}`);
  console.log(`Admin Points To Burn: ${pointsToBurn}`);
  console.log(`Admin Redeemable Points: ${adminPointsRemaining}`);

  for (const address of Object.keys(claimData)) {
    const rewards = Number(formatUnits(claimData[address].minorAmount, 18));
    const points = finalPoints[address].previous.seasonOnePoints;
    let adjustedRewards;
    if (address != adminAddress) {
      adjustedRewards = points / adjustedRatio;
    } else {
      adjustedRewards = adminPointsRemaining / adjustedRatio;
    }

    results.push({
      address,
      points,
      rewards: rewards.toFixed(2),
      rewardValue: `$${(rewards * 0.33).toFixed(2)}`,
      adjustedRewards: Number(adjustedRewards.toFixed(2)),
      diff: (adjustedRewards - rewards).toFixed(2),
      diffDollars: `$${((adjustedRewards - rewards) * 0.33).toFixed(2)}`,
      pointsPerRewardOriginal: (points / rewards).toFixed(2),
    });
  }
  results.sort((a, b) => b.rewards - a.rewards);

  const totalAdjustedRewards = results.reduce(
    (sum, r) => sum + r.adjustedRewards,
    0
  );

  results.push({
    address: "Totals",
    points: totalPoints,
    rewards: Number(formatUnits(totalRewards, 18)),
    adjustedRewards: totalAdjustedRewards,
  });
  results.push({
    address: "pointsPerReward",
    adjustedRewards: adjustedRatio,
    pointsPerRewardOriginal: socializedRatio,
  });

  console.table(results);

  // commented out file write
  // const batchJson = TxBuilder.batch(RUMPEL_ADMIN_SAFE, transactions);

  // Create safe-batches in working directory if it doesn't exist
  // const safeBatchesFolder = path.join(
  //   process.cwd(),
  //   "js-scripts/resolveS1Withdraw/safe-batches"
  // );

  // Write the result to a file in the safe-batches folder
  // const outputPath = path.join(safeBatchesFolder, `resolvS1Withdraw.json`);
  // await fs.writeFile(outputPath, JSON.stringify(batchJson, null, 2));
};

generateWithdrawalBatch();
