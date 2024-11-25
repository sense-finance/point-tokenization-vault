import { readFileSync } from "fs";

// https://explorer.zircuit.com/address/0xfd418e42783382E86Ae91e445406600Ba144D162?activeTab=3
// balanceOf(  0x25E426b153e74Ab36b2685c3A464272De60888Ae  )

// received transaction -> value here is rounded in explorer
// https://explorer.zircuit.com/tx/0xbeac890e91bbc50ea7281506c7f1b3912584330f4c1b8548177eedc8eb7e4d45
const rewards = 100048737683233891942400;


// copy and paste from: distribution-block:21246006.json
// https://github.com/sense-finance/pToken-distributions/blob/main/mainnet/distribution-block%3A21246006.json
const data = JSON.parse(
  readFileSync(
    `${process.cwd()}/js-scripts/generateRedemptionRights/zirc-s2-distribution.json`
  )
);

// deployment tx of 0x700b95a30aFcf0e55ADEb9CE647E780B23A635ae:
// https://etherscan.io/tx/0x0bb973a11c7c478e52f42624612f71056815049c64feab055d29fa15f648dd9a#eventlog
// Log3: 1652756D70656C206B50743A205A697263756974205332076B705A52432D3200
const zircS2Point =
  "0x1652756d70656c206b50743a205a697263756974205332076b705a52432d3200";

const pTokens = data.wallets;

let total = 0;
for (const user in pTokens) {
  total += parseInt(pTokens[user][zircS2Point].amount);
}

const totalPTokens = total;
const rewardsPerPToken = rewards * 1e18 / totalPTokens;

console.log();
console.log(rewards.toLocaleString('fullwide', { useGrouping: false }));

console.log();
console.log("Total pTokens - claimed and unclaimed:");
console.log(totalPTokens.toLocaleString('fullwide', { useGrouping: false }));

console.log();
console.log("rewards per ptoken");
console.log(rewardsPerPToken.toLocaleString('fullwide', { useGrouping: false }));
console.log((rewardsPerPToken / 1e18));

console.log();
console.log(`rewardsPerToken is rounded down: ${rewards >= rewardsPerPToken * totalPTokens / 1e18}`)
console.log((rewardsPerPToken * totalPTokens / 1e18).toLocaleString('fullwide', { useGrouping: false }));
console.log(rewards.toLocaleString('fullwide', { useGrouping: false }));