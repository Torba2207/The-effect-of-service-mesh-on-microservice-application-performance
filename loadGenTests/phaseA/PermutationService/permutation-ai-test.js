// Phase A — chained load for PermutationService → AI (permutation_from_ai), S2-ext.
// Endpoint: POST /api/permutation/generate-from-ai. The meshed permutation service asks the
// external, unmeshed AI host for a seeded set, then permutes it locally. Only the
// ingress→permutation hop is in the mesh; the permutation→AI egress leg is plaintext in every
// configuration.
// Env:
//   BASE_URL           required, e.g. http://10.29.20.113:30080
//   LEVEL              low | med | high                                  (default low)
//   DURATION           steady/warmup length                              (default 120s)
//   RATE_LOW/MED/HIGH  per-level arrival rate, req/s                     (default 3 / 6 / 12)
//   K6_SUMMARY_OUT     per-scenario JSON out path                        (default phaseA_summary.json)

import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const BASE = __ENV.BASE_URL;
const LEVEL = (__ENV.LEVEL || 'low').toLowerCase();
const DURATION = __ENV.DURATION || '120s';
const SUMMARY_OUT = __ENV.K6_SUMMARY_OUT || 'phaseA_summary.json';

if (!BASE) { throw new Error('BASE_URL env is required'); }

// Every request reaches the AI host, so the defaults sit under its measured ~12-13 req/s ceiling.
const RATES = {
  low:  parseInt(__ENV.RATE_LOW  || '3'),
  med:  parseInt(__ENV.RATE_MED  || '6'),
  high: parseInt(__ENV.RATE_HIGH || '12'),
};
const RATE = RATES[LEVEL];
const S = 'permutation_from_ai';

const lat = new Trend('lat_' + S, true);
const okr = new Rate('ok_' + S);

// Work unit from test-scenario.typ: AI returns a seeded 7-element set, which is then permuted.
const BODY = JSON.stringify({ count: 7, minVal: 1, maxVal: 10, seed: 42 });
const PARAMS = { headers: { 'Content-Type': 'application/json' }, timeout: '30s' };

export const options = {
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    permutation_from_ai: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: Math.max(4, Math.ceil(RATE * 2)),
      maxVUs: 60,
      gracefulStop: '30s',
      exec: 'permutation_from_ai',
      tags: { scenario: S },
    },
  },
};

export function permutation_from_ai() {
  const res = http.post(BASE + '/api/permutation/generate-from-ai', BODY, PARAMS);
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

  const out = { level: LEVEL, duration: DURATION, include_ai: true, scenarios: {} };
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
  ret['stdout'] = 'Phase A [' + LEVEL + '] PermutationService → AI @ ' + RATE + ' req/s -> ' + SUMMARY_OUT + '\n';
  return ret;
}
