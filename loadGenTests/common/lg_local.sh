# Sourced by the runners that drive k6 on lg (phaseA/run_phaseA_Core.sh, phaseB/run_phaseB.sh,
# phaseB/timeseries/capture_run.sh) after LG_IP and LOADGEN_DIR are set.
#
# The runners work in two modes:
#   - on a workstation: k6 runs on lg over SSH, results land in this repository;
#   - on lg itself (campaign started there, e.g. in tmux): k6 runs locally and no SSH key is
#     needed. Results land in the clone on lg; lg_campaign.sh commits and pushes them.
#
# LG_LOCAL=1|0 forces the mode (default: detected from this host's addresses).
# RESULTS_ROOT overrides where results go (default: this repository's loadGenTests/); it mirrors
# the loadGenTests/ layout (phaseA/<ServiceDir>/results, phaseB/results).

# No pipeline here: the runners use pipefail, and `... | grep -q` can then fail on SIGPIPE.
if [ -z "${LG_LOCAL:-}" ]; then
  case " $(hostname -I 2>/dev/null) " in
    *" $LG_IP "*) LG_LOCAL=1 ;;
    *)            LG_LOCAL=0 ;;
  esac
fi
case "$LG_LOCAL" in
  0|1) ;;
  *) echo "ERROR: LG_LOCAL must be 1 or 0 (got '$LG_LOCAL')"; exit 2 ;;
esac

RESULTS_ROOT="${RESULTS_ROOT:-$LOADGEN_DIR}"
# The runners cd around; a relative RESULTS_ROOT would follow them.
case "$RESULTS_ROOT" in
  /*) ;;
  *) RESULTS_ROOT="$PWD/$RESULTS_ROOT" ;;
esac

# Run a shell command on lg (locally when already there).
lg_sh() {
  if [ "$LG_LOCAL" = 1 ]; then
    bash -c "$1"
  else
    ssh $KEY_OPTS root@"$LG_IP" "$1"
  fi
}

# Copy files into a directory on lg: lg_put <dest-dir> <file>...
lg_put() {
  local dest="$1"; shift
  if [ "$LG_LOCAL" = 1 ]; then
    cp "$@" "$dest/"
  else
    scp $KEY_OPTS "$@" root@"$LG_IP":"$dest/" >/dev/null
  fi
}
