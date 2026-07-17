// Phase A — isolated load for IntegrationService (integration_calculate).
// Env:
//   BASE_URL        required, e.g. http://10.29.20.113:30080
//   LEVEL           low | med | high           (default low)
//   DURATION        steady/warmup length        (default 120s)
//   K6_SUMMARY_OUT  per-scenario JSON out path  (default phaseA_summary.json)

import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const BASE = __ENV.BASE_URL;
const LEVEL = (__ENV.LEVEL || 'low').toLowerCase();
const DURATION = __ENV.DURATION || '120s';
const SUMMARY_OUT = __ENV.K6_SUMMARY_OUT || 'phaseA_summary.json';

if (!BASE) { throw new Error('BASE_URL env is required'); }

// Isolated target rates for integration_calculate
const RATES = {
  integration_calculate: { low: 25, med: 50, high: 100 }
};

const SCENARIOS = ['integration_calculate'];

const lat = { integration_calculate: new Trend('lat_integration_calculate', true) };
const okr = { integration_calculate: new Rate('ok_integration_calculate') };

const JSON_HEADERS = { headers: { 'Content-Type': 'application/json' } };
function rate(s) { return RATES[s][LEVEL]; }

export const options = {
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    integration_calculate: {
      executor: 'constant-arrival-rate',
      rate: rate('integration_calculate'),
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: 20,
      maxVUs: 120,
      gracefulStop: '15s',
      exec: 'integration_calculate',
      tags: { scenario: 'integration_calculate' },
    }
  },
};

function record(s, res) {
  const ok = res.status === 200;
  okr[s].add(ok);
  lat[s].add(res.timings.duration);
  
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
}

export function integration_calculate() {
  record('integration_calculate',
    http.post(BASE + '/api/integration/calculate',
      JSON.stringify({ function: 'x^2', lowerBound: 0, upperBound: 1, steps: 20000 }), JSON_HEADERS));
}

function val(o, k) { return (o && o[k] !== undefined && o[k] !== null) ? o[k] : null; }

export function handleSummary(data) {
  const out = { level: LEVEL, duration: DURATION, include_ai: false, scenarios: {} };
  
  const s = 'integration_calculate';
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

  const ret = {};
  ret[SUMMARY_OUT] = JSON.stringify(out, null, 2);
  ret['stdout'] = 'Phase A [' + LEVEL + '] Isolated IntegrationService -> ' + SUMMARY_OUT + '\n';
  return ret;
}