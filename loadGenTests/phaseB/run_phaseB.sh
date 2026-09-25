#!/usr/bin/env bash
# Phase B orchestrator — runs the aggregate full-system load for ONE configuration.
# Runs from the workstation: drives k6 on the load generator (lg), pulls CPU/RAM
# from Prometheus (via port-forward), and appends rows to results/master.csv.
#
# The active configuration must already be deployed before calling this (deployments/:
# make baseline | linkerd | linkerd-nomtls | istio-nomtls, or make istio + the STRICT policy).
# One invocation = 3 levels x N reps. Every run drives all nine scenarios, AI included.
#
# Usage:
#   ./run_phaseB.sh -c <label> -m <baseline|istio|linkerd> -t <mtls> [opts]
# Example:
#   ./run_phaseB.sh -c linkerd_mtls -m linkerd -t on
#   ./run_phaseB.sh -c baseline -m baseline -t na -u http://10.29.20.113:30080
#
# Options:
#   -c LABEL     config label for the CSV (e.g. linkerd_mtls, istio_nomtls)   [required]
#   -m MESH      baseline | istio | linkerd                                   [required]
#   -t MTLS      mTLS state label: on | off | na                              [required]
#   -u URL       TARGET_URL base (default http://<node>:30080; istio: resolve gateway)
#   -n NODE_IP   worker node IP for NodePort ingress     (default 10.29.20.113)
#   -l "LEVELS"  space-separated levels                  (default "low med high")
#   -r REPS      repetitions per level                   (default 10)
#   -W WARMUP    warm-up duration                        (default 30s)
#   -S STEADY    steady (measured) duration              (default 120s)
#   -C COOLDOWN  cooldown seconds between runs           (default 30)
#   -N N         Fibonacci work unit n                   (default 20000, same as Phase A)
#   -X           exclude the three AI scenarios - debugging only, NOT a valid Phase B run
#                (AI is included by default at 1/2/3 req/s per scenario)
set -euo pipefail

# --- fixed environment ---
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

# SSH key: read from $SSH_PRIVATE_KEY if set, else from the SSH_PRIVATE_KEY entry in
# the repo-root .env (override the file with ENV_FILE=/path/to/.env).
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"
SSH_KEY="${SSH_PRIVATE_KEY:-}"
if [ -z "$SSH_KEY" ]; then
  [ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE not found and \$SSH_PRIVATE_KEY unset"; exit 1; }
  SSH_KEY="$(sed -n 's/^SSH_PRIVATE_KEY=//p' "$ENV_FILE" | head -1 | sed 's/^["'\'']//;s/["'\'']$//')"
fi
[ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ] || { echo "ERROR: SSH key not found (SSH_PRIVATE_KEY='$SSH_KEY')"; exit 1; }

SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8"
LG_IP="10.29.20.130"
LG_DIR="/root/thesis-tests/phaseB"
CTX="projekt-badawchy-cluster"
PROM_SVC="cluster-monitor-kube-prome-prometheus"
PROM_LOCAL="http://localhost:9090"

# --- defaults ---
NODE_IP="10.29.20.113"; URL=""; LEVELS="low med high"; REPS=10
WARMUP="30s"; STEADY="120s"; COOLDOWN=30; INCLUDE_AI="true"; FIB_N=20000
CONFIG=""; MESH=""; MTLS=""

while getopts "c:m:t:u:n:l:r:W:S:C:N:X" opt; do
  case "$opt" in
    c) CONFIG="$OPTARG" ;; m) MESH="$OPTARG" ;; t) MTLS="$OPTARG" ;;
    u) URL="$OPTARG" ;; n) NODE_IP="$OPTARG" ;; l) LEVELS="$OPTARG" ;;
    r) REPS="$OPTARG" ;; W) WARMUP="$OPTARG" ;; S) STEADY="$OPTARG" ;;
    C) COOLDOWN="$OPTARG" ;; N) FIB_N="$OPTARG" ;; X) INCLUDE_AI="false" ;;
    *) echo "bad option"; exit 2 ;;
  esac
done
[ -z "$CONFIG" ] || [ -z "$MESH" ] || [ -z "$MTLS" ] && { echo "ERROR: -c -m -t are required"; exit 2; }
[ -z "$URL" ] && URL="http://${NODE_IP}:30080"
case "$FIB_N" in ''|*[!0-9]*) echo "ERROR: -N must be a positive integer (got '$FIB_N')"; exit 2 ;; esac
[ "$FIB_N" -ge 1 ] || { echo "ERROR: -N must be >= 1"; exit 2; }

RESULTS="$HERE/results"; mkdir -p "$RESULTS"
CSV="$RESULTS/master.csv"
KEY_OPTS="-i $SSH_KEY $SSH_OPTS"

echo "============================================================"
echo " Phase B :: config=$CONFIG mesh=$MESH mtls=$MTLS"
echo " URL=$URL  levels=[$LEVELS] reps=$REPS  warmup=$WARMUP steady=$STEADY cooldown=${COOLDOWN}s"
echo " AI=$INCLUDE_AI  fibonacci n=$FIB_N"
[ "$INCLUDE_AI" = "true" ] || echo " WARNING: -X given - AI scenarios excluded, this is NOT a valid Phase B run"
echo "============================================================"

# --- preflight ---
echo "[preflight] lg ssh..."
ssh $KEY_OPTS root@"$LG_IP" 'command -v k6 >/dev/null' || { echo "k6 missing on lg"; exit 1; }
echo "[preflight] kube context..."
kubectl --context "$CTX" get ns thesis-test >/dev/null || { echo "kube context unreachable"; exit 1; }
echo "[preflight] target URL..."
curl -s -m 8 -o /dev/null -w '  ingress -> http=%{http_code}\n' -X POST "$URL/api/permutation/generate" \
  -H 'Content-Type: application/json' -d '{"set":[1,2,3]}' || true
if [ "$INCLUDE_AI" = "true" ]; then
  echo "[preflight] AI host..."
  EP="$(kubectl --context "$CTX" -n thesis-test get endpoints ai-service -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
  [ -n "$EP" ] || { echo "ERROR: service thesis-test/ai-service has no endpoints (kubectl apply -f deployments/k8s/ai-service/ai-service-external.yaml)"; exit 1; }
  curl -s -m 10 -o /dev/null -w "  ai-service ($EP) via ingress -> http=%{http_code}\n" "$URL/api/Ai/health" || true
fi

# --- sync assets + script to lg ---
echo "[sync] copying aggregate.js + assets to lg:$LG_DIR ..."
ssh $KEY_OPTS root@"$LG_IP" "mkdir -p $LG_DIR/assets"
scp $KEY_OPTS "$HERE/aggregate.js" root@"$LG_IP":"$LG_DIR/" >/dev/null
scp $KEY_OPTS "$HERE/../common/assets/filter_input_128.png" "$HERE/../common/assets/sample_360p_1s.mp4" root@"$LG_IP":"$LG_DIR/assets/" >/dev/null

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

K6_ENV="BASE_URL=$URL INCLUDE_AI=$INCLUDE_AI FIB_N=$FIB_N IMG_PATH=assets/filter_input_128.png VID_PATH=assets/sample_360p_1s.mp4"

run_one() {
  local level="$1" rep="$2"
  local run_id="${CONFIG}_${level}_r${rep}"
  echo "---- $run_id ----"

  # warm-up (discarded)
  ssh $KEY_OPTS root@"$LG_IP" \
    "cd $LG_DIR && $K6_ENV LEVEL=$level DURATION=$WARMUP K6_SUMMARY_OUT=/tmp/warm.json k6 run --quiet aggregate.js" \
    >/dev/null 2>&1 || true

  # steady (measured)
  local start end
  start=$(date -u +%s)
  ssh $KEY_OPTS root@"$LG_IP" \
    "cd $LG_DIR && $K6_ENV LEVEL=$level DURATION=$STEADY K6_SUMMARY_OUT=/tmp/${run_id}.json k6 run --quiet aggregate.js" \
    > "$RESULTS/k6_${run_id}.log" 2>&1 || true
  end=$(date -u +%s)

  # retrieve per-scenario summary
  ssh $KEY_OPTS root@"$LG_IP" "cat /tmp/${run_id}.json" > "$RESULTS/k6_${run_id}.json" 2>/dev/null || echo '{"scenarios":{}}' > "$RESULTS/k6_${run_id}.json"

  sleep "$COOLDOWN"
  ensure_pf

  python3 "$HERE/../common/collect_metrics.py" \
    --prom "$PROM_LOCAL" --config "$CONFIG" --mesh "$MESH" --mtls "$MTLS" \
    --level "$level" --rep "$rep" --run-id "$run_id" \
    --start "$start" --end "$end" --summary "$RESULTS/k6_${run_id}.json" --csv "$CSV"

  # Extract this run's CPU/RAM time-series NOW, while it is still in Prometheus.
  # Prometheus retention here is only 1h (tmpfs), so end-of-campaign extraction would
  # already be too late for the first runs — it must be done per-run.
  python3 "$HERE/../common/extract_timeseries.py" --prom "$PROM_LOCAL" --master "$CSV" \
    --run-id "$run_id" --append --out "$RESULTS/timeseries_${CONFIG}.csv" --step 10 >/dev/null 2>&1 || true
}

for level in $LEVELS; do
  for rep in $(seq 1 "$REPS"); do
    run_one "$level" "$rep"
  done
done

echo "============================================================"
echo " DONE: $CONFIG -> $CSV  (+ results/timeseries_${CONFIG}.csv, extracted per-run)"
echo "============================================================"
