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
  PublicClient,
} from "viem";
import { mainnet } from "viem/chains";
import { MerkleTree } from "merkletreejs";

// Core types
type PointsBalance = Map<`0x${string}`, bigint>;
type RedemptionRightsMap = Map<Address, PointsBalance>;

interface AlphaDistributionData {
  pTokens: {
    [address: Address]: {
      [pointsId: `0x${string}`]: {
        accumulatingPoints: string;
      };
    };
  };
}

interface MerklizedData {
  root: `0x${string}`;
  redemptionRights: {
    [address: Address]: {
      [pointsId: `0x${string}`]: {
        amount: string;
        proof: `0x${string}`[];
      };
    };
  };
  pTokens: {
    [address: Address]: {
      [pointsId: `0x${string}`]: {
        amount: string;
        proof: `0x${string}`[];
      };
    };
  };
}

// Load config
dotenv.config({ path: "./js-scripts/generateRedemptionRights/.env" });
const config = {
  rpcUrl: process.env.MAINNET_RPC_URL,
  pTokenAddresses: (process.env.PTOKEN_ADDRESSES as string)?.split(
    ","
  ) as Address[],
  pointsIds: (process.env.POINTS_IDS as string)?.split(",") as `0x${string}`[],
  rewardsPerPToken: process.env.REWARDS_PER_P_TOKEN as string,
};

// Core functions
async function calculateRedemptionRights(
  client: PublicClient,
  pTokenAddress: Address
): Promise<Map<Address, bigint>> {
  const redemptionRights = new Map<Address, bigint>();
  const rewardsMultiplier = BigInt(config.rewardsPerPToken);

  const logs = await client.getLogs({
    address: pTokenAddress,
    event: parseAbiItem(
      "event Transfer(address indexed from, address indexed to, uint256)"
    ),
    fromBlock: 0n,
    toBlock: "latest",
  });

  for (const log of logs) {
    const [from, to, value] = log.args as [Address, Address, bigint];

    if (from !== zeroAddress) {
      redemptionRights.set(
        from,
        (redemptionRights.get(from) || 0n) -
          (value * rewardsMultiplier) / BigInt(1e18)
      );
    }
    if (to !== zeroAddress) {
      redemptionRights.set(
        to,
        (redemptionRights.get(to) || 0n) +
          (value * rewardsMultiplier) / BigInt(1e18)
      );
    }
  }

  return new Map(
    Array.from(redemptionRights.entries()).filter(
      ([_, balance]) => balance > 0n
    )
  );
}

function generateMerkleData(
  allRights: RedemptionRightsMap,
  previousDistribution: AlphaDistributionData
): MerklizedData {
  const prefix = keccak256(encodePacked(["string"], ["REDEMPTION_RIGHTS"]));

  // Generate leaves
  const rightsLeaves = Array.from(allRights.entries()).flatMap(
    ([address, balances]) =>
      Array.from(balances.entries()).map(([pointsId, balance]) =>
        keccak256(
          encodePacked(
            ["bytes32", "address", "bytes32", "uint256"],
            [prefix, address, pointsId, balance]
          )
        )
      )
  );

  const pTokenLeaves = Object.entries(previousDistribution.pTokens).flatMap(
    ([address, pointsData]) =>
      Object.entries(pointsData).map(([pointsId, data]) =>
        keccak256(
          encodePacked(
            ["address", "bytes32", "uint256"],
            [
              address as Address,
              pointsId as `0x${string}`,
              BigInt(data.accumulatingPoints),
            ]
          )
        )
      )
  );

  // Build tree
  const tree = new MerkleTree(
    [...rightsLeaves, ...pTokenLeaves].sort(),
    keccak256,
    { sortPairs: true }
  );

  return {
    root: tree.getHexRoot() as `0x${string}`,
    redemptionRights: Object.fromEntries(
      Array.from(allRights.entries()).map(([addr, balances]) => [
        addr,
        Object.fromEntries(
          Array.from(balances.entries()).map(([pointsId, balance]) => [
            pointsId,
            {
              amount: balance.toString(),
              proof: tree.getHexProof(
                keccak256(
                  encodePacked(
                    ["bytes32", "address", "bytes32", "uint256"],
                    [prefix, addr, pointsId, balance]
                  )
                )
              ) as `0x${string}`[],
            },
          ])
        ),
      ])
    ),
    pTokens: Object.fromEntries(
      Object.entries(previousDistribution.pTokens).map(([addr, pointsData]) => [
        addr,
        Object.fromEntries(
          Object.entries(pointsData).map(([pointsId, data]) => [
            pointsId,
            {
              amount: data.accumulatingPoints,
              proof: tree.getHexProof(
                keccak256(
                  encodePacked(
                    ["address", "bytes32", "uint256"],
                    [
                      addr as Address,
                      pointsId as `0x${string}`,
                      BigInt(data.accumulatingPoints),
                    ]
                  )
                )
              ) as `0x${string}`[],
            },
          ])
        ),
      ])
    ),
  };
}

// Main execution
async function generateMerkleTree(): Promise<void> {
  const client = createPublicClient({
    chain: mainnet,
    transport: http(config.rpcUrl),
  });

  // Validate inputs
  if (
    !config.rpcUrl ||
    !config.pTokenAddresses.length ||
    !config.pointsIds.length ||
    config.pTokenAddresses.length !== config.pointsIds.length
  ) {
    throw new Error("Invalid configuration");
  }

  console.log(`Processing at block #${await client.getBlockNumber()}`);

  // Calculate rights for each token
  const allRights: RedemptionRightsMap = new Map();
  for (let i = 0; i < config.pTokenAddresses.length; i++) {
    const rights = await calculateRedemptionRights(
      client,
      config.pTokenAddresses[i]
    );
    for (const [addr, balance] of rights.entries()) {
      if (!allRights.has(addr)) allRights.set(addr, new Map());
      allRights.get(addr)!.set(config.pointsIds[i], balance);
    }
  }

  // Generate merkle data
  const previousDistribution = JSON.parse(
    fs.readFileSync(
      "js-scripts/generateRedemptionRights/last-alpha-distribution.json",
      "utf8"
    )
  ) as AlphaDistributionData;

  const merklizedData = generateMerkleData(allRights, previousDistribution);

  console.log("Merkle root:", merklizedData.root);
  fs.writeFileSync(
    "js-scripts/generateRedemptionRights/out/merged-distribution.json",
    JSON.stringify(merklizedData, null, 2)
  );
}

generateMerkleTree().catch(console.error);
