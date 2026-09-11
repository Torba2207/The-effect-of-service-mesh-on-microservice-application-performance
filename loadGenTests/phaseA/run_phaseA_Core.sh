#!/usr/bin/env bash
# Unified Phase A Orchestrator — Isolated S1 testing (Baseline)
# Usage: ./run_phaseA_Core.sh -s <service_name> [opts]
# Examples:
#   ./run_phaseA_Core.sh -s digital -r 5 -l "low med"
#
#   ./run_phaseA_Core.sh -s fibonacci -r 5 -l "low med"
#   ./run_phaseA_Core.sh -s fibonacci -u http://<istio-gateway>:80     # full-URL override (e.g. Istio)
#
#   ./run_phaseA_Core.sh -s integration -r 5 -l "low med"
#
#   ./run_phaseA_Core.sh -s permutation -r 5 -l "low med"
#
#   ./run_phaseA_Core.sh -s video -r 5 -l "low med"
#   ./run_phaseA_Core.sh -s video -u http://<istio-gateway>:80     # full-URL override (e.g. Istio)


set -euo pipefail

# --- Lock Execution Directory ---
# Ensures the script runs strictly from the directory it is written in.
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# --- Fixed Environment Paths ---
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
COMMON="$HERE/../common"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"

# --- Default Parameters ---
SERVICE_NAME=""
NODE_IP="10.29.20.113"
URL=""
LEVELS="low med high"
REPS=10
WARMUP="30s"
STEADY="120s"
COOLDOWN=30

MESH="baseline"
MTLS="na"
LG_IP="10.29.20.130"
LG_DIR="/root/thesis-tests/phaseA"
CTX="projekt-badawchy-cluster"
PROM_SVC="cluster-monitor-kube-prome-prometheus"
PROM_LOCAL="http://localhost:9090"

# --- Parse Arguments ---
while getopts "s:u:n:l:r:W:S:C:" opt; do
  case "$opt" in
    s) SERVICE_NAME="$OPTARG" ;;
    u) URL="$OPTARG" ;;
    n) NODE_IP="$OPTARG" ;;
    l) LEVELS="$OPTARG" ;;
    r) REPS="$OPTARG" ;;
    W) WARMUP="$OPTARG" ;;
    S) STEADY="$OPTARG" ;;
    C) COOLDOWN="$OPTARG" ;;
    *) echo "Invalid parameter"; exit 2 ;;
  esac
done

if [ -z "$SERVICE_NAME" ]; then
  echo "ERROR: You must provide a service name using -s"
  exit 1
fi

# Set default URL before sourcing, as PREFLIGHT_CMD depends on it[cite: 3].
[ -z "$URL" ] && URL="http://${NODE_IP}:30080"

# --- 1. Load Datafile ---
if ! source "$HERE/phaseA_Data.sh" "$SERVICE_NAME"; then
  exit 1
fi

# --- 2. Fail-Fast Local Validation ---
echo "[check] Validating local dependencies..."
if [ ! -d "$HERE/$SERVICE_DIR" ]; then
  echo "ERROR: Service directory missing at $HERE/$SERVICE_DIR"
  exit 1
fi

RESULTS="$HERE/$SERVICE_DIR/results"; mkdir -p "$RESULTS"
CSV="$RESULTS/master.csv"

if [ ! -f "$HERE/$SERVICE_DIR/$JS_FILE" ]; then
  echo "ERROR: K6 script missing at $HERE/$SERVICE_DIR/$JS_FILE"
  exit 1
fi

if [ "$HAS_ASSETS" == "true" ]; then
  if [ ! -f "$COMMON/assets/$ASSET_FILE" ]; then
    echo "ERROR: Required asset missing at $COMMON/assets/$ASSET_FILE"
    exit 1
  fi
fi

# --- 3. SSH Setup & Preflight ---
SSH_KEY="${SSH_PRIVATE_KEY:-}"
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

if [ -z "$SSH_KEY" ]; then
  [ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE not found and \$SSH_PRIVATE_KEY unset"; exit 1; }
  SSH_KEY="$(sed -n 's/^SSH_PRIVATE_KEY=//p' "$ENV_FILE" | head -1 | sed 's/^['\''"]//;s/['\''"]$//')"
fi
[ -n "$SSH_KEY" ] && SSH_KEY="$(normalize_ssh_key_path "$SSH_KEY")"
[ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ] || { echo "ERROR: SSH key not found"; exit 1; }

SSH_KEY_TMP="/tmp/phaseA_ssh_key.$$"
cp "$SSH_KEY" "$SSH_KEY_TMP" 2>/dev/null || { echo "ERROR: could not copy SSH key"; exit 1; }
chmod 600 "$SSH_KEY_TMP"
SSH_KEY="$SSH_KEY_TMP"
SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8"
KEY_OPTS="-i $SSH_KEY $SSH_OPTS"

cleanup() {
  kill "${PF_PID:-}" 2>/dev/null || true
  rm -f "${SSH_KEY_TMP:-}"
}
trap cleanup EXIT

echo "============================================================"
echo " [Phase A] Starting unified test :: $CONFIG"
echo " Target URL: $URL"
echo " Service Dir: $SERVICE_DIR | Script: $JS_FILE"
echo "------------------------------------------------------------"
echo " Load Levels: [$LEVELS] | Repetitions:$REPS"
echo " Warmup: $WARMUP | Measurement: $STEADY | Cooldown:${COOLDOWN}s"
echo "============================================================"

echo "[preflight] lg ssh..."
ssh $KEY_OPTS root@"$LG_IP" 'command -v k6 >/dev/null' || { echo "k6 missing on lg"; exit 1; }
echo "[preflight] kube context..."
kubectl --context "$CTX" get ns thesis-test >/dev/null || { echo "kube context unreachable"; exit 1; }
echo "[preflight] target URL..."
eval "$PREFLIGHT_CMD" || true

# --- 4. Sync Files ---
echo "[sync] copying $JS_FILE to lg:$LG_DIR ..."
ssh $KEY_OPTS root@"$LG_IP" "mkdir -p $LG_DIR/assets"
scp $KEY_OPTS "$HERE/$SERVICE_DIR/$JS_FILE" root@"$LG_IP":"$LG_DIR/" >/dev/null

if [ "$HAS_ASSETS" == "true" ]; then
  echo "[sync] copying asset $ASSET_FILE to lg:$LG_DIR/assets/ ..."
  scp $KEY_OPTS "$COMMON/assets/$ASSET_FILE" root@"$LG_IP":"$LG_DIR/assets/" >/dev/null
fi

# --- 5. Prometheus Setup ---
start_pf() {
  kubectl --context "$CTX" -n monitoring port-forward "svc/$PROM_SVC" 9090:9090 >/dev/null 2>&1 &
  PF_PID=$!
  sleep 4
}
ensure_pf() {
  if ! curl -s -m 4 -o /dev/null "$PROM_LOCAL/-/ready"; then
    echo "[prom] port-forward down, restarting..."
    kill "${PF_PID:-}" 2>/dev/null || true; start_pf
  fi
}
start_pf
ensure_pf

# --- 6. Execution Loop ---
K6_ENV="BASE_URL=$URL $K6_EXTRA_ENV"

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

  python3 "$COMMON/collect_metrics.py" \
    --prom "$PROM_LOCAL" --config "$CONFIG" --mesh "$MESH" --mtls "$MTLS" \
    --level "$level" --rep "$rep" --run-id "$run_id" \
    --start "$start" --end "$end" --summary "$RESULTS/k6_${run_id}.json" --csv "$CSV"

  # Extract this run's CPU/RAM time-series while it is still in Prometheus (1h tmpfs retention).
  python3 "$COMMON/extract_timeseries.py" --prom "$PROM_LOCAL" --master "$CSV" \
    --run-id "$run_id" --append --out "$RESULTS/timeseries_${CONFIG}.csv" --step 10 >/dev/null 2>&1 || true
}

for level in $LEVELS; do
  for rep in $(seq 1 "$REPS"); do
    run_one "$level" "$rep"
  done
done

echo "============================================================"
echo " DONE: $CONFIG -> $CSV  (+ results/timeseries_${CONFIG}.csv)"
echo "============================================================"