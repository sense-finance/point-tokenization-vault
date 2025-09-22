import { TxBuilder } from "@morpho-labs/gnosis-tx-builder";
import fs from "fs/promises";
import path from "path";
import {
  RUMPEL_ADMIN_SAFE,
  RUMPEL_MODULE,
  RUMPEL_MODULE_INTERFACE,
} from "../resolvS1Registration/resolveS1Constants";
import { Interface } from "ethers";

const STAKED_RESOLV_TOKEN_DISTRIBUTOR_ADDRESS =
  "0xFc7d46929Bc3dc2ca9533A6Fc5e9896d401604a4";
const STAKED_RESOLV_ADDRESS = "0xFE4BCE4b3949c35fB17691D8b03c3caDBE2E5E23";
const DATA_DIR = path.join(process.cwd(), "js-scripts/resolvS2Claim");
const CLAIMS_FILE = path.join(DATA_DIR, "resolvS2Claims.json");
const SAFE_BATCH_DIR = path.join(DATA_DIR, "safe-batches");
const SAFE_BATCH_FILE = path.join(SAFE_BATCH_DIR, "resolvS2ClaimBatch.json");
const CSV_FILE = path.join(DATA_DIR, "resolvS2Earners.csv");

type ClaimPayload = {
  id: number;
  minorAmount: string;
  proof: string[];
};

type ClaimMap = Record<string, ClaimPayload>;

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
      }
      const message = await response.json();
      if (message && message.message) {
        return message;
      }
      throw Error;
    } catch (error) {
      if (attempt < retries) {
        console.warn(`Attempt ${attempt} failed. Retrying in ${delay}ms...`);
        console.warn(url);
        console.warn(error);
        await new Promise((resolve) => setTimeout(resolve, delay));
        delay *= backoffFactor;
      } else {
        console.error(`All ${retries} attempts failed.`);
        throw error;
      }
    }
  }
};

const readSeasonTwoAddresses = async (): Promise<string[]> => {
  const csvRaw = await fs.readFile(CSV_FILE, "utf8");
  return csvRaw
    .trim()
    .split("\n")
    .slice(1)
    .map((row) => row.split(",")[0]?.trim())
    .filter((address): address is string => Boolean(address));
};

const fetchClaims = async (addresses: string[]): Promise<ClaimMap> => {
  let claims: ClaimMap = {};
  const missing: string[] = [];
  for (let i = 0; i < addresses.length; i += 10) {
    const chunk = addresses.slice(i, i + 10);
    const results = await Promise.all(
      chunk.map(async (address) => {
        const response = await fetchWithRetries(
          `https://api.resolv.xyz/claim/merkle-proofs?address=${address}`
        );
        if (!response || response.message) {
          missing.push(address);
          return null;
        }
        return { address, data: response };
      })
    );
    results
      .filter((r): r is { address: string; data: ClaimPayload } => Boolean(r))
      .forEach(({ address, data }) => {
        claims[address] = {
          id: data.id,
          minorAmount: data.minorAmount,
          proof: data.proof,
        };
      });
    console.log(`${Math.min(i + 10, addresses.length)} wallets processed`);
  }
  if (missing.length) {
    console.warn(`No claim proof returned for ${missing.length} wallets.`);
    console.warn(JSON.stringify(missing, null, 2));
  }
  return claims;
};

const writeClaims = async (claims: ClaimMap) => {
  await fs.writeFile(CLAIMS_FILE, JSON.stringify(claims, null, 2));
};

const generateSafeBatch = async (claims: ClaimMap) => {
  const distributorInterface = new Interface([
    "function claim(uint256 _index,uint256 _amount,bytes32[] calldata _merkleProof) external",
  ]);
  const stkResolvInterface = new Interface([
    "function initiateWithdrawal(uint256 _amount) external",
  ]);

  const txs = Object.entries(claims).flatMap(([safe, payload]) => {
    const amount = BigInt(payload.minorAmount);
    const claimData = distributorInterface.encodeFunctionData("claim", [
      payload.id,
      amount,
      payload.proof,
    ]);
    const claimTx = {
      to: RUMPEL_MODULE,
      value: "0",
      data: RUMPEL_MODULE_INTERFACE.encodeFunctionData("exec", [
        [
          {
            safe,
            to: STAKED_RESOLV_TOKEN_DISTRIBUTOR_ADDRESS,
            data: claimData,
            operation: 0,
          },
        ],
      ]),
    };
    const withdrawData = stkResolvInterface.encodeFunctionData(
      "initiateWithdrawal",
      [amount]
    );
    const withdrawTx = {
      to: RUMPEL_MODULE,
      value: "0",
      data: RUMPEL_MODULE_INTERFACE.encodeFunctionData("exec", [
        [
          {
            safe,
            to: STAKED_RESOLV_ADDRESS,
            data: withdrawData,
            operation: 0,
          },
        ],
      ]),
    };
    return [claimTx, withdrawTx];
  });

  const batchJson = TxBuilder.batch(RUMPEL_ADMIN_SAFE, txs);
  await fs.mkdir(SAFE_BATCH_DIR, { recursive: true });
  await fs.writeFile(SAFE_BATCH_FILE, JSON.stringify(batchJson, null, 2));
};

const main = async () => {
  const addresses = await readSeasonTwoAddresses();
  console.log(`Loaded ${addresses.length} S2 wallets`);
  const claims = await fetchClaims(addresses);
  await writeClaims(claims);
  await generateSafeBatch(claims);
};

await main();
