#!/usr/bin/env bash
# Runs one campaign on lg on a git branch and publishes its results there:
#   1. checks that the clone is on the studies branch and has no local changes;
#   2. syncs it with origin (fast-forward only), so the campaign runs the latest pushed code and
#      appends to the latest pushed CSVs;
#   3. runs the given runner, which writes its results into the clone (loadGenTests/.../results);
#   4. commits the new results and pushes the branch.
#
# Run on lg, e.g. in tmux:
#   cd /root/thesis
#   loadGenTests/common/lg_campaign.sh -- loadGenTests/phaseA/run_phaseA_Core.sh -s fibonacci -m linkerd -t on
#   loadGenTests/common/lg_campaign.sh -- loadGenTests/phaseB/run_phaseB.sh -c baseline -m baseline -t na
#
# Options (before --):
#   -b BRANCH   branch the clone must be on       (default: studies_lg_based)
#   -n          commit, but do not push
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

die() { printf 'ERROR: %b\n' "$*" >&2; exit 1; }

main() {
  local branch="studies_lg_based" push=1 opt
  while getopts "b:n" opt; do
    case "$opt" in
      b) branch="$OPTARG" ;;
      n) push=0 ;;
      *) echo "usage: $0 [-b BRANCH] [-n] -- <runner> [runner args]"; exit 2 ;;
    esac
  done
  shift $((OPTIND - 1))
  [ "${1:-}" != "--" ] || shift
  [ $# -ge 1 ] || die "no runner given (usage: $0 [-b BRANCH] [-n] -- <runner> [runner args])"

  case " $(hostname -I 2>/dev/null) " in
    *" $LG_IP "*) ;;
    *) die "run this on lg ($LG_IP); on a workstation start the runner directly" ;;
  esac

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
    git push --dry-run -q origin "$branch" >/dev/null 2>&1 ||
      die "lg cannot push to origin ($(git remote get-url origin)); give it write access or use -n"
  fi
  echo "[git] on $branch at $(git rev-parse --short HEAD)"

  # --- campaign ---
  # RESULTS_ROOT is set explicitly so a value exported in the shell cannot send the results
  # outside the clone, where they would not be committed.
  local start rc
  start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[campaign] ${runner#"$repo"/} $*"
  set +e
  RESULTS_ROOT="$repo/loadGenTests" LG_LOCAL=1 "$runner" "$@"
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
      -m "Run on lg from $start to $(date -u +%Y-%m-%dT%H:%M:%SZ), runner exit code $rc."
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
