// AI host capacity step — one open-loop rate held for DURATION against /api/Ai/generate.
// run_ai_capacity.sh calls this once per rung of the ladder (e.g. 3 → 6 → 12 req/s).
//
// Unlike ai_probe.js this is rate-based on purpose: it answers "can the AI host sustain R req/s",
// which is what decides whether the AI / S2-ext scenarios can use the normal open-loop model.
// In-flight requests are capped by MAX_VUS so an overloaded host sees a bounded backlog, and
// k6 aborts the step early if the host starts failing outright.
//
// Env:
//   BASE_URL        required, AI entry point, e.g. http://10.29.20.121:5005
//   RATE            required, target req/s
//   DURATION        how long to hold the rate                       (default 120s)
//   MAX_VUS         cap on concurrent in-flight requests            (default 60)
//   EXPECTED        JSON array the seeded prompt must return; a 200 with any other payload
//                   counts as a wrong answer, not a success         (optional)
//   K6_SUMMARY_OUT  summary JSON path                               (default ai_capacity_summary.json)

import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

const BASE = __ENV.BASE_URL;
const RATE = parseFloat(__ENV.RATE || '');
const DURATION = __ENV.DURATION || '120s';
const MAX_VUS = parseInt(__ENV.MAX_VUS || '60', 10);
const EXPECTED = __ENV.EXPECTED ? JSON.stringify(JSON.parse(__ENV.EXPECTED)) : null;
const SUMMARY_OUT = __ENV.K6_SUMMARY_OUT || 'ai_capacity_summary.json';

if (!BASE) { throw new Error('BASE_URL env is required'); }
if (!(RATE > 0)) { throw new Error('RATE env must be a positive number'); }

const PROMPT = JSON.stringify({ user_input: 'Give me 10 random numbers between 1 and 100 with seed 42' });
const PARAMS = { headers: { 'Content-Type': 'application/json' }, timeout: '30s' };

const lat = new Trend('lat_ai_generate', true);
const svcExec = new Trend('svc_exec_ms', true);    // service-reported ExecutionTimeMS
const ok = new Rate('ok_ai_generate');              // HTTP 200
const correct = new Rate('correct_ai_generate');    // HTTP 200 AND the expected numbers
const wrong = new Counter('wrong_answers');

// Whole-number rates use a 1 s unit; fractional ones (e.g. 0.5) are scaled to a 10 s unit.
const whole = Number.isInteger(RATE);

export const options = {
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    ai_generate: {
      executor: 'constant-arrival-rate',
      rate: whole ? RATE : Math.round(RATE * 10),
      timeUnit: whole ? '1s' : '10s',
      duration: DURATION,
      preAllocatedVUs: Math.min(MAX_VUS, Math.max(4, Math.ceil(RATE * 2))),
      maxVUs: MAX_VUS,
      gracefulStop: '30s',
    },
  },
  thresholds: {
    // Protect the host: stop the step if a fifth of requests fail after the first 30 s.
    ok_ai_generate: [{ threshold: 'rate>0.8', abortOnFail: true, delayAbortEval: '30s' }],
  },
};

export default function () {
  const res = http.post(BASE + '/api/Ai/generate', PROMPT, PARAMS);
  const is200 = res.status === 200;
  ok.add(is200);
  lat.add(res.timings.duration);

  let good = false;
  if (is200) {
    try {
      const body = res.json();
      if (typeof body.ExecutionTimeMS === 'number') { svcExec.add(body.ExecutionTimeMS); }
      const data = body.Data;
      good = Array.isArray(data) && data.length === 10
        && (EXPECTED === null || JSON.stringify(data) === EXPECTED);
    } catch (e) {
      good = false;
    }
    if (!good) { wrong.add(1); }
  }
  correct.add(good);
  check(res, { 'status 200': () => is200, 'expected numbers': () => good });
}

function val(o, k) { return (o && o[k] !== undefined && o[k] !== null) ? o[k] : null; }

function seconds(d) {
  const m = /^(\d+(?:\.\d+)?)(ms|s|m|h)$/.exec(d);
  if (!m) { return null; }
  return parseFloat(m[1]) * { ms: 0.001, s: 1, m: 60, h: 3600 }[m[2]];
}

export function handleSummary(data) {
  const metric = (name) => (data.metrics[name] || {}).values || {};
  const t = metric('lat_ai_generate');
  const e = metric('svc_exec_ms');
  const r = metric('ok_ai_generate');
  const c = metric('correct_ai_generate');
  const reqs = (r.passes || 0) + (r.fails || 0);
  const dropped = metric('dropped_iterations').count || 0;
  const secs = seconds(DURATION);

  const out = {
    rate_target: RATE,
    duration: DURATION,
    reqs: reqs,
    rate_achieved: secs ? reqs / secs : null,
    dropped_iterations: dropped,
    drop_rate: (reqs + dropped) ? dropped / (reqs + dropped) : null,
    fail_rate: reqs ? (r.fails || 0) / reqs : null,
    wrong_answer_rate: reqs ? (c.fails || 0) / reqs - (r.fails || 0) / reqs : null,
    vus_max_used: metric('vus_max').max || metric('vus_max').value || null,
    lat_avg_ms: val(t, 'avg'), lat_p50_ms: val(t, 'med'), lat_p90_ms: val(t, 'p(90)'),
    lat_p95_ms: val(t, 'p(95)'), lat_p99_ms: val(t, 'p(99)'), lat_max_ms: val(t, 'max'),
    svc_exec_p50_ms: val(e, 'med'), svc_exec_p95_ms: val(e, 'p(95)'),
    aborted: Object.values(data.metrics).some((m) =>
      m.thresholds && Object.values(m.thresholds).some((th) => th.ok === false)),
  };

  const ret = {};
  ret[SUMMARY_OUT] = JSON.stringify(out, null, 2);
  ret['stdout'] = 'AI capacity step @ ' + RATE + ' req/s -> ' + SUMMARY_OUT + '\n';
  return ret;
}
