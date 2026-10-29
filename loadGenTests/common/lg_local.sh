# Sourced by run_phaseA_Core.sh and run_phaseB.sh after LG_IP and LOADGEN_DIR are set.
#
# The runners work in two modes:
#   - on a workstation: k6 runs on lg over SSH, results land in this repository;
#   - on lg itself (campaign started there, e.g. in tmux): k6 runs locally, no SSH key is
#     needed, and results land OUTSIDE the clone, in /root/thesis-results, so the clone stays
#     clean for `git pull`. fetch_lg_results.sh on the workstation merges them into the repo.
#
# LG_LOCAL=1|0 forces the mode (default: detected from this host's addresses).
# RESULTS_ROOT overrides where results go; it mirrors the loadGenTests/ layout
# (phaseA/<ServiceDir>/results, phaseB/results).

if [ -z "${LG_LOCAL:-}" ]; then
  if hostname -I 2>/dev/null | tr ' ' '\n' | grep -qx "$LG_IP"; then LG_LOCAL=1; else LG_LOCAL=0; fi
fi

if [ "$LG_LOCAL" = 1 ]; then
  RESULTS_ROOT="${RESULTS_ROOT:-/root/thesis-results}"
else
  RESULTS_ROOT="${RESULTS_ROOT:-$LOADGEN_DIR}"
fi

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
