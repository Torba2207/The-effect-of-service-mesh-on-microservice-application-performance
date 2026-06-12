// Phase B — aggregate full-system load.
// Drives every benchmarked service concurrently (one k6 scenario each) at its
// per-level rate, so the whole system is under realistic mixed contention.
// Per-scenario latency is recorded via custom Trends; a clean per-scenario JSON
// summary is written to K6_SUMMARY_OUT for the collector.
//
// Env:
//   BASE_URL        required, e.g. http://10.29.20.113:30080
//   LEVEL           low | med | high           (default low)
//   DURATION        steady/warmup length        (default 120s)
//   INCLUDE_AI      true | false                (default true)  - AI-touching scenarios
//   IMG_PATH        path to fixed PNG           (default assets/filter_input_128.png)
//   VID_PATH        path to fixed MP4           (default assets/sample_360p_1s.mp4)
//   K6_SUMMARY_OUT  per-scenario JSON out path  (default phaseB_summary.json)

import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const BASE = __ENV.BASE_URL;
const LEVEL = (__ENV.LEVEL || 'low').toLowerCase();
const DURATION = __ENV.DURATION || '120s';
// AI is OFF by default: the AI service does CPU LLM inference at ~1-3 MINUTES per
// request, so it cannot sustain a rate-based load (requests pile up and time out).
// Enable only for a dedicated low-rate probe.
const INCLUDE_AI = (__ENV.INCLUDE_AI || 'false') === 'true';
const SUMMARY_OUT = __ENV.K6_SUMMARY_OUT || 'phaseB_summary.json';
const IMG_PATH = __ENV.IMG_PATH || 'assets/filter_input_128.png';
const VID_PATH = __ENV.VID_PATH || 'assets/sample_360p_1s.mp4';

if (!BASE) { throw new Error('BASE_URL env is required'); }

// Fixed binary work-unit assets (must be opened at init context).
const IMG = open(IMG_PATH, 'b');
const VID = open(VID_PATH, 'b');

// Per-level target rates (requests/second) per scenario.
//                            low  med  high
const RATES = {
  permutation_generate:  { low: 25, med: 50, high: 100 }, // S1  STD
  fibonacci_calculate:   { low: 25, med: 50, high: 100 }, // S1  STD
  integration_calculate: { low: 25, med: 50, high: 100 }, // S1  STD
  filters_apply_image:   { low: 25, med: 50, high: 100 }, // S1  STD (multipart)
  differential_solve:    { low: 25, med: 50, high: 100 }, // S2-int STD (chains -> Integration)
  video_compress:        { low: 1,  med: 1,  high: 2  },  // S1  HVY (multipart, ~0.5s/req)
  ai_generate:           { low: 1,  med: 1,  high: 1  },  // S1  HVY  (external AI VM)
  permutation_from_ai:   { low: 1,  med: 1,  high: 1  },  // S2-ext   (-> external AI)
  filters_ai_matrix:     { low: 1,  med: 1,  high: 1  },  // S2-ext   (-> external AI)
};
// AI capacity is ~0.3 req/s TOTAL (CPU LLM inference, ~6-7s/req, 2 backends). The
// three AI scenarios therefore use a 10s timeUnit (0.1 req/s each = 0.3 r/s combined)
// AND are OFF by default. They are an opt-in trickle, never a real load tier.

const AI_SCENARIOS = ['ai_generate', 'permutation_from_ai', 'filters_ai_matrix'];
function timeUnit(s) { return AI_SCENARIOS.indexOf(s) !== -1 ? '10s' : '1s'; }
const SCENARIOS = Object.keys(RATES).filter(function (s) {
  return INCLUDE_AI || AI_SCENARIOS.indexOf(s) === -1;
});

const lat = {};  // per-scenario latency Trend (ms)
const okr = {};  // per-scenario success Rate
for (let i = 0; i < SCENARIOS.length; i++) {
  const s = SCENARIOS[i];
  lat[s] = new Trend('lat_' + s, true);
  okr[s] = new Rate('ok_' + s);
}

const JSON_HEADERS = { headers: { 'Content-Type': 'application/json' } };
function rate(s) { return RATES[s][LEVEL]; }
function preVUs(s) { return s === 'video_compress' ? 12 : (AI_SCENARIOS.indexOf(s) !== -1 ? 8 : 20); }
function maxVUs(s) { return s === 'video_compress' ? 60 : (AI_SCENARIOS.indexOf(s) !== -1 ? 40 : 120); }

function mkScenario(s) {
  return {
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

const scenarios = {};
for (let i = 0; i < SCENARIOS.length; i++) { scenarios[SCENARIOS[i]] = mkScenario(SCENARIOS[i]); }

export const options = {
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: scenarios,
};

function record(s, res) {
  const ok = res.status === 200;
  okr[s].add(ok);
  lat[s].add(res.timings.duration);
  const c = {};
  c[s + ' status 200'] = function () { return ok; };
  check(res, c);
}

export function permutation_generate() {
  record('permutation_generate',
    http.post(BASE + '/api/permutation/generate', JSON.stringify({ set: [1, 2, 3, 4, 5, 6, 7] }), JSON_HEADERS));
}
export function fibonacci_calculate() {
  record('fibonacci_calculate',
    http.post(BASE + '/api/fibonacci/calculate', JSON.stringify({ n: 3000 }), JSON_HEADERS));
}
export function integration_calculate() {
  record('integration_calculate',
    http.post(BASE + '/api/integration/calculate',
      JSON.stringify({ function: 'x^2', lowerBound: 0, upperBound: 1, steps: 20000 }), JSON_HEADERS));
}
export function differential_solve() {
  record('differential_solve',
    http.post(BASE + '/api/differential/solve',
      JSON.stringify({ function: 'x^2', initialConditionY: 1, steps: 5 }), JSON_HEADERS));
}
export function filters_apply_image() {
  record('filters_apply_image',
    http.post(BASE + '/api/filters/apply-image',
      { image: http.file(IMG, 'filter_input_128.png', 'image/png'), filterType: 'blur' }));
}
export function video_compress() {
  record('video_compress',
    http.post(BASE + '/api/video/compress',
      { file: http.file(VID, 'sample_360p_1s.mp4', 'video/mp4') }));
}
export function ai_generate() {
  record('ai_generate',
    http.post(BASE + '/api/Ai/generate',
      JSON.stringify({ user_input: 'Give me 10 random numbers between 1 and 100 with seed 42' }), JSON_HEADERS));
}
export function permutation_from_ai() {
  record('permutation_from_ai',
    http.post(BASE + '/api/permutation/generate-from-ai',
      JSON.stringify({ count: 7, minVal: 1, maxVal: 10, seed: 42 }), JSON_HEADERS));
}
export function filters_ai_matrix() {
  record('filters_ai_matrix',
    http.post(BASE + '/api/filters/apply-ai-matrix',
      JSON.stringify({ filterName: 'blur', kernelSize: 3 }), JSON_HEADERS));
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
  ret['stdout'] = 'Phase B [' + LEVEL + '] ' + SCENARIOS.length + ' scenarios, ' + DURATION + ' -> ' + SUMMARY_OUT + '\n';
  return ret;
}
