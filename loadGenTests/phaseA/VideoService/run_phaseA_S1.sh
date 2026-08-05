#!/usr/bin/env bash
# Phase A Orchestrator — Isolated S1 (VideoService) testing.
# Specialized version for research: baseline (no service mesh, no AI).
# HVY workload: real ffmpeg x264 transcode of a fixed MP4 (multipart upload).
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
COMMON="$HERE/../../common"

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

# --- HARDCODED PARAMETERS FOR S1 (VideoService) BASELINE ---
CONFIG="baseline_video_S1"
MESH="baseline"
MTLS="na"
SERVICE="video-service"
JS_FILE="video-test.js"
VID_ASSET="sample_360p_1s.mp4"

# --- Default load parameters (can be overridden via flags) ---
NODE_IP="10.29.20.113"
URL=""
LEVELS="low med high"
REPS=10
WARMUP="30s"
STEADY="120s"
COOLDOWN=30
# HVY video rates (rps) — calibrated against the raised 4-core x3 pod ceiling.
# Passed to k6 as RATE_LOW/MED/HIGH; the JS falls back to the same defaults.
RATE_LOW=6
RATE_MED=12
RATE_HIGH=18

# Parse arguments (load management parameters only)
while getopts "u:n:l:r:W:S:C:" opt; do
  case "$opt" in
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

# apply the default only if -u wasn't supplied
[ -z "$URL" ] && URL="http://${NODE_IP}:30080"

RESULTS="$HERE/results"; mkdir -p "$RESULTS"
CSV="$RESULTS/master.csv"
KEY_OPTS="-i $SSH_KEY $SSH_OPTS"

echo "============================================================"
echo " [Phase A] Starting isolated test :: SERVICE S1 (VideoService)"
echo " Profile: BASELINE (No Mesh / No mTLS) | HVY (ffmpeg x264)"
echo " Target URL: $URL"
echo " Test Script: $JS_FILE | Asset: $VID_ASSET | rates(l/m/h)=$RATE_LOW/$RATE_MED/$RATE_HIGH rps"
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
# Real multipart POST of the asset to ensure the transcoder actually responds (not a generic 404).
curl -s -m 20 -X POST -F "file=@$COMMON/assets/$VID_ASSET;type=video/mp4" \
  -o /dev/null -w '   api -> http=%{http_code} t=%{time_total}s\n' "$URL/api/video/compress" || true

# --- sync script + video asset to lg ---
echo "[sync] copying $JS_FILE + assets/$VID_ASSET to lg:$LG_DIR ..."
ssh $KEY_OPTS root@"$LG_IP" "mkdir -p $LG_DIR/assets"
scp $KEY_OPTS "$HERE/$JS_FILE" root@"$LG_IP":"$LG_DIR/" >/dev/null
scp $KEY_OPTS "$COMMON/assets/$VID_ASSET" root@"$LG_IP":"$LG_DIR/assets/" >/dev/null

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

K6_ENV="BASE_URL=$URL VID_PATH=assets/$VID_ASSET RATE_LOW=$RATE_LOW RATE_MED=$RATE_MED RATE_HIGH=$RATE_HIGH"

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

  python3 "$COMMON/extract_timeseries.py" --prom "$PROM_LOCAL" --master "$CSV" \
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
