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
# gateway: the ingress NodePort changes on every install (Istio ingress gateway, Consul API
#          Gateway); lg_campaign.sh -G resolves it.
# ai_mesh: the target can deploy with the AI host inside the mesh (make TARGET AI_MESH=1).
# ai_route_needs_mesh: the ingress reaches /api/Ai only with the AI host in the mesh (Consul's API
#          Gateway routes to catalog services only), so Phase B and Phase A "ai" need ai_mesh.
CONFIGS = {
    "baseline":       {"make": "baseline",       "mesh": "baseline", "mtls": "na"},
    "linkerd_mtls":   {"make": "linkerd",        "mesh": "linkerd",  "mtls": "on",  "ai_mesh": True},
    "linkerd_nomtls": {"make": "linkerd-nomtls", "mesh": "linkerd",  "mtls": "off", "ai_mesh": True},
    "istio_mtls":     {"make": "istio-mtls",     "mesh": "istio",    "mtls": "on",  "gateway": True, "ai_mesh": True},
    "istio_nomtls":   {"make": "istio-nomtls",   "mesh": "istio",    "mtls": "off", "gateway": True, "ai_mesh": True},
    # C-S: mTLS is always on in Consul, there is no C-P variant.
    "consul_mtls":    {"make": "consul",         "mesh": "consul",   "mtls": "on",  "gateway": True, "ai_mesh": True,
                       "ai_route_needs_mesh": True},
}

# Phase A scenarios that call the AI host. With the AI host in the mesh their label carries this
# suffix (the runner adds it to its default label; common/ai_state.sh refuses a mismatch).
AI_SCENARIOS = {"ai", "permutation_ai", "digital_ai"}
AI_MESH_SUFFIX = "_aimesh"

# Phase A scenario keys (loadGenTests/phaseA/phaseA_Data.sh) and their default -R rates
# (DEFAULT_RATES there; keep the two in sync).
SCENARIOS = {
    "digital": "60 120 180", "fibonacci": "50 100 150", "integration": "200 400 800",
    "permutation": "100 200 300",
    "video": "6 12 18", "ai": "3 6 12",
    "differential": "200 400 800",
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
        "ai_mesh_configs": [c for c, v in CONFIGS.items() if v.get("ai_mesh")],
        "ai_scenarios": sorted(AI_SCENARIOS),
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
    # With deploy: make TARGET AI_MESH=1 (lg_campaign.sh -A). Without: only the labels, for a
    # cluster that was already deployed that way.
    ai_mesh = bool(params.get("ai_mesh", False))
    if ai_mesh and not cfg.get("ai_mesh"):
        raise BadRequest(f"the AI host can join the mesh only for: {', '.join(c for c, v in CONFIGS.items() if v.get('ai_mesh'))}")

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
             "label": label, "ai_mesh": ai_mesh}

    if phase == "A":
        scenario = params.get("scenario")
        if scenario not in SCENARIOS:
            raise BadRequest("scenario: choose a Phase A scenario")
        if scenario == "ai" and cfg.get("ai_route_needs_mesh") and not ai_mesh:
            raise BadRequest(f"scenario ai under {config} needs the AI host in the mesh: without it the gateway has no /api/Ai route")
        args += ["-s", scenario, "-m", cfg["mesh"], "-t", cfg["mtls"]]
        if label:
            if ai_mesh and scenario in AI_SCENARIOS and not label.endswith(AI_MESH_SUFFIX):
                raise BadRequest(f"label must end in {AI_MESH_SUFFIX} for an AI scenario with the AI host in the mesh")
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
        shown = label or config + (AI_MESH_SUFFIX if ai_mesh and scenario in AI_SCENARIOS else "")
        title = f"A {scenario} · {shown}"
    else:
        exclude_ai = bool(params.get("exclude_ai", False))
        if cfg.get("ai_route_needs_mesh") and not ai_mesh and not exclude_ai:
            raise BadRequest(f"Phase B under {config} needs the AI host in the mesh: without it the gateway has no /api/Ai route for ai_generate")
        with_ai_mesh = ai_mesh and not exclude_ai
        if label and with_ai_mesh and not label.endswith(AI_MESH_SUFFIX):
            raise BadRequest(f"label must end in {AI_MESH_SUFFIX} with the AI host in the mesh")
        label_b = label or config + (AI_MESH_SUFFIX if with_ai_mesh else "")
        args += ["-c", label_b, "-m", cfg["mesh"], "-t", cfg["mtls"]]
        if exclude_ai:
            args.append("-X")
        clean["exclude_ai"] = exclude_ai
        title = f"B · {label_b}" + (" · no AI (debug)" if exclude_ai else "")

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
        if ai_mesh:
            wrapper.append("-A")
            title += " (AI in mesh)"
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
