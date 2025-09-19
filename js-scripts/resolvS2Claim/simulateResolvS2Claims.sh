#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)

SAFE_HASHES_SCRIPT=${SAFE_HASHES_SCRIPT:-"$ROOT_DIR/../safe-tx-hashes-util/safe_hashes.sh"}
SAFE_HASHES_RUNNER=${SAFE_HASHES_RUNNER:-"/opt/homebrew/bin/bash"}
BATCH_FILE=${BATCH_FILE:-"$SCRIPT_DIR/safe-batches/resolvS2ClaimBatch.json"}
RPC_URL=${MAINNET_RPC_URL:-}
SAFE_ADDRESS="0x9D89745fD63Af482ce93a9AdB8B0BbDbb98D3e06"

if [[ -z "$RPC_URL" ]]; then
  echo "Error: MAINNET_RPC_URL is not set" >&2
  exit 1
fi

if [[ ! -x "$SAFE_HASHES_SCRIPT" ]]; then
  echo "Error: safe-hashes script not found at $SAFE_HASHES_SCRIPT" >&2
  exit 1
fi

if [[ ! -x "$SAFE_HASHES_RUNNER" ]]; then
  SAFE_HASHES_RUNNER=$(command -v bash)
fi

if [[ -z "$SAFE_HASHES_RUNNER" ]]; then
  echo "Error: unable to locate bash runtime for safe hashes script" >&2
  exit 1
fi

if [[ ! -f "$BATCH_FILE" ]]; then
  echo "Error: batch file not found at $BATCH_FILE" >&2
  exit 1
fi

if ! command -v cast >/dev/null 2>&1; then
  echo "Error: cast is not installed" >&2
  exit 1
fi

START_NONCE=${SAFE_NONCE:-"$(cast call "$SAFE_ADDRESS" "nonce()(uint256)" --rpc-url "$RPC_URL")"}

if [[ -z "$START_NONCE" ]]; then
  echo "Error: unable to determine Safe nonce" >&2
  exit 1
fi

TOTAL=$(jq '.transactions | length' "$BATCH_FILE")
if [[ "$TOTAL" -eq 0 ]]; then
  echo "Error: no transactions found in batch file" >&2
  exit 1
fi

nonce=$START_NONCE

for ((idx=0; idx<TOTAL; idx++)); do
  to=$(jq -r ".transactions[$idx].to" "$BATCH_FILE")
  value=$(jq -r ".transactions[$idx].value" "$BATCH_FILE")
  data=$(jq -r ".transactions[$idx].data" "$BATCH_FILE")
  operation=$(jq -r ".transactions[$idx].operation // \"0\"" "$BATCH_FILE")
  sim_args=("--interactive")
  if (( idx % 2 == 0 )); then
    sim_args+=("--simulate" "$RPC_URL")
  fi

  echo "=== Simulating tx #$((idx+1)) (nonce $nonce) ==="
  printf '\n%s\n%s\n%s\n%s\n0\n0\n0\n0x0000000000000000000000000000000000000000\n0x0000000000000000000000000000000000000000\n' \
    "$to" \
    "$value" \
    "$data" \
    "$operation" \
    | "$SAFE_HASHES_RUNNER" "$SAFE_HASHES_SCRIPT" \
        --network ethereum \
        --address "$SAFE_ADDRESS" \
        --nonce "$nonce" \
        "${sim_args[@]}"

  nonce=$((nonce + 1))
done
