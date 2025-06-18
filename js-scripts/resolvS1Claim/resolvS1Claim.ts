import { TxBuilder } from "@morpho-labs/gnosis-tx-builder";
import fs from "fs/promises";
import path from "path";
import { distro } from "../resolvS1Registration/rumpelPoints";
import {
  RUMPEL_ADMIN_SAFE,
  RUMPEL_MODULE,
  RUMPEL_MODULE_INTERFACE,
} from "../resolvS1Registration/resolveS1Constants";
import { Interface } from "ethers";

const STAKED_RESOLV_TOKEN_DISTRIBUTOR_ADDRESS =
  "0xCE9d50db432e0702BcAd5a4A9122F1F8a77aD8f9";
const STAKED_RESOLV_ADDRESS = "0xFE4BCE4b3949c35fB17691D8b03c3caDBE2E5E23";

const fetchWithRetries = async (
  url: string,
  retries = 8,
  delay = 3000,
  backoffFactor = 2
): Promise<any> => {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      const response = await fetch(url, { cache: "no-cache" });
      if (response.ok) {
        return await response.json();
      } else {
        const message = await response.json();
        if (message && message.error) {
          if (
            message.error ==
            "Unexpected token 'U', \"User not f\"... is not valid JSON"
          ) {
            return {};
          }
        }
        throw Error;
      }
    } catch (error) {
      if (attempt < retries) {
        console.warn(`Attempt ${attempt} failed. Retrying in ${delay}ms...`);
        console.warn(url);
        console.warn(error);
        await new Promise((resolve) => setTimeout(resolve, delay));
        delay *= backoffFactor; // Apply exponential backoff
      } else {
        console.error(`All ${retries} attempts failed.`);
        throw error; // Throw the error after exhausting retries
      }
    }
  }
};

const writeClaimResponses = async () => {
  const addressesWithResolv = Object.entries(distro)
    .filter(
      ([, balances]) => balances["Resolv S1"] && balances["Resolv S1"] !== "0"
    )
    .map(([address]) => address);

  console.log(
    JSON.stringify(addressesWithResolv, null, 2),
    addressesWithResolv.length
  );

  let allResults: { [key: string]: {} } = {};
  for (let i = 0; i < addressesWithResolv.length; i = i + 10) {
    let end = i + 10;
    if (i + 10 > addressesWithResolv.length) {
      end = addressesWithResolv.length;
    }
    const subWallets = addressesWithResolv.slice(i, end);
    const promises = subWallets.map(async (wallet) => {
      const response = await fetchWithRetries(
        `https://api.resolv.xyz/claim/merkle-proofs?address=${wallet}`
      );
      return { [wallet]: response };
    });
    const results = await Promise.all(promises);
    allResults = { ...allResults, ...Object.assign({}, ...results) };
    console.log(`${i + 10} wallets completed`);
  }

  const s1ClaimPath = path.join(process.cwd(), "/js-scripts/resolvS1Claim/");

  await fs.writeFile(
    path.join(s1ClaimPath, "resolvS1Claims.json"),
    JSON.stringify(allResults, null, 2)
  );
};

const writeS1TotalFinalPoints = async () => {
  const addressesWithResolv = Object.entries(distro)
    .filter(
      ([, balances]) => balances["Resolv S1"] && balances["Resolv S1"] !== "0"
    )
    .map(([address]) => address);

  let allResults = {};
  for (let i = 0; i < addressesWithResolv.length; i = i + 10) {
    let end = i + 10;
    if (i + 10 > addressesWithResolv.length) {
      end = addressesWithResolv.length;
    }
    const subWallets = addressesWithResolv.slice(i, end);
    const promises = subWallets.map(async (wallet) => {
      const response = await fetchWithRetries(
        `https://api.resolv.xyz/points?address=${wallet}`
      );
      return { [wallet]: response };
    });
    const results = await Promise.all(promises);
    allResults = { ...allResults, ...Object.assign({}, ...results) };
    console.log(`${i + 10} wallets completed`);
  }

  const s1TotalPointsPath = path.join(
    process.cwd(),
    "/js-scripts/resolvS1Claim/"
  );
  await fs.writeFile(
    path.join(s1TotalPointsPath, "resolvS1TotalPointsFinal.json"),
    JSON.stringify(allResults, null, 2)
  );
};

const generateSafeBatch = async () => {
  const s1ClaimPath = path.join(process.cwd(), "/js-scripts/resolvS1Claim/");
  const claimDataRaw = await fs.readFile(
    path.join(s1ClaimPath, "resolvS1Claims.json"),
    "utf8"
  );
  const claimData = JSON.parse(claimDataRaw);

  const stkResolvDistributorInterface = new Interface([
    "function claim(uint256 _index,uint256 _amount,bytes32[] calldata _merkleProof) external",
  ]);
  const stkResolvInterface = new Interface([
    "function initiateWithdrawal(uint256 _amount) external",
  ]);

  const transactions: any[] = [];
  for (const address of Object.keys(claimData)) {
    const claimAmount = BigInt(claimData[address].minorAmount);
    const claimMessageData = stkResolvDistributorInterface.encodeFunctionData(
      "claim",
      [claimData[address].id, claimAmount, claimData[address].proof]
    );
    const executeClaimTransactionData =
      RUMPEL_MODULE_INTERFACE.encodeFunctionData("exec", [
        [
          {
            safe: address,
            to: STAKED_RESOLV_TOKEN_DISTRIBUTOR_ADDRESS,
            data: claimMessageData,
            operation: 0, // call
          },
        ],
      ]);
    transactions.push({
      to: RUMPEL_MODULE,
      value: "0",
      data: executeClaimTransactionData,
    });

    const initiateWithdrawalData = stkResolvInterface.encodeFunctionData(
      "initiateWithdrawal",
      [claimAmount]
    );

    const executeInitWithdrawalTransactionData =
      RUMPEL_MODULE_INTERFACE.encodeFunctionData("exec", [
        [
          {
            safe: address,
            to: STAKED_RESOLV_ADDRESS,
            data: initiateWithdrawalData,
            operation: 0, // call
          },
        ],
      ]);
    transactions.push({
      to: RUMPEL_MODULE,
      value: "0",
      data: executeInitWithdrawalTransactionData,
    });
  }

  const batchJson = TxBuilder.batch(RUMPEL_ADMIN_SAFE, transactions);

  // Create safe-batches in working directory if it doesn't exist
  const safeBatchesFolder = path.join(
    process.cwd(),
    "/js-scripts/resolvS1Claim/safe-batches"
  );

  // Write the result to a file in the safe-batches folder
  const outputPath = path.join(safeBatchesFolder, `resolvS1ClaimBatch.json`);
  await fs.writeFile(outputPath, JSON.stringify(batchJson, null, 2));
};

// await writeClaimResponses();
// await writeS1TotalFinalPoints();
// await generateSafeBatch();
