// Phase A — isolated load for PermutationService (permutation_generate).
// Env:
//   BASE_URL        required, e.g. http://10.29.20.113:30080
//   LEVEL           low | med | high           (default low)
//   DURATION        steady/warmup length        (default 120s)
//   INCLUDE_AI      true | false                (default false)
//   K6_SUMMARY_OUT  per-scenario JSON out path  (default phaseA_permutation_summary.json)

import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const BASE = __ENV.BASE_URL;
const LEVEL = (__ENV.LEVEL || 'low').toLowerCase();
const DURATION = __ENV.DURATION || '120s';
const INCLUDE_AI = (__ENV.INCLUDE_AI || 'false') === 'true';
const SUMMARY_OUT = __ENV.K6_SUMMARY_OUT || 'phaseA_permutation_summary.json';

if (!BASE) { throw new Error('BASE_URL env is required'); }

// Baseline S1 target rates for permutation_generate; AI-chained variant is opt-in.
const RATES = {
  permutation_generate: { low: 25, med: 50, high: 100 },
  permutation_from_ai: { low: 1, med: 1, high: 1 },
};

function timeUnit(s) { return s === 'permutation_from_ai' ? '10s' : '1s'; }
function preVUs(s) { return s === 'permutation_from_ai' ? 8 : 20; }
function maxVUs(s) { return s === 'permutation_from_ai' ? 40 : 120; }
function rate(s) { return RATES[s][LEVEL]; }

const SCENARIOS = INCLUDE_AI ? ['permutation_generate', 'permutation_from_ai'] : ['permutation_generate'];

const lat = {};
const okr = {};
for (let i = 0; i < SCENARIOS.length; i++) {
  const s = SCENARIOS[i];
  lat[s] = new Trend('lat_' + s, true);
  okr[s] = new Rate('ok_' + s);
}

const JSON_HEADERS = { headers: { 'Content-Type': 'application/json' } };

export const options = {
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {},
};

for (let i = 0; i < SCENARIOS.length; i++) {
  const s = SCENARIOS[i];
  options.scenarios[s] = {
    executor: 'constant-arrival-rate',
    rate: rate(s),
    timeUnit: timeUnit(s),
    duration: DURATION,
    preAllocatedVUs: preVUs(s),
    maxVUs: maxVUs(s),
    gracefulStop: '15s',
    exec: s,
    tags: { scenario: s },
  };
}

function record(s, res) {
  const ok = res.status === 200;
  okr[s].add(ok);
  lat[s].add(res.timings.duration);

  check(res, {
    'status is 200': (r) => r.status === 200,
  });
}

export function permutation_generate() {
  record('permutation_generate',
    http.post(BASE + '/api/permutation/generate',
      JSON.stringify({ set: [1, 2, 3, 4, 5, 6, 7] }), JSON_HEADERS));
}

export function permutation_from_ai() {
  record('permutation_from_ai',
    http.post(BASE + '/api/permutation/generate-from-ai',
      JSON.stringify({ count: 7, minVal: 1, maxVal: 10, seed: 42 }), JSON_HEADERS));
}

function val(o, k) { return (o && o[k] !== undefined && o[k] !== null) ? o[k] : null; }

export function handleSummary(data) {
  const out = { level: LEVEL, duration: DURATION, include_ai: INCLUDE_AI, scenarios: {} };

  for (let i = 0; i < SCENARIOS.length; i++) {
    const s = SCENARIOS[i];
    const t = (data.metrics['lat_' + s] || {}).values || {};
    const r = (data.metrics['ok_' + s] || {}).values || {};
    const passes = r.passes || 0;
    const fails = r.fails || 0;
    const reqs = passes + fails;

    out.scenarios[s] = {
      rps_target: rate(s),
      reqs: reqs,
      fail_rate: reqs ? fails / reqs : null,
      lat_avg_ms: val(t, 'avg'),
      lat_p50_ms: val(t, 'med'),
      lat_p90_ms: val(t, 'p(90)'),
      lat_p95_ms: val(t, 'p(95)'),
      lat_p99_ms: val(t, 'p(99)'),
      lat_max_ms: val(t, 'max'),
    };
  }

  const ret = {};
  ret[SUMMARY_OUT] = JSON.stringify(out, null, 2);
  ret['stdout'] = 'Phase A [' + LEVEL + '] PermutationService -> ' + SUMMARY_OUT + '\n';
  return ret;
}
