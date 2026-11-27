#!/usr/bin/env bash
# Runs one campaign on lg on a git branch and publishes its results there:
#   1. takes the campaign lock, so only one campaign runs on lg at a time;
#   2. checks that the clone is on the studies branch and has no local changes;
#   3. syncs it with origin (fast-forward only), so the campaign runs the latest pushed code and
#      appends to the latest pushed CSVs;
#   4. optionally deploys the configuration (-d) and resolves the Istio gateway (-G);
#   5. runs the given runner, which writes its results into the clone (loadGenTests/.../results);
#   6. commits the new results and pushes the branch.
#
# Run on lg, e.g. in tmux, or queue it from the scheduler page (loadGenTests/lg_ui):
#   cd /root/thesis
#   loadGenTests/common/lg_campaign.sh -d linkerd -- loadGenTests/phaseA/run_phaseA_Core.sh -s fibonacci -m linkerd -t on
#   loadGenTests/common/lg_campaign.sh -d istio-mtls -G -- loadGenTests/phaseB/run_phaseB.sh -c istio_mtls -m istio -t on
#   loadGenTests/common/lg_campaign.sh -d istio-mtls -A -G -- loadGenTests/phaseB/run_phaseB.sh -c istio_mtls_aimesh -m istio -t on
#   loadGenTests/common/lg_campaign.sh -- loadGenTests/phaseB/run_phaseB.sh -c baseline -m baseline -t na
#
# Options (before --):
#   -b BRANCH   branch the clone must be on       (default: studies_lg_based)
#   -n          commit, but do not push
#   -d TARGET   deploy first: make -C deployments TARGET (after the sync, under the lock); a failed
#               deploy stops here, before the runner
#   -A          with -d: deploy with the AI host inside the mesh (make TARGET AI_MESH=1). The runners
#               then require the _aimesh label suffix on AI runs (common/ai_state.sh)
#   -G          append -u http://<node>:<port> to the runner arguments, with the Istio ingress
#               gateway's NodePort (it changes on every Istio install); after -d if both are given
#
# The lock ($LG_CAMPAIGN_LOCK, default /run/lock/thesis-campaign.lock) is held for the whole run,
# deploy included; a second lg_campaign.sh refuses to start while it is held. A bare `make <config>`
# typed by hand does not take it - do not deploy by hand while a campaign is running.
#
# Checked before the campaign starts, so a 2 h run never ends in a failed push:
#   - git user.name / user.email are set on lg (git config --global ...);
#   - lg can push to origin (the bootstrap clones over anonymous https, which can only pull).
#
# Results are committed even when the runner exits non-zero (the exit code goes into the commit
# message). A campaign stopped with Ctrl-C is NOT committed: its results stay in the clone, and the
# next start refuses to run until they are committed or removed by hand. k6 *.log files are
# gitignored, so they stay on lg only, as on a workstation.
set -euo pipefail

LG_IP="10.29.20.130"
NODE_IP="10.29.20.113"            # the runners' default ingress node
CTX="projekt-badawchy-cluster"
LOCK="${LG_CAMPAIGN_LOCK:-/run/lock/thesis-campaign.lock}"
DEPLOY_TARGETS="baseline linkerd linkerd-nomtls istio-mtls istio-nomtls istio consul"
USAGE="usage: $0 [-b BRANCH] [-n] [-d TARGET [-A]] [-G] -- <runner> [runner args]"

die() { printf 'ERROR: %b\n' "$*" >&2; exit 1; }

main() {
  local branch="studies_lg_based" push=1 deploy="" gateway=0 ai_mesh=0 opt
  while getopts "b:nd:AG" opt; do
    case "$opt" in
      b) branch="$OPTARG" ;;
      n) push=0 ;;
      d) deploy="$OPTARG" ;;
      A) ai_mesh=1 ;;
      G) gateway=1 ;;
      *) echo "$USAGE"; exit 2 ;;
    esac
  done
  shift $((OPTIND - 1))
  [ "${1:-}" != "--" ] || shift
  [ $# -ge 1 ] || die "no runner given ($USAGE)"
  [ "$ai_mesh" = 0 ] || [ -n "$deploy" ] || die "-A needs -d TARGET (it changes how TARGET is deployed)"
  if [ -n "$deploy" ]; then
    case " $DEPLOY_TARGETS " in
      *" $deploy "*) ;;
      *) die "-d must be one of: $DEPLOY_TARGETS (got '$deploy')" ;;
    esac
  fi

  case " $(hostname -I 2>/dev/null) " in
    *" $LG_IP "*) ;;
    *) die "run this on lg ($LG_IP); on a workstation start the runner directly" ;;
  esac

  # fd 9 holds the lock until this script exits; every child below gets 9>&- so that nothing
  # left running in the background (a port-forward, say) keeps the lock after the campaign.
  exec 9>>"$LOCK" || die "cannot open the campaign lock $LOCK"
  flock -n 9 || die "another campaign is running on lg (lock $LOCK is held)"

  # The runner path may be relative to the current directory or to the repository root.
  local runner="$1"; shift
  if [ -f "$runner" ]; then
    runner="$(cd "$(dirname "$runner")" && pwd)/$(basename "$runner")"
  fi

  local repo
  repo="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
  cd "$repo"
  case "$runner" in /*) ;; *) runner="$repo/$runner" ;; esac
  [ -x "$runner" ] || die "runner not found or not executable: $runner"

  # --- preflight: branch, clean tree, identity, push access ---
  local current
  current="$(git symbolic-ref --quiet --short HEAD)" || die "the clone is in detached HEAD (git checkout $branch)"
  [ "$current" = "$branch" ] || die "the clone is on '$current', not '$branch' (git checkout $branch)"

  local dirty
  dirty="$(git status --porcelain)"
  [ -z "$dirty" ] || die "the clone has local changes; commit, stash or remove them first:\n$dirty"

  git config user.name >/dev/null && git config user.email >/dev/null ||
    die "no git identity on lg: git config --global user.name '...'; git config --global user.email '...'"

  export GIT_TERMINAL_PROMPT=0   # fail instead of waiting for a password in tmux
  echo "[git] syncing $branch with origin ..."
  git fetch -q origin "$branch" || die "git fetch failed (does origin/$branch exist?)"
  git merge -q --ff-only "origin/$branch" ||
    die "local $branch has diverged from origin/$branch; resolve it by hand"

  if [ "$push" = 1 ]; then
    git push --dry-run -q origin "$branch" 9>&- >/dev/null 2>&1 ||
      die "lg cannot push to origin ($(git remote get-url origin)); give it write access or use -n"
  fi
  echo "[git] on $branch at $(git rev-parse --short HEAD)"

  # --- deploy ---
  local deployed=""
  if [ -n "$deploy" ]; then
    local make_args=("$deploy")
    [ "$ai_mesh" = 1 ] && make_args+=(AI_MESH=1)
    echo "[deploy] make -C deployments ${make_args[*]} ($(date -u +%H:%M:%SZ)) ..."
    make -C "$repo/deployments" "${make_args[@]}" 9>&- ||
      die "deployment failed (make ${make_args[*]}); the campaign was not started"
    deployed="Deployed with \`make ${make_args[*]}\` first. "
    echo "[deploy] done ($(date -u +%H:%M:%SZ))"
  fi
  if [ "$gateway" = 1 ]; then
    local gwport
    gwport="$(kubectl --context "$CTX" -n istio-system get svc istio-ingressgateway \
      -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 9>&- || true)"
    [ -n "$gwport" ] || die "-G: cannot read the Istio ingress gateway NodePort (is Istio deployed?)"
    set -- "$@" -u "http://$NODE_IP:$gwport"
    echo "[deploy] Istio gateway: http://$NODE_IP:$gwport"
  fi

  # --- campaign ---
  # RESULTS_ROOT is set explicitly so a value exported in the shell cannot send the results
  # outside the clone, where they would not be committed.
  local start rc
  start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[campaign] ${runner#"$repo"/} $*"
  set +e
  RESULTS_ROOT="$repo/loadGenTests" LG_LOCAL=1 "$runner" "$@" 9>&-
  rc=$?
  set -e
  echo "[campaign] runner exit code: $rc"

  # --- commit + push ---
  git add -A -- ':(glob)loadGenTests/**/results/**'
  local other
  other="$(git status --porcelain --untracked-files=all | grep -v '^[MADR] ' || true)"
  [ -z "$other" ] || printf '[git] WARNING: changes outside results/ are left uncommitted:\n%s\n' "$other"

  if git diff --cached --quiet; then
    echo "[git] no new results to commit"
  else
    git commit -q -m "studies(lg): ${runner#"$repo"/} $*" \
      -m "${deployed}Run on lg from $start to $(date -u +%Y-%m-%dT%H:%M:%SZ), runner exit code $rc."
    echo "[git] committed $(git rev-parse --short HEAD)"
  fi

  if [ "$push" = 1 ] && [ -n "$(git rev-list "origin/$branch..HEAD")" ]; then
    if ! git push -q origin "$branch"; then
      echo "[git] push rejected, rebasing onto origin/$branch ..."
      if ! { git pull -q --rebase origin "$branch" && git push -q origin "$branch"; }; then
        git rebase --abort 2>/dev/null || true
        die "push failed; the results are committed locally on $branch, push them by hand"
      fi
    fi
    echo "[git] pushed $branch"
  fi
  return "$rc"
}

# Everything runs inside main: bash reads a script while executing it, and the sync above may
# replace this very file. A function is parsed whole before it starts.
main "$@"; exit $?
