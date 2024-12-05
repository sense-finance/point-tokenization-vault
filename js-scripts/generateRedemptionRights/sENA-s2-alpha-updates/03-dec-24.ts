import { keccak256, encodePacked } from "viem";
import { MerkleTree } from "merkletreejs";
import mergedDistribution from "../out/merged-distribution.json";
import fs from "fs";

const NEW_SENA = 25467538460000000000000n;

const updateRedemptionRights = () => {
  // Calculate total existing rights
  const total = Object.values(mergedDistribution.redemptionRights).reduce(
    (acc, userRights) => {
      const amount = Object.values(userRights)[0].amount;
      return acc + BigInt(amount);
    },
    0n
  );

  // Update each user's rights proportionally
  for (const [address, rights] of Object.entries(
    mergedDistribution.redemptionRights
  )) {
    const tokenId = Object.keys(rights)[0];
    const currentAmount = BigInt(rights[tokenId].amount);

    // Calculate proportion and new amount
    const newAmount = (currentAmount * NEW_SENA) / total;
    const updatedAmount = currentAmount + newAmount;

    // Update in the distribution object
    mergedDistribution.redemptionRights[address][tokenId].amount =
      updatedAmount.toString();
  }

  // Regenerate merkle tree
  const prefix = keccak256(encodePacked(["string"], ["REDEMPTION_RIGHTS"]));

  // Generate redemption rights leaves
  const rightsLeaves = Object.entries(
    mergedDistribution.redemptionRights
  ).flatMap(([address, rights]) =>
    Object.entries(rights).map(([pointsId, data]) =>
      keccak256(
        encodePacked(
          ["bytes32", "address", "bytes32", "uint256"],
          [
            prefix,
            address as `0x${string}`,
            pointsId as `0x${string}`,
            BigInt(data.amount),
          ]
        )
      )
    )
  );

  // Generate pTokens leaves
  const pTokenLeaves = Object.entries(mergedDistribution.pTokens).flatMap(
    ([address, pointsData]) =>
      Object.entries(pointsData).map(([pointsId, data]) =>
        keccak256(
          encodePacked(
            ["address", "bytes32", "uint256"],
            [
              address as `0x${string}`,
              pointsId as `0x${string}`,
              BigInt(data.amount),
            ]
          )
        )
      )
  );

  // Build tree
  const tree = new MerkleTree(
    [...rightsLeaves, ...pTokenLeaves].sort(),
    keccak256,
    {
      sortPairs: true,
    }
  );

  // Update root
  mergedDistribution.root = tree.getHexRoot();

  // Update proofs for redemption rights
  for (const [address, rights] of Object.entries(
    mergedDistribution.redemptionRights
  )) {
    for (const [pointsId, data] of Object.entries(rights)) {
      const leaf = keccak256(
        encodePacked(
          ["bytes32", "address", "bytes32", "uint256"],
          [
            prefix,
            address as `0x${string}`,
            pointsId as `0x${string}`,
            BigInt(data.amount),
          ]
        )
      );
      mergedDistribution.redemptionRights[address][pointsId].proof =
        tree.getHexProof(leaf);
    }
  }

  // Update proofs for pTokens
  for (const [address, pointsData] of Object.entries(
    mergedDistribution.pTokens
  )) {
    for (const [pointsId, data] of Object.entries(pointsData)) {
      const leaf = keccak256(
        encodePacked(
          ["address", "bytes32", "uint256"],
          [
            address as `0x${string}`,
            pointsId as `0x${string}`,
            BigInt(data.amount),
          ]
        )
      );
      mergedDistribution.pTokens[address][pointsId].proof =
        tree.getHexProof(leaf);
    }
  }

  // Write updated distribution back to file
  fs.writeFileSync(
    "./js-scripts/generateRedemptionRights/out/merged-distribution-03Dec24.json",
    JSON.stringify(mergedDistribution, null, 2)
  );
};

updateRedemptionRights();
