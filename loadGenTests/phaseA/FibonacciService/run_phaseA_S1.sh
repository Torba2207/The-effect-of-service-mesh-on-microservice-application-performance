#!/usr/bin/env bash
# Phase A Orchestrator — Isolated S1 (FibonacciService) testing.
# Specialized version for research: baseline (no service mesh, no AI).
# Ported with aggregate/loop engine logic from Phase B.
#
# Usage:
#   ./run_phaseA_S1.sh [opts]
# Example:
#   ./run_phaseA_S1.sh -r 5 -l "low med"
#   ./run_phaseA_S1.sh -u http://<istio-gateway>:80     # full-URL override (e.g. Istio)

set -euo pipefail

# --- Fixed Environment ---
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"

# Read SSH private key from .env or environment variable
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"
SSH_KEY="${SSH_PRIVATE_KEY:-}"
if [ -z "$SSH_KEY" ]; then
  [ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE not found and \$SSH_PRIVATE_KEY unset"; exit 1; }
  SSH_KEY="$(sed -n 's/^SSH_PRIVATE_KEY=//p' "$ENV_FILE" | head -1 | sed 's/^["'\'']//;s/["'\'']$//')"
fi
[ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ] || { echo "ERROR: SSH key not found (SSH_PRIVATE_KEY='$SSH_KEY')"; exit 1; }

SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8"
LG_IP="10.29.20.130"
LG_DIR="/root/thesis-tests/phaseA"
CTX="projekt-badawchy-cluster"
PROM_SVC="cluster-monitor-kube-prome-prometheus"
PROM_LOCAL="http://localhost:9090"

# --- HARDCODED PARAMETERS FOR S1 (FibonacciService) BASELINE ---
CONFIG="baseline_fibonacci_S1"
MESH="baseline"
MTLS="na"
SERVICE="fibonacci-service"
JS_FILE="fibonacci-test.js"

# --- Default load parameters (can be overridden via flags) ---
NODE_IP="10.29.20.113"
URL=""
LEVELS="low med high"
REPS=10
WARMUP="30s"
STEADY="120s"
COOLDOWN=30
# Fibonacci work-unit size (n). Larger n => O(n^2) BigInteger work => more app CPU.
# Calibrated ceiling: pods are capped at 500m x 3 = 1.5 cores; n>=30000 saturates at
# 100 rps (high). n=20000 sustains high at ~10ms/req with headroom -> clean CPU curve.
# Overridable with -N.  (Phase B uses 3000; keep that as the neutral default.)
FIB_N="${FIB_N:-3000}"

# Parse arguments (load management parameters only)
while getopts "u:n:N:l:r:W:S:C:" opt; do
  case "$opt" in
    u) URL="$OPTARG" ;;
    n) NODE_IP="$OPTARG" ;;
    N) FIB_N="$OPTARG" ;;
    l) LEVELS="$OPTARG" ;;
    r) REPS="$OPTARG" ;;
    W) WARMUP="$OPTARG" ;;
    S) STEADY="$OPTARG" ;;
    C) COOLDOWN="$OPTARG" ;;
    *) echo "Invalid parameter"; exit 2 ;;
  esac
done

# apply the default only if -u wasn't supplied
[ -z "$URL" ] && URL="http://${NODE_IP}:30080"

RESULTS="$HERE/results"; mkdir -p "$RESULTS"
CSV="$RESULTS/master.csv"
KEY_OPTS="-i $SSH_KEY $SSH_OPTS"

echo "============================================================"
echo " [Phase A] Starting isolated test :: SERVICE S1 (FibonacciService)"
echo " Profile: BASELINE (No Mesh / No mTLS)"
echo " Target URL: $URL"
echo " Test Script: $JS_FILE | Fibonacci n = $FIB_N"
echo "------------------------------------------------------------"
echo " Load Levels: [$LEVELS] | Repetitions:$REPS"
echo " Warmup: $WARMUP | Measurement: $STEADY | Cooldown:${COOLDOWN}s"
echo "============================================================"

# --- preflight ---
echo "[preflight] lg ssh..."
ssh $KEY_OPTS root@"$LG_IP" 'command -v k6 >/dev/null' || { echo "k6 missing on lg"; exit 1; }
echo "[preflight] kube context..."
kubectl --context "$CTX" get ns thesis-test >/dev/null || { echo "kube context unreachable"; exit 1; }
echo "[preflight] target URL..."
# Check the specific app route with a small POST to ensure the backend actually responds,
# preventing false positives from a generic Ingress 404 response.
curl -s -m 8 -X POST -H "Content-Type: application/json" \
  -d '{"n":10}' \
  -o /dev/null -w '   api -> http=%{http_code}\n' "$URL/api/fibonacci/calculate" || true

# --- sync assets + script to lg ---
echo "[sync] copying $JS_FILE to lg:$LG_DIR ..."
ssh $KEY_OPTS root@"$LG_IP" "mkdir -p $LG_DIR"
scp $KEY_OPTS "$HERE/$JS_FILE" root@"$LG_IP":"$LG_DIR/" >/dev/null

# --- Prometheus port-forward ---
start_pf() {
  kubectl --context "$CTX" -n monitoring port-forward "svc/$PROM_SVC" 9090:9090 >/dev/null 2>&1 &
  PF_PID=$!
  sleep 4
}
ensure_pf() {  # restart if it died
  if ! curl -s -m 4 -o /dev/null "$PROM_LOCAL/-/ready"; then
    echo "[prom] port-forward down, restarting..."
    kill "$PF_PID" 2>/dev/null || true; start_pf
  fi
}
start_pf
trap 'kill "$PF_PID" 2>/dev/null || true' EXIT
ensure_pf

K6_ENV="BASE_URL=$URL FIB_N=$FIB_N"

run_one() {
  local level="$1" rep="$2"
  local run_id="${CONFIG}_${level}_r${rep}"
  echo "---- $run_id ----"

  # warm-up (discarded)
  ssh $KEY_OPTS root@"$LG_IP" \
    "cd $LG_DIR && $K6_ENV LEVEL=$level DURATION=$WARMUP K6_SUMMARY_OUT=/tmp/warm.json k6 run --quiet $JS_FILE" \
    >/dev/null 2>&1 || true

  # steady (measured)
  local start end
  start=$(date -u +%s)
  ssh $KEY_OPTS root@"$LG_IP" \
    "cd $LG_DIR && $K6_ENV LEVEL=$level DURATION=$STEADY K6_SUMMARY_OUT=/tmp/${run_id}.json k6 run --quiet $JS_FILE" \
    > "$RESULTS/k6_${run_id}.log" 2>&1 || true
  end=$(date -u +%s)

  # retrieve per-scenario summary
  ssh $KEY_OPTS root@"$LG_IP" "cat /tmp/${run_id}.json" > "$RESULTS/k6_${run_id}.json" 2>/dev/null || echo '{"scenarios":{}}' > "$RESULTS/k6_${run_id}.json"

  sleep "$COOLDOWN"
  ensure_pf

  python3 "$HERE/../../common/collect_metrics.py" \
    --prom "$PROM_LOCAL" --config "$CONFIG" --mesh "$MESH" --mtls "$MTLS" \
    --level "$level" --rep "$rep" --run-id "$run_id" \
    --start "$start" --end "$end" --summary "$RESULTS/k6_${run_id}.json" --csv "$CSV"

  python3 "$HERE/../../common/extract_timeseries.py" --prom "$PROM_LOCAL" --master "$CSV" \
    --run-id "$run_id" --append --out "$RESULTS/timeseries_${CONFIG}.csv" --step 10 >/dev/null 2>&1 || true
}

for level in $LEVELS; do
  for rep in $(seq 1 "$REPS"); do
    run_one "$level" "$rep"
  done
done

echo "============================================================"
echo " DONE: $CONFIG -> $CSV   (+ results/timeseries_${CONFIG}.csv)"
echo "============================================================"
