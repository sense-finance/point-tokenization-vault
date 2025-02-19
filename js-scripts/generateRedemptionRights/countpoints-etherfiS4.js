import { readFileSync } from "fs";

// received transaction
// https://etherscan.io/tx/0x8ca29113461d936c01b7f34a9f4d8649d0e271cbe1b89ddcd0798210b2466c6d
const rewards = 25299464779708667665;

// copy and paste from: https://oracle.rumpel.xyz/
// Date Queued: 2/18/2025
const data = JSON.parse(
  readFileSync(
    `${process.cwd()}/js-scripts/generateRedemptionRights/etherfi-s4-distribution.json`
  )
);

// deployment tx of 0xd0b520304dC2dF26c8C73294901220D549217aAc:
// https://etherscan.io/tx/0x856c39ebd8fe3b3cc7c5ad5e21b4d3954caa8c763a915e73b64aa9af3ab9bba1
const etherFi4PointToken = "0xd0b520304dC2dF26c8C73294901220D549217aAc";

const etherFi4Point =
  "0x1652756d70656c206b50743a2045544845524649205334066b7045462d340000";

const pTokens = data.balances;

let total = 0;
for (const user in pTokens) {
  total += parseInt(pTokens[user][etherFi4Point]);
}

const totalPTokens = total;
const rewardsPerPToken = (rewards * 1e18) / totalPTokens;

console.log();
console.log(rewards.toLocaleString("fullwide", { useGrouping: false }));

console.log();
console.log("Total pTokens - claimed and unclaimed:");
console.log(totalPTokens.toLocaleString("fullwide", { useGrouping: false }));

console.log();
console.log("rewards per ptoken");
console.log(
  rewardsPerPToken.toLocaleString("fullwide", { useGrouping: false })
);
console.log((rewardsPerPToken / 1e18).toFixed(18));

console.log();
console.log(
  `rewardsPerToken is rounded down: ${
    rewards >= (rewardsPerPToken * totalPTokens) / 1e18
  }`
);
console.log(
  ((rewardsPerPToken * totalPTokens) / 1e18).toLocaleString("fullwide", {
    useGrouping: false,
  })
);
console.log(rewards.toLocaleString("fullwide", { useGrouping: false }));
