#!/usr/bin/env bash
# Closed-loop AI / S2-ext probe for ONE configuration. Measures real chain latency of
# the AI-touching scenarios (ai_generate, permutation_from_ai, filters_ai_matrix) at
# concurrency 1, so the AI VM is never overloaded. Appends per-scenario rows to
# results/ai_probe.csv.
#
# Usage:  ./run_ai_probe.sh -c <label> -m <baseline|istio|linkerd> -t <mtls> [-i ITERS] [-u URL]
# Example: ./run_ai_probe.sh -c linkerd_mtls -m linkerd -t on
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"; PB="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$PB/../.." && pwd)"

# SSH key: $SSH_PRIVATE_KEY if set, else the SSH_PRIVATE_KEY entry in the repo-root .env
# (override the file with ENV_FILE=/path/to/.env).
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"
SSH_KEY="${SSH_PRIVATE_KEY:-}"
if [ -z "$SSH_KEY" ]; then
  [ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE not found and \$SSH_PRIVATE_KEY unset"; exit 1; }
  SSH_KEY="$(sed -n 's/^SSH_PRIVATE_KEY=//p' "$ENV_FILE" | head -1 | sed 's/^["'\'']//;s/["'\'']$//')"
fi
[ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ] || { echo "ERROR: SSH key not found (SSH_PRIVATE_KEY='$SSH_KEY')"; exit 1; }

SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"
LG_IP="10.29.20.130"; LG_DIR="/root/thesis-tests/phaseB/ai_probe"

NODE_IP="10.29.20.113"; URL=""; ITERS=90; CONFIG=""; MESH=""; MTLS=""
while getopts "c:m:t:i:u:n:" opt; do case "$opt" in
  c) CONFIG="$OPTARG";; m) MESH="$OPTARG";; t) MTLS="$OPTARG";;
  i) ITERS="$OPTARG";; u) URL="$OPTARG";; n) NODE_IP="$OPTARG";; *) echo bad; exit 2;; esac; done
[ -z "$CONFIG" ] || [ -z "$MESH" ] || [ -z "$MTLS" ] && { echo "ERROR: -c -m -t required"; exit 2; }
[ -z "$URL" ] && URL="http://${NODE_IP}:30080"
KEY_OPTS="-i $SSH_KEY $SSH_OPTS"
RESULTS="$PB/results"; mkdir -p "$RESULTS"; CSV="$RESULTS/ai_probe.csv"
RUN="${CONFIG}_aiprobe"

echo "== AI probe :: config=$CONFIG mesh=$MESH mtls=$MTLS url=$URL iters=$ITERS (1 VU, ~$((ITERS*5))s) =="

# preflight: AI healthy?
code=$(curl -s -m 90 -o /dev/null -w '%{http_code}' -X POST "$URL/api/Ai/generate" \
  -H 'Content-Type: application/json' -d '{"user_input":"Give me 3 random numbers between 1 and 10 with seed 7"}')
echo "[preflight] AI generate -> http=$code"
[ "$code" != "200" ] && { echo "AI not healthy (http=$code) — aborting so we don't probe a melted VM"; exit 1; }

# sync + run (closed-loop, single VU -> AI never sees >1 concurrent request)
ssh $KEY_OPTS root@"$LG_IP" "mkdir -p $LG_DIR"
scp $KEY_OPTS "$HERE/ai_probe.js" root@"$LG_IP":"$LG_DIR/" >/dev/null
ssh $KEY_OPTS root@"$LG_IP" \
  "cd $LG_DIR && BASE_URL=$URL ITERS=$ITERS K6_SUMMARY_OUT=/tmp/${RUN}.json k6 run --quiet ai_probe.js" \
  > "$RESULTS/k6_${RUN}.log" 2>&1 || true
ssh $KEY_OPTS root@"$LG_IP" "cat /tmp/${RUN}.json" > "$RESULTS/k6_${RUN}.json" 2>/dev/null || echo '{"scenarios":{}}' > "$RESULTS/k6_${RUN}.json"

# append per-scenario rows
python3 - "$CSV" "$RESULTS/k6_${RUN}.json" "$CONFIG" "$MESH" "$MTLS" <<'PY'
import csv, json, os, sys
csv_path, summ_path, config, mesh, mtls = sys.argv[1:6]
fields = ["config","mesh","mtls","scenario","reqs","fail_rate",
          "lat_avg_ms","lat_p50_ms","lat_p90_ms","lat_p95_ms","lat_p99_ms","lat_max_ms"]
summ = json.load(open(summ_path)).get("scenarios", {})
new = not os.path.exists(csv_path)
with open(csv_path, "a", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
    if new: w.writeheader()
    for scen, m in summ.items():
        row = {"config": config, "mesh": mesh, "mtls": mtls, "scenario": scen}
        row.update(m); w.writerow(row)
        print("  %-22s reqs=%s fail=%s p50=%.0fms p95=%.0fms"
              % (scen, m.get("reqs"), m.get("fail_rate"),
                 m.get("lat_p50_ms") or 0, m.get("lat_p95_ms") or 0))
PY
echo "== done -> $CSV =="
