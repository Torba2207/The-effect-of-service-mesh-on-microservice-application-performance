// Phase A — chained load for DifferentialEquationsService → IntegrationService (differential_solve), S2-int.
// Endpoint: POST /api/differential/solve. The meshed differential service always calls the meshed
// integration service in-cluster (http://integration-service/), so under a mesh BOTH hops carry
// mTLS: ingress→differential and differential→integration. This is the project's sidecar-to-sidecar
// encryption benchmark.
//
// Work unit: `x^2` contains no `y`, so DifferentialCalculator makes EXACTLY ONE downstream
// antiderivative call per request (a `y`-bearing function would loop `steps` times — that is S2-amp).
// At R req/s this scenario therefore also puts R req/s on the integration service.
// Env:
//   BASE_URL           required, e.g. http://10.29.20.113:30080
//   LEVEL              low | med | high                                  (default low)
//   DURATION           steady/warmup length                              (default 120s)
//   RATE_LOW/MED/HIGH  per-level arrival rate, req/s                     (default 25 / 50 / 100)
//   K6_SUMMARY_OUT     per-scenario JSON out path                        (default phaseA_summary.json)

import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const BASE = __ENV.BASE_URL;
const LEVEL = (__ENV.LEVEL || 'low').toLowerCase();
const DURATION = __ENV.DURATION || '120s';
const SUMMARY_OUT = __ENV.K6_SUMMARY_OUT || 'phaseA_summary.json';

if (!BASE) { throw new Error('BASE_URL env is required'); }

// STD class rates, identical to Phase B's differential_solve and to the S1 STD scenarios.
const RATES = {
  low:  parseInt(__ENV.RATE_LOW  || '25', 10),
  med:  parseInt(__ENV.RATE_MED  || '50', 10),
  high: parseInt(__ENV.RATE_HIGH || '100', 10),
};
const RATE = RATES[LEVEL];
const S = 'differential_solve';

const lat = new Trend('lat_' + S, true);
const okr = new Rate('ok_' + S);

// Same payload as Phase B's aggregate.js and docs/test-scenario.typ §3 (S2-int work unit).
const BODY = JSON.stringify({ function: 'x^2', initialConditionY: 1, steps: 5 });
const JSON_HEADERS = { headers: { 'Content-Type': 'application/json' } };

export const options = {
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    differential_solve: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: 20,
      maxVUs: 120,
      gracefulStop: '15s',
      exec: 'differential_solve',
      tags: { scenario: S },
    },
  },
};

export function differential_solve() {
  const res = http.post(BASE + '/api/differential/solve', BODY, JSON_HEADERS);
  const ok = res.status === 200;
  okr.add(ok);
  lat.add(res.timings.duration);
  check(res, { 'status is 200': () => ok });
}

function val(o, k) { return (o && o[k] !== undefined && o[k] !== null) ? o[k] : null; }

export function handleSummary(data) {
  const t = (data.metrics['lat_' + S] || {}).values || {};
  const r = (data.metrics['ok_' + S] || {}).values || {};
  const fails = r.fails || 0;
  const reqs = (r.passes || 0) + fails;

  const out = { level: LEVEL, duration: DURATION, include_ai: false, scenarios: {} };
  out.scenarios[S] = {
    rps_target: RATE,
    reqs: reqs,
    fail_rate: reqs ? fails / reqs : null,
    lat_avg_ms: val(t, 'avg'),
    lat_p50_ms: val(t, 'med'),
    lat_p90_ms: val(t, 'p(90)'),
    lat_p95_ms: val(t, 'p(95)'),
    lat_p99_ms: val(t, 'p(99)'),
    lat_max_ms: val(t, 'max'),
  };

  const ret = {};
  ret[SUMMARY_OUT] = JSON.stringify(out, null, 2);
  ret['stdout'] = 'Phase A [' + LEVEL + '] DifferentialEquationsService → Integration @ ' + RATE + ' req/s -> ' + SUMMARY_OUT + '\n';
  return ret;
}
