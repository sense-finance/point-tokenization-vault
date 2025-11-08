import "dotenv/config";
import { formatUnits, getAddress } from "ethers";
import type { Hex } from "viem";

const KV_URL = process.env.KV_REST_API_URL?.replace(/\/$/, "");
const KV_TOKEN = process.env.KV_REST_API_TOKEN;
const ETHENA_ROOT = "0x3d99219fbd49ace3f48d6ca1340e505ec1bdf27d1f8d0e15ec9f286cc9215fcd";
const ETHENA_S3 = "https://airdrop-data-ethena-s4.s3.us-west-2.amazonaws.com";
const POINT_ID = "0x1552756d70656c206b50743a20457468656e61205334086b70534154532d3400";

if (!KV_URL || !KV_TOKEN) throw new Error("Missing KV credentials");

async function kvGet<T>(key: string): Promise<T | null> {
  const res = await fetch(`${KV_URL}/get/${encodeURIComponent(key)}`, {
    headers: { Authorization: `Bearer ${KV_TOKEN}` },
  });
  const json = (await res.json()) as { result?: T };
  const v = json.result;
  return v == null ? null : typeof v === "string" ? JSON.parse(v) : v;
}

async function fetchSena(addr: Hex): Promise<bigint> {
  const url = `${ETHENA_S3}/${getAddress(addr)}/${ETHENA_ROOT}-${getAddress(addr)}.json`;
  const res = await fetch(url);
  if (!res.ok) return 0n;
  const json = (await res.json()) as { events?: { awardAmount: string }[]; claimed?: boolean };
  return json.events?.[0] && !json.claimed ? BigInt(json.events[0].awardAmount) : 0n;
}

async function main() {
  const exec = await kvGet<string[]>("distributions:executed");
  const ts = exec![exec!.length - 1];
  const wallets = await kvGet<Record<string, Record<string, string>>>(`distributions:${ts}:wallets`);

  let totalKPoints = 0n;
  let totalSena = 0n;

  for (const [addr, pts] of Object.entries(wallets!)) {
    const kp = pts[POINT_ID];
    if (!kp || kp === "0") continue;
    totalKPoints += BigInt(kp);
    totalSena += await fetchSena(getAddress(addr) as Hex);
  }

  const senaFull = (totalSena * 35n) / 25n;
  const rewardsPerPToken = (senaFull * 10n ** 18n) / totalKPoints;
  const current = 10691798002514229n;

  console.log("=== Ethena S4 REWARDS_PER_PTOKEN Validation ===\n");
  console.log(`Distribution: ${ts}`);
  console.log(`Total kPoints: ${formatUnits(totalKPoints, 18)}`);
  console.log(`Total sENA (2.5/3.5): ${formatUnits(totalSena, 18)}`);
  console.log(`Total sENA (3.5/3.5): ${formatUnits(senaFull, 18)}\n`);
  console.log(`Calculated: ${formatUnits(rewardsPerPToken, 18)}`);
  console.log(`Current:    ${formatUnits(current, 18)}`);
  console.log(`Match: ${rewardsPerPToken === current ? "✅" : "❌"}\n`);
}

main().catch(console.error);
