// AI / S2-ext closed-loop probe.
// The AI service is CPU LLM inference (~0.3 req/s ceiling) and CANNOT take open-loop
// rate-based load. This probe uses a SINGLE VU doing per-VU iterations, so exactly one
// AI request is ever in flight -> it self-throttles to AI's real throughput and never
// melts the VM. Each iteration round-robins the three AI-touching scenarios and records
// per-scenario latency. Output: clean per-scenario chain latency.
//
// Env: BASE_URL (req), ITERS (total iterations, /3 per scenario; default 90),
//      K6_SUMMARY_OUT (default ai_probe_summary.json)

import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const BASE = __ENV.BASE_URL;
const ITERS = parseInt(__ENV.ITERS || '90', 10);
const SUMMARY_OUT = __ENV.K6_SUMMARY_OUT || 'ai_probe_summary.json';
if (!BASE) { throw new Error('BASE_URL env is required'); }

const TYPES = ['ai_generate', 'permutation_from_ai', 'filters_ai_matrix'];
const lat = {}, okr = {};
for (let i = 0; i < TYPES.length; i++) {
  lat[TYPES[i]] = new Trend('lat_' + TYPES[i], true);
  okr[TYPES[i]] = new Rate('ok_' + TYPES[i]);
}

export const options = {
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    ai_closed_loop: { executor: 'per-vu-iterations', vus: 1, iterations: ITERS, maxDuration: '90m', exec: 'probe' },
  },
};

// Long per-request timeout — AI can take several seconds; never want a false failure.
const JH = { headers: { 'Content-Type': 'application/json' }, timeout: '120s' };

function request(type) {
  if (type === 'ai_generate') {
    return http.post(BASE + '/api/Ai/generate',
      JSON.stringify({ user_input: 'Give me 10 random numbers between 1 and 100 with seed 42' }), JH);
  }
  if (type === 'permutation_from_ai') {
    return http.post(BASE + '/api/permutation/generate-from-ai',
      JSON.stringify({ count: 7, minVal: 1, maxVal: 10, seed: 42 }), JH);
  }
  return http.post(BASE + '/api/filters/apply-ai-matrix',
    JSON.stringify({ filterName: 'blur', kernelSize: 3 }), JH);
}

export function probe() {
  const type = TYPES[__ITER % TYPES.length];
  const res = request(type);
  const ok = res.status === 200;
  okr[type].add(ok);
  lat[type].add(res.timings.duration);
  const c = {}; c[type + ' status 200'] = function () { return ok; };
  check(res, c);
}

function val(o, k) { return (o && o[k] !== undefined && o[k] !== null) ? o[k] : null; }

export function handleSummary(data) {
  const out = { iterations: ITERS, scenarios: {} };
  for (let i = 0; i < TYPES.length; i++) {
    const t = TYPES[i];
    const tv = (data.metrics['lat_' + t] || {}).values || {};
    const rv = (data.metrics['ok_' + t] || {}).values || {};
    const reqs = (rv.passes || 0) + (rv.fails || 0);
    out.scenarios[t] = {
      reqs: reqs, fail_rate: reqs ? (rv.fails || 0) / reqs : null,
      lat_avg_ms: val(tv, 'avg'), lat_p50_ms: val(tv, 'med'), lat_p90_ms: val(tv, 'p(90)'),
      lat_p95_ms: val(tv, 'p(95)'), lat_p99_ms: val(tv, 'p(99)'), lat_max_ms: val(tv, 'max'),
    };
  }
  const ret = {}; ret[SUMMARY_OUT] = JSON.stringify(out, null, 2);
  ret['stdout'] = 'AI probe: ' + ITERS + ' iters (1 VU, closed-loop) -> ' + SUMMARY_OUT + '\n';
  return ret;
}
