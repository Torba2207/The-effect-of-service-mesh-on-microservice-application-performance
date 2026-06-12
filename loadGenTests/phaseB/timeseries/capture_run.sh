#!/usr/bin/env bash
# Capture ONE Phase B run with full time-series (no kernel access):
#   - CPU/RAM over time   <- Prometheus query_range (resolution ~ scrape interval)
#   - Latency per second  <- k6 --out csv (true per-second)
# Produces CSVs + a PNG plot in results/ts/. Use this for detailed inspection of a
# representative run; use ../run_phaseB.sh for the full 150-run summary campaign.
#
# Usage:  ./capture_run.sh -c <label> -m <baseline|istio|linkerd> -t <mtls> -l <level> [opts]
# Example: ./capture_run.sh -c linkerd_mtls -m linkerd -t on -l high
set -euo pipefail

SSH_KEY="/home/torba/Documents/PG/Projects/.sshkeys/pgPB"
SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8"
LG_IP="10.29.20.130"; LG_DIR="/root/thesis-tests/phaseB"
CTX="projekt-badawchy-cluster"; PROM_SVC="cluster-monitor-kube-prome-prometheus"; PROM="http://localhost:9090"
HERE="$(cd "$(dirname "$0")" && pwd)"; PB="$(cd "$HERE/.." && pwd)"

NODE_IP="10.29.20.113"; URL=""; LEVEL="high"; WARMUP="30s"; STEADY="120s"; STEP="5"; INCLUDE_AI="false"
CONFIG=""; MESH=""; MTLS=""
while getopts "c:m:t:l:u:n:W:S:p:I" opt; do case "$opt" in
  c) CONFIG="$OPTARG";; m) MESH="$OPTARG";; t) MTLS="$OPTARG";; l) LEVEL="$OPTARG";;
  u) URL="$OPTARG";; n) NODE_IP="$OPTARG";; W) WARMUP="$OPTARG";; S) STEADY="$OPTARG";;
  p) STEP="$OPTARG";; I) INCLUDE_AI="true";; *) echo bad; exit 2;; esac; done
[ -z "$CONFIG" ] || [ -z "$MESH" ] || [ -z "$MTLS" ] && { echo "ERROR: -c -m -t required"; exit 2; }
[ -z "$URL" ] && URL="http://${NODE_IP}:30080"
KEY_OPTS="-i $SSH_KEY $SSH_OPTS"
OUT="$PB/results/ts"; mkdir -p "$OUT"
RUN="${CONFIG}_${LEVEL}_ts"
echo "== capture $RUN :: mesh=$MESH mtls=$MTLS url=$URL steady=$STEADY step=${STEP}s =="

# sync
ssh $KEY_OPTS root@"$LG_IP" "mkdir -p $LG_DIR/assets"
scp $KEY_OPTS "$PB/aggregate.js" root@"$LG_IP":"$LG_DIR/" >/dev/null
scp $KEY_OPTS "$PB/assets/filter_input_128.png" "$PB/assets/sample_360p_1s.mp4" root@"$LG_IP":"$LG_DIR/assets/" >/dev/null

# prometheus port-forward
kubectl --context "$CTX" -n monitoring port-forward "svc/$PROM_SVC" 9090:9090 >/dev/null 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null || true' EXIT; sleep 4

K6ENV="BASE_URL=$URL INCLUDE_AI=$INCLUDE_AI IMG_PATH=assets/filter_input_128.png VID_PATH=assets/sample_360p_1s.mp4"

echo "[warmup $WARMUP]"
ssh $KEY_OPTS root@"$LG_IP" "cd $LG_DIR && $K6ENV LEVEL=$LEVEL DURATION=$WARMUP K6_SUMMARY_OUT=/tmp/warm.json k6 run --quiet aggregate.js" >/dev/null 2>&1 || true

echo "[steady $STEADY + per-request csv]"
START=$(date -u +%s)
ssh $KEY_OPTS root@"$LG_IP" "cd $LG_DIR && $K6ENV LEVEL=$LEVEL DURATION=$STEADY K6_SUMMARY_OUT=/tmp/${RUN}.json k6 run --quiet --out csv=/tmp/${RUN}_k6.csv aggregate.js" > "$OUT/k6_${RUN}.log" 2>&1 || true
END=$(date -u +%s)

# retrieve k6 per-request csv (gzip on the wire)
ssh $KEY_OPTS root@"$LG_IP" "gzip -c /tmp/${RUN}_k6.csv" > "$OUT/${RUN}_k6.csv.gz" 2>/dev/null || true
ssh $KEY_OPTS root@"$LG_IP" "rm -f /tmp/${RUN}_k6.csv" 2>/dev/null || true

echo "[build time-series + plot]"
python3 "$HERE/timeseries.py" --prom "$PROM" --mesh "$MESH" --start "$START" --end "$END" \
  --step "$STEP" --k6csv "$OUT/${RUN}_k6.csv.gz" --run-id "$RUN" --outdir "$OUT" --plot

echo "== done -> $OUT/${RUN}_{cpu_ram,latency}.csv + ${RUN}.png =="
