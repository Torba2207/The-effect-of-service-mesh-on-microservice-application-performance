"""Turns a request from the page into one shell command for run.sh.

The page only sends parameters; every value is checked against what the runners accept and the
command is assembled here, quoted with shlex. Defaults mirror the runners' own defaults, and a
flag is only passed when its value differs from them, so the command (and the commit message
lg_campaign.sh writes from it) reads like one typed by hand.
"""
import re
import shlex

LG_CAMPAIGN = "loadGenTests/common/lg_campaign.sh"
RUNNER = {
    "A": "loadGenTests/phaseA/run_phaseA_Core.sh",
    "B": "loadGenTests/phaseB/run_phaseB.sh",
}

# Configuration -> deploy target in deployments/Makefile and the runner's -m/-t labels.
# istio_*: the Envoy gateway NodePort changes on every install, lg_campaign.sh -G resolves it.
CONFIGS = {
    "baseline":       {"make": "baseline",       "mesh": "baseline", "mtls": "na"},
    "linkerd_mtls":   {"make": "linkerd",        "mesh": "linkerd",  "mtls": "on"},
    "linkerd_nomtls": {"make": "linkerd-nomtls", "mesh": "linkerd",  "mtls": "off"},
    "istio_mtls":     {"make": "istio-mtls",     "mesh": "istio",    "mtls": "on",  "gateway": True},
    "istio_nomtls":   {"make": "istio-nomtls",   "mesh": "istio",    "mtls": "off", "gateway": True},
}

# Phase A scenario keys (loadGenTests/phaseA/phaseA_Data.sh) and the default -R rates of those
# whose k6 script reads RATE_LOW/MED/HIGH.
SCENARIOS = {
    "digital": None, "fibonacci": None, "integration": None, "permutation": None,
    "video": "6 12 18", "ai": "3 6 12",
    "differential": "25 50 100",
    "permutation_ai": "3 6 12", "digital_ai": "3 6 12",
}

LEVELS = ["low", "med", "high"]
DEFAULTS = {"levels": LEVELS, "reps": 10, "warmup": "30s", "steady": "120s", "cooldown": 30,
            "fib_n": 20000}

SELFTEST_SECONDS = 60
DEPLOY_ESTIMATE_S = 600           # a make target tears down, cleans and installs: ~5-10 min

DURATION_RE = re.compile(r"([1-9][0-9]*)(s|m)")
LABEL_RE = re.compile(r"[A-Za-z0-9_-]+")


class BadRequest(ValueError):
    pass


def options():
    """What the page builds its form from."""
    return {
        "configs": list(CONFIGS),
        "scenarios": {k: {"rates": v} for k, v in SCENARIOS.items()},
        "levels": LEVELS,
        "defaults": DEFAULTS,
    }


def _int(params, key, lo, hi):
    v = params.get(key, DEFAULTS[key])
    if isinstance(v, str) and v.strip().isdigit():
        v = int(v)
    if not isinstance(v, int) or isinstance(v, bool) or not lo <= v <= hi:
        raise BadRequest(f"{key} must be an integer between {lo} and {hi}")
    return v


def _duration(params, key):
    v = str(params.get(key, DEFAULTS[key])).strip()
    m = DURATION_RE.fullmatch(v)
    if not m:
        raise BadRequest(f"{key} must be a duration with a unit, e.g. 30s or 2m (got {v!r})")
    return v, int(m[1]) * (60 if m[2] == "m" else 1)


def build(params):
    """Validate the request. Returns (command, title, estimate in seconds, clean params)."""
    if not isinstance(params, dict):
        raise BadRequest("the body must be a JSON object")
    phase = params.get("phase")

    if phase == "selftest":
        cmd = (f'for i in $(seq 1 {SELFTEST_SECONDS // 2}); do echo "selftest $i/{SELFTEST_SECONDS // 2}"; '
               'sleep 2; done')
        return cmd, "self-test (no cluster access)", SELFTEST_SECONDS, {"phase": phase}

    if phase not in RUNNER:
        raise BadRequest("phase must be A, B or selftest")
    config = params.get("config")
    if config not in CONFIGS:
        raise BadRequest(f"config must be one of {', '.join(CONFIGS)}")
    cfg = CONFIGS[config]
    deploy = bool(params.get("deploy", True))
    push = bool(params.get("push", True))

    levels = params.get("levels", LEVELS)
    if (not isinstance(levels, list) or not levels or len(set(levels)) != len(levels)
            or any(lv not in LEVELS for lv in levels)):
        raise BadRequest("levels: choose one or more of low, med, high, each once")
    levels = [lv for lv in LEVELS if lv in levels]
    reps = _int(params, "reps", 1, 100)
    warmup, warmup_s = _duration(params, "warmup")
    steady, steady_s = _duration(params, "steady")
    cooldown = _int(params, "cooldown", 0, 3600)
    fib_n = _int(params, "fib_n", 1, 10_000_000)
    label = str(params.get("label") or "").strip()
    if label and not LABEL_RE.fullmatch(label):
        raise BadRequest("label may contain letters, digits, '_' and '-' only")

    args = [RUNNER[phase]]
    clean = {"phase": phase, "config": config, "deploy": deploy, "push": push, "levels": levels,
             "reps": reps, "warmup": warmup, "steady": steady, "cooldown": cooldown, "fib_n": fib_n,
             "label": label}

    if phase == "A":
        scenario = params.get("scenario")
        if scenario not in SCENARIOS:
            raise BadRequest("scenario: choose a Phase A scenario")
        args += ["-s", scenario, "-m", cfg["mesh"], "-t", cfg["mtls"]]
        if label:
            args += ["-c", label]
        rates = str(params.get("rates") or "").strip()
        if rates:
            if SCENARIOS[scenario] is None:
                raise BadRequest(f"rates are fixed in the k6 script of {scenario}")
            parts = rates.split()
            if len(parts) != 3 or not all(p.isdigit() and int(p) > 0 for p in parts):
                raise BadRequest('rates: three positive integers "LOW MED HIGH"')
            rates = " ".join(parts)
            if rates != SCENARIOS[scenario]:
                args += ["-R", rates]
        clean.update(scenario=scenario, rates=rates)
        title = f"A {scenario} · {label or config}"
    else:
        args += ["-c", label or config, "-m", cfg["mesh"], "-t", cfg["mtls"]]
        exclude_ai = bool(params.get("exclude_ai", False))
        if exclude_ai:
            args.append("-X")
        clean["exclude_ai"] = exclude_ai
        title = f"B · {label or config}" + (" · no AI (debug)" if exclude_ai else "")

    if fib_n != DEFAULTS["fib_n"]:
        args += ["-N", str(fib_n)]
    if levels != LEVELS:
        args += ["-l", " ".join(levels)]
    if reps != DEFAULTS["reps"]:
        args += ["-r", str(reps)]
    if warmup != DEFAULTS["warmup"]:
        args += ["-W", warmup]
    if steady != DEFAULTS["steady"]:
        args += ["-S", steady]
    if cooldown != DEFAULTS["cooldown"]:
        args += ["-C", str(cooldown)]

    wrapper = [LG_CAMPAIGN]
    if deploy:
        wrapper += ["-d", cfg["make"]]
        title += " · deploy"
    if cfg.get("gateway"):
        wrapper.append("-G")
    if not push:
        wrapper.append("-n")
        title += " · no push"

    command = shlex.join(wrapper + ["--"] + args)
    estimate = len(levels) * reps * (warmup_s + steady_s + cooldown)
    if deploy:
        estimate += DEPLOY_ESTIMATE_S
    return command, title, estimate, clean
