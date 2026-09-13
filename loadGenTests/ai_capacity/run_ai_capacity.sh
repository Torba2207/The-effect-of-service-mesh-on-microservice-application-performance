#!/usr/bin/env bash
# AI host capacity smoke test — a rate ladder against /api/Ai/generate, driven from the load
# generator. Each rung is held for a fixed duration while GPU/CPU are sampled on the AI host;
# the ladder stops at the first rung that fails, so an overloaded host is never pushed further.
#
# A rung PASSES when: fail_rate < 1%, wrong answers < 1%, dropped iterations < 1% (k6 kept up
# with the target rate), and p95 latency is under the -p limit.
#
# Usage: ./run_ai_capacity.sh [options]
#   -a AI_IP      AI host, used for the default URL and GPU/CPU sampling    (default 10.29.20.121)
#   -u URL        AI entry point                                            (default http://<AI_IP>:5005)
#   -r "RATES"    space-separated req/s ladder                              (default "3 6 12")
#   -d DURATION   hold time per rung                                        (default 120s)
#   -w WARMUP     warm-up at the same rate before each rung, discarded      (default 15s)
#   -g SECONDS    rest between rungs, lets any backlog drain                (default 30)
#   -p MS         p95 latency limit for a pass                              (default 3000)
#   -V N          cap on concurrent in-flight requests                      (default 60)
#   -f            keep climbing even after a failed rung
#
# Example:
#   ./run_ai_capacity.sh                       # 3, 6, 12 req/s, 2 min each
#   ./run_ai_capacity.sh -r "12 15 20" -d 60s  # probe the ceiling further
#
# Output: results/ai_capacity.csv (one row per rung) + per-rung k6 JSON/log and GPU samples.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"

AI_IP="10.29.20.121"
URL=""
RATES="3 6 12"
DURATION="120s"
WARMUP="15s"
GAP=30
P95_LIMIT=3000
MAX_VUS=60
FORCE=false

LG_IP="10.29.20.130"
LG_DIR="/root/thesis-tests/ai_capacity"

while getopts "a:u:r:d:w:g:p:V:f" opt; do
  case "$opt" in
    a) AI_IP="$OPTARG" ;;
    u) URL="$OPTARG" ;;
    r) RATES="$OPTARG" ;;
    d) DURATION="$OPTARG" ;;
    w) WARMUP="$OPTARG" ;;
    g) GAP="$OPTARG" ;;
    p) P95_LIMIT="$OPTARG" ;;
    V) MAX_VUS="$OPTARG" ;;
    f) FORCE=true ;;
    *) echo "Invalid parameter"; exit 2 ;;
  esac
done
[ -z "$URL" ] && URL="http://${AI_IP}:5005"

# --- SSH key (same resolution as the Phase A Core) ---
normalize_ssh_key_path() {
  local p="$1"
  if command -v wslpath >/dev/null 2>&1; then
    wslpath -u "$p" 2>/dev/null && return 0 || true
  fi
  if [[ "$p" =~ ^[A-Za-z]:[\\/] ]]; then
    python3 - "$p" <<'PY'
import re, sys
m = re.match(r'^([A-Za-z]):[\\/](.*)$', sys.argv[1])
if m: print(f"/mnt/{m.group(1).lower()}/{m.group(2).replace(chr(92), '/')}")
else: print(sys.argv[1])
PY
  else
    printf '%s\n' "$p"
  fi
}

SSH_KEY="${SSH_PRIVATE_KEY:-}"
if [ -z "$SSH_KEY" ]; then
  [ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE not found and \$SSH_PRIVATE_KEY unset"; exit 1; }
  SSH_KEY="$(sed -n 's/^SSH_PRIVATE_KEY=//p' "$ENV_FILE" | head -1 | sed 's/^['\''"]//;s/['\''"]$//')"
fi
[ -n "$SSH_KEY" ] && SSH_KEY="$(normalize_ssh_key_path "$SSH_KEY")"
[ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ] || { echo "ERROR: SSH key not found"; exit 1; }

SSH_KEY_TMP="/tmp/ai_capacity_ssh_key.$$"
cp "$SSH_KEY" "$SSH_KEY_TMP" 2>/dev/null || { echo "ERROR: could not copy SSH key"; exit 1; }
chmod 600 "$SSH_KEY_TMP"
SAMPLER_STARTED=false
cleanup() {
  if [ "$SAMPLER_STARTED" = true ]; then
    ssh $KEY_OPTS root@"$AI_IP" 'pkill -f "[a]i_capacity_sampler.sh" 2>/dev/null' >/dev/null 2>&1 || true
  fi
  rm -f "$SSH_KEY_TMP"
}
trap cleanup EXIT
KEY_OPTS="-i $SSH_KEY_TMP -o StrictHostKeyChecking=no -o BatchMode=yes -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8"

RESULTS="$HERE/results"; mkdir -p "$RESULTS"
CSV="$RESULTS/ai_capacity.csv"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

# The prompt is seeded, so the correct answer is known in advance: Python's random.Random(42),
# exactly as the MCP tool computes it. Any other payload is a wrong answer.
EXPECTED="$(python3 -c 'import random, json; r = random.Random(42); print(json.dumps([r.randint(1, 100) for _ in range(10)]))')"

echo "============================================================"
echo " AI capacity ladder :: $URL"
echo " Rates: [$RATES] req/s | hold $DURATION (+ $WARMUP warm-up) | rest ${GAP}s"
echo " Pass: fail<1%, wrong<1%, dropped<1%, p95<${P95_LIMIT}ms | in-flight cap $MAX_VUS"
echo " Expected answer: $EXPECTED"
echo "============================================================"

# --- Preflight ---
echo "[preflight] lg: k6 present and AI reachable from lg..."
ssh $KEY_OPTS root@"$LG_IP" 'command -v k6 >/dev/null' || { echo "ERROR: k6 missing on lg"; exit 1; }
code="$(ssh $KEY_OPTS root@"$LG_IP" "curl -s -m 10 -o /dev/null -w '%{http_code}' $URL/api/Ai/health" || true)"
[ "$code" = "200" ] || { echo "ERROR: $URL/api/Ai/health from lg -> http=$code"; exit 1; }

echo "[preflight] AI host: model placement..."
PLACEMENT="$(ssh $KEY_OPTS root@"$AI_IP" 'for c in $(docker ps --format "{{.Names}}" | grep ^ai-service-); do printf "%s: " "$c"; docker exec "$c" /app/data/ollama_engine/bin/ollama ps | awk "NR>1{print \$0}" | sed "s/  */ /g"; done' 2>/dev/null || true)"
if [ -n "$PLACEMENT" ]; then
  echo "$PLACEMENT" | sed 's/^/   /'
  echo "$PLACEMENT" | grep -q 'CPU' && echo "   WARNING: at least one backend runs the model (partly) on CPU"
else
  echo "   (could not read ollama ps on $AI_IP — GPU sampling will be skipped)"
fi

echo "[preflight] one request end to end..."
first="$(ssh $KEY_OPTS root@"$LG_IP" "curl -s -m 60 -o /dev/null -w '%{http_code} %{time_total}' -X POST $URL/api/Ai/generate -H 'Content-Type: application/json' -d '{\"user_input\":\"Give me 10 random numbers between 1 and 100 with seed 42\"}'" || true)"
echo "   generate -> http=${first% *} in ${first#* }s"
[ "${first% *}" = "200" ] || { echo "ERROR: first request failed, not starting the ladder"; exit 1; }

# --- Sync ---
ssh $KEY_OPTS root@"$LG_IP" "mkdir -p $LG_DIR"
scp $KEY_OPTS "$HERE/ai-capacity.js" root@"$LG_IP":"$LG_DIR/" >/dev/null

GPU_OK=false
if ssh $KEY_OPTS root@"$AI_IP" 'command -v nvidia-smi >/dev/null' 2>/dev/null; then
  GPU_OK=true
  # Once per second: epoch, GPU utilisation %, GPU memory used MiB, host 1-min load average.
  ssh $KEY_OPTS root@"$AI_IP" 'cat > /tmp/ai_capacity_sampler.sh && chmod +x /tmp/ai_capacity_sampler.sh' <<'SAMPLER'
#!/usr/bin/env bash
while :; do
  gpu="$(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits | head -1 | tr -d ' ')"
  echo "$(date +%s),${gpu},$(cut -d' ' -f1 /proc/loadavg)"
  sleep 1
done
SAMPLER
fi

# --- Ladder ---
K6_ENV="BASE_URL=$URL MAX_VUS=$MAX_VUS EXPECTED='$EXPECTED'"
declare -a SUMMARY_LINES=()

for rate in $RATES; do
  run_id="${STAMP}_${rate}rps"
  echo "---- ${rate} req/s ----"

  echo "   warm-up $WARMUP (discarded)"
  ssh $KEY_OPTS root@"$LG_IP" \
    "cd $LG_DIR && $K6_ENV RATE=$rate DURATION=$WARMUP K6_SUMMARY_OUT=/tmp/ai_cap_warm.json k6 run --quiet ai-capacity.js" \
    >/dev/null 2>&1 || true

  # GPU + host load sampler, running only for the measured window.
  if [ "$GPU_OK" = true ]; then
    ssh $KEY_OPTS root@"$AI_IP" "nohup /tmp/ai_capacity_sampler.sh > /tmp/${run_id}_gpu.csv 2>/dev/null < /dev/null &" || true
    SAMPLER_STARTED=true
  fi

  echo "   measuring $DURATION"
  ssh $KEY_OPTS root@"$LG_IP" \
    "cd $LG_DIR && $K6_ENV RATE=$rate DURATION=$DURATION K6_SUMMARY_OUT=/tmp/${run_id}.json k6 run --quiet ai-capacity.js" \
    > "$RESULTS/k6_${run_id}.log" 2>&1 || true

  if [ "$GPU_OK" = true ]; then
    ssh $KEY_OPTS root@"$AI_IP" 'pkill -f "[a]i_capacity_sampler.sh"' >/dev/null 2>&1 || true
    ssh $KEY_OPTS root@"$AI_IP" "cat /tmp/${run_id}_gpu.csv" > "$RESULTS/${run_id}_gpu.csv" 2>/dev/null || true
  fi
  ssh $KEY_OPTS root@"$LG_IP" "cat /tmp/${run_id}.json" > "$RESULTS/k6_${run_id}.json" 2>/dev/null || echo '{}' > "$RESULTS/k6_${run_id}.json"

  verdict="$(python3 - "$RESULTS/k6_${run_id}.json" "$RESULTS/${run_id}_gpu.csv" "$CSV" "$STAMP" "$URL" "$rate" "$P95_LIMIT" <<'PY'
import csv, json, os, sys
summ_path, gpu_path, csv_path, stamp, url, rate, p95_limit = sys.argv[1:8]
try:
    s = json.load(open(summ_path))
except Exception:
    s = {}

util, mem, load = [], [], []
if os.path.exists(gpu_path):
    for line in open(gpu_path):
        parts = line.strip().split(",")
        if len(parts) == 4:
            try:
                util.append(float(parts[1])); mem.append(float(parts[2])); load.append(float(parts[3]))
            except ValueError:
                pass
avg = lambda xs: sum(xs) / len(xs) if xs else None
mx = lambda xs: max(xs) if xs else None

def pct(x):
    return "n/a" if x is None else f"{x * 100:.1f}%"

reasons = []
if not s.get("reqs"):
    reasons.append("no summary (k6 did not finish)")
else:
    if s.get("aborted"): reasons.append("aborted by k6 threshold")
    if (s.get("fail_rate") or 0) >= 0.01: reasons.append(f"fail {pct(s['fail_rate'])}")
    if (s.get("wrong_answer_rate") or 0) >= 0.01: reasons.append(f"wrong {pct(s['wrong_answer_rate'])}")
    if (s.get("drop_rate") or 0) >= 0.01: reasons.append(f"dropped {pct(s['drop_rate'])}")
    if (s.get("lat_p95_ms") or 0) >= float(p95_limit): reasons.append(f"p95 {s['lat_p95_ms']:.0f}ms")
verdict = "PASS" if not reasons else "FAIL"

row = {
    "stamp": stamp, "url": url, "rate_target": rate,
    "rate_achieved": s.get("rate_achieved"), "reqs": s.get("reqs"),
    "fail_rate": s.get("fail_rate"), "wrong_answer_rate": s.get("wrong_answer_rate"),
    "drop_rate": s.get("drop_rate"),
    "lat_p50_ms": s.get("lat_p50_ms"), "lat_p95_ms": s.get("lat_p95_ms"),
    "lat_p99_ms": s.get("lat_p99_ms"), "lat_max_ms": s.get("lat_max_ms"),
    "svc_exec_p50_ms": s.get("svc_exec_p50_ms"),
    "gpu_util_avg": avg(util), "gpu_util_max": mx(util), "gpu_mem_max_mib": mx(mem),
    "host_load1_max": mx(load), "verdict": verdict, "reasons": "; ".join(reasons),
}
new = not os.path.exists(csv_path)
with open(csv_path, "a", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(row))
    if new: w.writeheader()
    w.writerow(row)

def num(x, fmt):
    return "n/a" if x is None else format(x, fmt)

print(f"{verdict}|{rate:>5} req/s  got {num(s.get('rate_achieved'), '.2f'):>6}"
      f"  fail {pct(s.get('fail_rate')):>6}  wrong {pct(s.get('wrong_answer_rate')):>6}"
      f"  drop {pct(s.get('drop_rate')):>6}"
      f"  p50 {num(s.get('lat_p50_ms'), '.0f'):>5}ms  p95 {num(s.get('lat_p95_ms'), '.0f'):>5}ms"
      f"  p99 {num(s.get('lat_p99_ms'), '.0f'):>5}ms"
      f"  GPU {num(avg(util), '.0f'):>3}%/{num(mx(mem), '.0f'):>5}MiB"
      f"  {verdict}{'  (' + '; '.join(reasons) + ')' if reasons else ''}")
PY
)"
  status="${verdict%%|*}"
  line="${verdict#*|}"
  echo "   $line"
  SUMMARY_LINES+=("$line")

  if [ "$status" != "PASS" ] && [ "$FORCE" != true ]; then
    echo "   stopping the ladder: ${rate} req/s failed (use -f to keep climbing)"
    break
  fi

  echo "   resting ${GAP}s"
  sleep "$GAP"
  code="$(ssh $KEY_OPTS root@"$LG_IP" "curl -s -m 10 -o /dev/null -w '%{http_code}' $URL/api/Ai/health" || true)"
  if [ "$code" != "200" ]; then
    echo "   AI health after rest -> http=$code; stopping so the host can recover"
    break
  fi
done

echo "============================================================"
echo " Summary ($STAMP)"
for l in "${SUMMARY_LINES[@]}"; do echo "  $l"; done
echo " -> $CSV"
echo "============================================================"
