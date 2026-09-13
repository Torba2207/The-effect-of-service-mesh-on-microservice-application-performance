// Phase A — isolated load for the AI service itself (ai_generate), S1 / HVY.
// Endpoint: POST /api/Ai/generate through the cluster ingress, which routes /api/Ai to the
// external (unmeshed) AI host. The prompt is seeded, so the correct answer is known in advance.
// Env:
//   BASE_URL           required, e.g. http://10.29.20.113:30080
//   LEVEL              low | med | high                                  (default low)
//   DURATION           steady/warmup length                              (default 120s)
//   RATE_LOW/MED/HIGH  per-level arrival rate, req/s                     (default 3 / 6 / 12)
//   EXPECTED           JSON array the seeded prompt must return; a 200 with any other payload
//                      is counted in wrong_answer_rate                   (optional)
//   K6_SUMMARY_OUT     per-scenario JSON out path                        (default phaseA_summary.json)

import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const BASE = __ENV.BASE_URL;
const LEVEL = (__ENV.LEVEL || 'low').toLowerCase();
const DURATION = __ENV.DURATION || '120s';
const EXPECTED = __ENV.EXPECTED ? JSON.stringify(JSON.parse(__ENV.EXPECTED)) : null;
const SUMMARY_OUT = __ENV.K6_SUMMARY_OUT || 'phaseA_summary.json';

if (!BASE) { throw new Error('BASE_URL env is required'); }

// Defaults sit well under the measured AI host ceiling (~12-13 req/s on the RTX 4070 host).
const RATES = {
  low:  parseInt(__ENV.RATE_LOW  || '3'),
  med:  parseInt(__ENV.RATE_MED  || '6'),
  high: parseInt(__ENV.RATE_HIGH || '12'),
};
const RATE = RATES[LEVEL];
const S = 'ai_generate';

const lat = new Trend('lat_' + S, true);
const okr = new Rate('ok_' + S);
const correct = new Rate('correct_' + S);

const PROMPT = JSON.stringify({ user_input: 'Give me 10 random numbers between 1 and 100 with seed 42' });
const PARAMS = { headers: { 'Content-Type': 'application/json' }, timeout: '30s' };

export const options = {
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    ai_generate: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      // Inference holds a VU for ~0.3-1 s; cap in-flight so an overloaded host sees a bounded backlog.
      preAllocatedVUs: Math.max(4, Math.ceil(RATE * 2)),
      maxVUs: 60,
      gracefulStop: '30s',
      exec: 'ai_generate',
      tags: { scenario: S },
    },
  },
};

export function ai_generate() {
  const res = http.post(BASE + '/api/Ai/generate', PROMPT, PARAMS);
  const ok = res.status === 200;
  okr.add(ok);
  lat.add(res.timings.duration);

  let good = false;
  if (ok) {
    try {
      const data = res.json('Data');
      good = Array.isArray(data) && data.length === 10
        && (EXPECTED === null || JSON.stringify(data) === EXPECTED);
    } catch (e) {
      good = false;
    }
  }
  correct.add(good);
  check(res, { 'status is 200': () => ok, 'expected numbers': () => good });
}

function val(o, k) { return (o && o[k] !== undefined && o[k] !== null) ? o[k] : null; }

export function handleSummary(data) {
  const t = (data.metrics['lat_' + S] || {}).values || {};
  const r = (data.metrics['ok_' + S] || {}).values || {};
  const c = (data.metrics['correct_' + S] || {}).values || {};
  const fails = r.fails || 0;
  const reqs = (r.passes || 0) + fails;

  const out = { level: LEVEL, duration: DURATION, include_ai: true, scenarios: {} };
  out.scenarios[S] = {
    rps_target: RATE,
    reqs: reqs,
    fail_rate: reqs ? fails / reqs : null,
    wrong_answer_rate: reqs ? ((c.fails || 0) - fails) / reqs : null,
    lat_avg_ms: val(t, 'avg'),
    lat_p50_ms: val(t, 'med'),
    lat_p90_ms: val(t, 'p(90)'),
    lat_p95_ms: val(t, 'p(95)'),
    lat_p99_ms: val(t, 'p(99)'),
    lat_max_ms: val(t, 'max'),
  };

  const ret = {};
  ret[SUMMARY_OUT] = JSON.stringify(out, null, 2);
  ret['stdout'] = 'Phase A [' + LEVEL + '] AiService ai_generate @ ' + RATE + ' req/s -> ' + SUMMARY_OUT + '\n';
  return ret;
}
