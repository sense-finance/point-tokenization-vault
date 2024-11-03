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
  getContract,
  erc20Abi,
} from "viem";
import { mainnet } from "viem/chains";
import { MerkleTree } from "merkletreejs";
import { pointTokenVaultABI } from "./abis/point-token-vault.ts";
import { LosslessNumber, parse, stringify } from "lossless-json";

// Types
type PointsBalance = Map<`0x${string}`, bigint>;
type RedemptionRightsMap = Map<Address, PointsBalance>;

interface AlphaDistributionData {
  pTokens: {
    [address: Address]: {
      [pointsId: `0x${string}`]: {
        accumulatingPoints: LosslessNumber;
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

interface PTokenSnapshot {
  address: Address;
  blockNumber: string;
  balances: {
    [address: string]: string;
  };
}

// Overrides
const UNI_POOL_OVERRIDES = {
  "0x597a1b0515bbeEe6796B89a6f403c3fD41BB626C": {
    "0x24C694d193B19119bcDea9D40a3b0bfaFb281E6D": "6487631537430741114",
    "0x44Cb2d713BDa3858001f038645fD05E23E5DE03D": "27597767454066598826095",
  },
};

// Config
dotenv.config({ path: "./js-scripts/generateRedemptionRights/.env" });
const config = {
  rpcUrl: process.env.MAINNET_RPC_URL,
  pTokenAddresses: (process.env.PTOKEN_ADDRESSES as string)?.split(
    ","
  ) as Address[],
  pointsIds: (process.env.POINTS_IDS as string)?.split(",") as `0x${string}`[],
  rewardsPerPToken: (process.env.REWARDS_PER_P_TOKEN as string)?.split(
    ","
  ) as string[],
  pointTokenVaultAddress: process.env.POINT_TOKEN_VAULT_ADDRESS as Address,
};

// Core functions
async function calculateRedemptionRights(
  client: PublicClient,
  pTokenAddress: Address,
  rewardsMultiplier: string,
  pointsId: `0x${string}`,
  previousDistribution: AlphaDistributionData
): Promise<[Map<Address, bigint>, PTokenSnapshot]> {
  const redemptionRights = new Map<Address, bigint>();
  const rewardsMultiplierBigInt = BigInt(rewardsMultiplier);
  const blockNumber = await client.getBlockNumber();

  const logs = await client.getLogs({
    address: pTokenAddress,
    event: parseAbiItem(
      "event Transfer(address indexed from, address indexed to, uint256)"
    ),
    fromBlock: 0n,
    toBlock: "latest",
  });

  // Track raw pToken balances separately
  const pTokenBalances = new Map<Address, bigint>();

  for (const log of logs) {
    const [from, to, value] = log.args as [Address, Address, bigint];

    // Update redemption rights
    if (from !== zeroAddress) {
      redemptionRights.set(
        from,
        (redemptionRights.get(from) || 0n) -
          (value * rewardsMultiplierBigInt) / BigInt(1e18)
      );
      pTokenBalances.set(from, (pTokenBalances.get(from) || 0n) - value);
    }
    if (to !== zeroAddress) {
      redemptionRights.set(
        to,
        (redemptionRights.get(to) || 0n) +
          (value * rewardsMultiplierBigInt) / BigInt(1e18)
      );
      pTokenBalances.set(to, (pTokenBalances.get(to) || 0n) + value);
    }
  }

  // Apply UNI pool overrides after processing all transfers
  for (const [poolAddress, redistributions] of Object.entries(
    UNI_POOL_OVERRIDES
  )) {
    const poolBalance = pTokenBalances.get(poolAddress as Address) || 0n;
    if (poolBalance > 0n) {
      // Remove balance from pool
      pTokenBalances.set(poolAddress as Address, 0n);
      redemptionRights.set(poolAddress as Address, 0n);

      // Redistribute to specified addresses
      for (const [recipient, amount] of Object.entries(redistributions)) {
        const recipientAddress = recipient as Address;
        const overrideAmount = BigInt(amount);

        pTokenBalances.set(
          recipientAddress,
          (pTokenBalances.get(recipientAddress) || 0n) + overrideAmount
        );

        redemptionRights.set(
          recipientAddress,
          (redemptionRights.get(recipientAddress) || 0n) +
            (overrideAmount * rewardsMultiplierBigInt) / BigInt(1e18)
        );
      }
    }
  }

  // Add unclaimed pToken balances
  const pointTokenVault = getContract({
    address: config.pointTokenVaultAddress,
    abi: pointTokenVaultABI,
    client,
  });
  for (const [userAddress, addressPointsData] of Object.entries(
    previousDistribution.pTokens
  )) {
    const { accumulatingPoints } = addressPointsData[pointsId];

    const claimedPtokens = (await pointTokenVault.read.claimedPTokens([
      userAddress,
      pointsId,
    ])) as bigint;

    const unclaimedPtokens =
      BigInt(accumulatingPoints.toString()) - claimedPtokens;

    if (unclaimedPtokens > 0n) {
      pTokenBalances.set(
        userAddress as Address,
        (pTokenBalances.get(userAddress as Address) || 0n) + unclaimedPtokens
      );
    }
  }

  // Create snapshot object
  const snapshot: PTokenSnapshot = {
    address: pTokenAddress,
    blockNumber: blockNumber.toString(),
    balances: Object.fromEntries(
      Array.from(pTokenBalances.entries())
        .filter(([_, balance]) => balance > 0n)
        .map(([addr, balance]) => [addr, balance.toString()])
    ),
  };

  return [
    new Map(
      Array.from(redemptionRights.entries()).filter(
        ([_, balance]) => balance > 0n
      )
    ),
    snapshot,
  ];
}

function generateMerkleData(
  allRedemptionRights: RedemptionRightsMap,
  previousDistribution: AlphaDistributionData
): MerklizedData {
  const prefix = keccak256(encodePacked(["string"], ["REDEMPTION_RIGHTS"]));

  // Generate redemption rights leaves
  const rightsLeaves = Array.from(allRedemptionRights.entries()).flatMap(
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

  // Generate pTokens leaves
  const pTokenLeaves = Object.entries(previousDistribution.pTokens).flatMap(
    ([address, pointsData]) =>
      Object.entries(pointsData).map(([pointsId, data]) =>
        keccak256(
          encodePacked(
            ["address", "bytes32", "uint256"],
            [
              address as Address,
              pointsId as `0x${string}`,
              BigInt(data.accumulatingPoints.toString()),
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
      Array.from(allRedemptionRights.entries()).map(([address, balances]) => [
        address,
        Object.fromEntries(
          Array.from(balances.entries()).map(([pointsId, balance]) => [
            pointsId,
            {
              amount: balance.toString(),
              proof: tree.getHexProof(
                keccak256(
                  encodePacked(
                    ["bytes32", "address", "bytes32", "uint256"],
                    [prefix, address, pointsId, balance]
                  )
                )
              ) as `0x${string}`[],
            },
          ])
        ),
      ])
    ),
    pTokens: Object.fromEntries(
      Object.entries(previousDistribution.pTokens).map(
        ([address, pointsData]) => [
          address,
          Object.fromEntries(
            Object.entries(pointsData).map(([pointsId, data]) => [
              pointsId,
              {
                amount: data.accumulatingPoints.toString(),
                proof: tree.getHexProof(
                  keccak256(
                    encodePacked(
                      ["address", "bytes32", "uint256"],
                      [
                        address as Address,
                        pointsId as `0x${string}`,
                        BigInt(data.accumulatingPoints.toString()),
                      ]
                    )
                  )
                ) as `0x${string}`[],
              },
            ])
          ),
        ]
      )
    ),
  };
}

// Main execution
async function generateMerkleTree(): Promise<void> {
  const client = createPublicClient({
    chain: mainnet,
    transport: http(config.rpcUrl),
  });

  // Validate config
  if (
    !config.rpcUrl ||
    !config.pTokenAddresses.length ||
    !config.pointsIds.length ||
    config.pTokenAddresses.length !== config.pointsIds.length
  ) {
    throw new Error("Invalid configuration");
  }

  console.log(`Processing at block #${await client.getBlockNumber()}`);

  const previousDistribution = parse(
    fs.readFileSync(
      "js-scripts/generateRedemptionRights/last-alpha-distribution.json",
      "utf8"
    )
  ) as AlphaDistributionData;

  // Calculate rights for each token
  const allRedemptionRights: RedemptionRightsMap = new Map();
  const snapshots: { [address: string]: PTokenSnapshot } = {};

  for (let i = 0; i < config.pTokenAddresses.length; i++) {
    const [rights, snapshot] = await calculateRedemptionRights(
      client,
      config.pTokenAddresses[i],
      config.rewardsPerPToken[i],
      config.pointsIds[i],
      previousDistribution
    );
    snapshots[config.pTokenAddresses[i]] = snapshot;

    for (const [addr, balance] of rights.entries()) {
      if (!allRedemptionRights.has(addr))
        allRedemptionRights.set(addr, new Map());
      allRedemptionRights.get(addr)!.set(config.pointsIds[i], balance);
    }
  }

  // Save individual snapshots for each pToken
  for (const [pTokenAddress, snapshot] of Object.entries(snapshots)) {
    const pTokenContract = getContract({
      address: pTokenAddress as Address,
      abi: erc20Abi,
      client,
    });

    const symbol = await pTokenContract.read.symbol();
    const fileName = `ptoken-snapshot-${symbol.toLowerCase()}.json`;

    // Add address to the snapshot data
    const snapshotWithAddress: PTokenSnapshot = {
      ...snapshot,
      address: pTokenAddress as Address,
    };

    fs.writeFileSync(
      `js-scripts/generateRedemptionRights/out/${fileName}`,
      JSON.stringify(snapshotWithAddress, null, 2)
    );
  }

  // Generate merkle data
  const merklizedData = generateMerkleData(
    allRedemptionRights,
    previousDistribution
  );

  console.log("Merkle root:", merklizedData.root);
  fs.writeFileSync(
    "js-scripts/generateRedemptionRights/out/merged-distribution.json",
    JSON.stringify(merklizedData, null, 2)
  );
}

generateMerkleTree().catch(console.error);
