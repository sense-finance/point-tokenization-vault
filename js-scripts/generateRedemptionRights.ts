import * as fs from "fs";
import * as dotenv from "dotenv";
import {
  keccak256,
  encodePacked,
  createPublicClient,
  http,
  parseAbiItem,
  Address,
  zeroAddress,
} from "viem";
import { mainnet } from "viem/chains";
import { MerkleTree } from "merkletreejs";

function solidityKeccak256(types: string[], values: any[]) {
  return keccak256(encodePacked(types, values));
}

dotenv.config({ path: "./scripts/.env" });

const MAINNET_RPC_URL = process.env.MAINNET_RPC_URL;
const PTOKEN_ADDRESSES = (process.env.PTOKEN_ADDRESSES as string).split(
  ","
) as Address[];
const POINTS_IDS = (process.env.POINTS_IDS as string).split(
  ","
) as `0x${string}`[];

const REDEMPTION_RIGHTS_PREFIX = solidityKeccak256(
  ["string"],
  ["REDEMPTION_RIGHTS"]
);

if (
  !MAINNET_RPC_URL ||
  PTOKEN_ADDRESSES.length === 0 ||
  POINTS_IDS.length === 0
) {
  console.error(
    "Please set MAINNET_RPC_URL, PTOKEN_ADDRESSES, and POINTS_IDS in your .env file"
  );
  process.exit(1);
}

if (PTOKEN_ADDRESSES.length !== POINTS_IDS.length) {
  console.error(
    "The number of PTOKEN_ADDRESSES must match the number of POINTS_IDS"
  );
  process.exit(1);
}

async function generateMerkleTree() {
  const publicClient = createPublicClient({
    chain: mainnet,
    transport: http(MAINNET_RPC_URL),
  });

  const latestBlock = await publicClient.getBlockNumber();
  console.log(`latest block #: ${latestBlock}`);

  const allHolders = new Map<string, Map<string, bigint>>();

  for (let i = 0; i < PTOKEN_ADDRESSES.length; i++) {
    const pTokenAddress = PTOKEN_ADDRESSES[i];
    const pointsId = POINTS_IDS[i];

    console.log(
      `Processing pToken: ${pTokenAddress} with Points ID: ${pointsId}`
    );

    const logs = await publicClient.getLogs({
      address: pTokenAddress,
      event: parseAbiItem(
        "event Transfer(address indexed from, address indexed to, uint256)"
      ),
      fromBlock: 0n,
      toBlock: "latest",
    });

    const holders = new Map<string, bigint>();

    for (const log of logs) {
      const [from, to, value] = log.args as [Address, Address, bigint];
      if (!from || !to || value === undefined) {
        throw new Error("Transfer event args are undefined");
      }

      if (from !== zeroAddress) {
        const fromBalance = (holders.get(from) || 0n) - value;
        holders.set(from, fromBalance);
      }

      if (to !== zeroAddress) {
        const toBalance = (holders.get(to) || 0n) + value;
        holders.set(to, toBalance);
      }
    }

    for (const [address, balance] of holders.entries()) {
      if (balance > 0n) {
        if (!allHolders.has(address)) {
          allHolders.set(address, new Map());
        }
        allHolders.get(address)!.set(pointsId, balance);
      }
    }
  }

  // TODO: for ptokens being LP'd in Uni, give the redemption rights to the LPs themselves rather than the pool address

  console.log("Generating Merkle tree...");

  const leaves = Array.from(allHolders.entries()).flatMap(
    ([address, balances]) =>
      Array.from(balances.entries()).map(([pointsId, balance]) =>
        solidityKeccak256(
          ["bytes32", "address", "bytes32", "uint256"],
          [REDEMPTION_RIGHTS_PREFIX, address, pointsId, balance.toString()]
        )
      )
  );

  const sortedLeaves = leaves.sort((a, b) => a.localeCompare(b));
  const tree = new MerkleTree(sortedLeaves, keccak256, { sortPairs: true });
  const root = tree.getHexRoot();

  const merklizedPointsData = {
    wallets: Object.fromEntries(
      Array.from(allHolders.entries()).map(([userAddress, balances]) => [
        userAddress,
        Object.fromEntries(
          Array.from(balances.entries()).map(([pointsId, balance]) => {
            const leaf = solidityKeccak256(
              ["bytes32", "address", "bytes32", "uint256"],
              [
                REDEMPTION_RIGHTS_PREFIX,
                userAddress,
                pointsId,
                balance.toString(),
              ]
            );
            return [
              pointsId,
              {
                amount: balance.toString(),
                proof: tree.getHexProof(leaf),
              },
            ];
          })
        ),
      ])
    ),
    root,
  };

  console.log("Merkle tree generated successfully.");
  console.log("Root:", root);
  console.log(
    "Total number of holders:",
    Object.keys(merklizedPointsData.wallets).length
  );

  // Save the merklizedPointsData to a JSON file
  fs.writeFileSync(
    "merklizedPointsData.json",
    JSON.stringify(merklizedPointsData, null, 2)
  );
  console.log("Merkle data saved to merklizedPointsData.json");
}

generateMerkleTree().catch(console.error);
