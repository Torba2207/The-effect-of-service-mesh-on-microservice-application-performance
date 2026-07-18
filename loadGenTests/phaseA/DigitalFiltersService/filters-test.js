// Phase A — isolated load for DigitalFiltersService (filters_apply_image).
// Env:
//   BASE_URL        required, e.g. http://10.29.20.113:30080
//   LEVEL           low | med | high           (default low)
//   DURATION        steady/warmup length        (default 120s)
//   INCLUDE_AI      true | false                (default false)
//   IMG_PATH        path to fixed PNG (on lg)   (default assets/filter_input_128.png)
//   K6_SUMMARY_OUT  per-scenario JSON out path  (default phaseA_filters_summary.json)

import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const BASE = __ENV.BASE_URL;
const LEVEL = (__ENV.LEVEL || 'low').toLowerCase();
const DURATION = __ENV.DURATION || '120s';
const INCLUDE_AI = (__ENV.INCLUDE_AI || 'false') === 'true';
const IMG_PATH = __ENV.IMG_PATH || 'assets/filter_input_128.png';
const SUMMARY_OUT = __ENV.K6_SUMMARY_OUT || 'phaseA_filters_summary.json';

if (!BASE) { throw new Error('BASE_URL env is required'); }

// Fixed image work-unit asset (must be opened at init context).
const IMG = open(IMG_PATH, 'b');

// Baseline S1 target rates for filters_apply_image; AI-chained variant is opt-in.
const RATES = {
  filters_apply_image: { low: 25, med: 50, high: 100 },
  filters_ai_matrix:   { low: 1,  med: 1,  high: 1 },
};

function timeUnit(s) { return s === 'filters_ai_matrix' ? '10s' : '1s'; }
function preVUs(s) { return s === 'filters_ai_matrix' ? 8 : 20; }
function maxVUs(s) { return s === 'filters_ai_matrix' ? 40 : 120; }
function rate(s) { return RATES[s][LEVEL]; }

const SCENARIOS = INCLUDE_AI ? ['filters_apply_image', 'filters_ai_matrix'] : ['filters_apply_image'];

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

export function filters_apply_image() {
  record('filters_apply_image',
    http.post(BASE + '/api/filters/apply-image',
      { image: http.file(IMG, 'filter_input_128.png', 'image/png'), filterType: 'blur' }));
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
  ret['stdout'] = 'Phase A [' + LEVEL + '] DigitalFiltersService -> ' + SUMMARY_OUT + '\n';
  return ret;
}
