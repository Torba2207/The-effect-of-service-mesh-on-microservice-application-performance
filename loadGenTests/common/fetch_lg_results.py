#!/usr/bin/env python3
"""Fetch campaign results produced on lg and merge them into this repository.

Campaigns started on lg write to /root/thesis-results (same layout as loadGenTests/:
phaseA/<ServiceDir>/results, phaseB/results), outside the git clone. This script, run on the
workstation:

  1. refuses to run while a Phase A/B runner is active on lg (files may be half written);
  2. copies /root/thesis-results to a local staging directory;
  3. merges it into loadGenTests/:
       *.csv          rows not yet present are appended (headers must match), so rows that
                      are already in the repository are never duplicated;
       other files    (k6 summaries and logs) are copied, replacing a file of the same name,
                      as a re-run on the workstation would;
  4. moves the fetched files on lg to /root/thesis-results-fetched/<timestamp>/, so the next
     fetch only brings new data and rows deleted here are not brought back.

Usage: fetch_lg_results.py [--dry-run] [--keep]
  --dry-run   show what would be merged, change nothing (here or on lg)
  --keep      merge, but leave the files on lg in place
"""

import argparse
import datetime
import os
import shutil
import subprocess
import sys
import tempfile

LG = "root@10.29.20.130"
REMOTE_RESULTS = "/root/thesis-results"
REMOTE_ARCHIVE = "/root/thesis-results-fetched"

HERE = os.path.dirname(os.path.abspath(__file__))
LOADGEN = os.path.dirname(HERE)
REPO_ROOT = os.path.dirname(LOADGEN)


def ssh_key():
    key = os.environ.get("SSH_PRIVATE_KEY")
    if not key:
        with open(os.path.join(REPO_ROOT, ".env")) as f:
            for line in f:
                if line.startswith("SSH_PRIVATE_KEY="):
                    key = line.split("=", 1)[1].strip().strip("'\"")
    if not key or not os.path.isfile(key):
        sys.exit("ERROR: SSH key not found (SSH_PRIVATE_KEY in the environment or .env)")
    return key


def ssh_opts(key):
    return ["-i", key, "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
            "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR"]


def merge_csv(src, dst):
    """Rows of src missing from dst (a list), or -1 when dst does not exist yet.
    Rows are compared as whole lines; the master and timeseries CSVs have no multi-line fields."""
    with open(src, newline="") as f:
        src_lines = f.read().splitlines()
    if not src_lines:
        return 0
    if not os.path.exists(dst):
        return -1  # caller copies the whole file
    with open(dst, newline="") as f:
        dst_lines = f.read().splitlines()
    if dst_lines and dst_lines[0] != src_lines[0]:
        raise ValueError(f"header differs: {dst}")
    present = set(dst_lines[1:])
    new = [line for line in src_lines[1:] if line not in present]
    return new


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--keep", action="store_true")
    args = ap.parse_args()

    opts = ssh_opts(ssh_key())

    # The [AB] bracket keeps pgrep from matching its own command line.
    busy = subprocess.run(["ssh", *opts, LG, "pgrep -af 'run_phase[AB]'"],
                          capture_output=True, text=True)
    if busy.returncode == 0 and busy.stdout.strip():
        sys.exit("ERROR: a campaign is running on lg, fetch after it finishes:\n" + busy.stdout)

    exists = subprocess.run(["ssh", *opts, LG, f"test -d {REMOTE_RESULTS}"])
    if exists.returncode != 0:
        sys.exit(f"Nothing to fetch: {REMOTE_RESULTS} does not exist on lg (run make lg-bootstrap).")

    staging = tempfile.mkdtemp(prefix="lg-results-")
    try:
        rsync_ssh = "ssh " + " ".join(opts)
        r = subprocess.run(["rsync", "-a", "-e", rsync_ssh, f"{LG}:{REMOTE_RESULTS}/", staging + "/"])
        if r.returncode != 0:
            sys.exit("ERROR: rsync from lg failed")

        fetched = []
        for root, _, files in os.walk(staging):
            for name in sorted(files):
                fetched.append(os.path.relpath(os.path.join(root, name), staging))
        if not fetched:
            print("Nothing new on lg.")
            return

        # Plan every file first, so a header mismatch aborts before anything is written.
        plan = []
        for rel in fetched:
            src = os.path.join(staging, rel)
            dst = os.path.join(LOADGEN, rel)
            if rel.endswith(".csv"):
                new = merge_csv(src, dst)
                if new == -1:
                    plan.append(("copy", rel, src, dst, None))
                elif new:
                    plan.append(("append", rel, src, dst, new))
                else:
                    plan.append(("same", rel, src, dst, None))
            else:
                plan.append(("copy", rel, src, dst, None))

        for action, rel, src, dst, new in plan:
            if action == "append":
                print(f"  + {len(new):4d} rows  {rel}")
            elif action == "copy" and rel.endswith(".csv"):
                print(f"  new file    {rel}")
            elif action == "same":
                print(f"  no new rows {rel}")
        others = sum(1 for p in plan if p[0] == "copy" and not p[1].endswith(".csv"))
        print(f"  {others} k6 summary/log files")

        if args.dry_run:
            print("Dry run: nothing changed.")
            return

        for action, rel, src, dst, new in plan:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if action == "copy":
                shutil.copy2(src, dst)
            elif action == "append":
                with open(dst, "rb") as f:
                    f.seek(-1, os.SEEK_END)
                    missing_newline = f.read(1) != b"\n"
                with open(dst, "a", newline="") as f:
                    if missing_newline:
                        f.write("\n")
                    for line in new:
                        f.write(line + "\n")
        print(f"Merged into {LOADGEN}")

        if not args.keep:
            stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
            target = f"{REMOTE_ARCHIVE}/{stamp}"
            mv = (f"mkdir -p {target} && cd {REMOTE_RESULTS} && "
                  f"find . -mindepth 1 -maxdepth 1 -exec mv -t {target} {{}} +")
            r = subprocess.run(["ssh", *opts, LG, mv])
            if r.returncode != 0:
                sys.exit(f"ERROR: merged, but could not archive the files on lg ({target})")
            print(f"Archived on lg: {target}")
    finally:
        shutil.rmtree(staging, ignore_errors=True)


if __name__ == "__main__":
    main()
