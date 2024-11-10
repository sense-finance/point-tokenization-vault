import { readFileSync } from "fs";

const rewards = 132431200000000000000000 / 1e18;

const data = JSON.parse(
  readFileSync(
    `${process.cwd()}/js-scripts/generateRedemptionRights/last-alpha-distribution.json`
  )
);

const kpSatId =
  "0x1852756d70656c206b506f696e743a20457468656e61205332066b7053415453";

const pTokens = data.pTokens;

let total = 0;
for (const user in pTokens) {
  console.log(pTokens[user][kpSatId]);
  total += pTokens[user][kpSatId].accumulatingPoints;
}
console.log(total);
const totalPTokens = total / 1e18;
const rewardsPerPToken = rewards / totalPTokens;
console.log(rewardsPerPToken * 2);
