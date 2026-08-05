// Phase A — isolated load for VideoService (video_compress).
// Endpoint: POST /api/video/compress  multipart form field `file` = fixed MP4 (ffmpeg x264 encode).
// HVY class: real transcoding, ~0.28s/req warm (pods raised to 4-core limit x3).
// Env:
//   BASE_URL        required, e.g. http://10.29.20.113:30080
//   LEVEL           low | med | high           (default low)
//   DURATION        steady/warmup length        (default 120s)
//   VID_PATH        path to fixed MP4 (on lg)   (default assets/sample_360p_1s.mp4)
//   RATE_LOW/MED/HIGH  per-level arrival rate (rps) override (defaults calibrated below)
//   K6_SUMMARY_OUT  per-scenario JSON out path  (default phaseA_summary.json)

import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const BASE = __ENV.BASE_URL;
const LEVEL = (__ENV.LEVEL || 'low').toLowerCase();
const DURATION = __ENV.DURATION || '120s';
const VID_PATH = __ENV.VID_PATH || 'assets/sample_360p_1s.mp4';
const SUMMARY_OUT = __ENV.K6_SUMMARY_OUT || 'phaseA_summary.json';

if (!BASE) { throw new Error('BASE_URL env is required'); }

// Fixed video work-unit asset (must be opened at init context).
const VID = open(VID_PATH, 'b');

// HVY isolated rates for video_compress. Calibrated against the raised 4-core x3 ceiling;
// overridable per level via RATE_LOW/RATE_MED/RATE_HIGH so they can be re-tuned without edits.
const RATES = {
  video_compress: {
    low:  parseInt(__ENV.RATE_LOW  || '6',  10),
    med:  parseInt(__ENV.RATE_MED  || '12', 10),
    high: parseInt(__ENV.RATE_HIGH || '18', 10),
  },
};

const SCENARIOS = ['video_compress'];

const lat = { video_compress: new Trend('lat_video_compress', true) };
const okr = { video_compress: new Rate('ok_video_compress') };

function rate(s) { return RATES[s][LEVEL]; }

export const options = {
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    video_compress: {
      executor: 'constant-arrival-rate',
      rate: rate('video_compress'),
      timeUnit: '1s',
      duration: DURATION,
      // HVY: encode is slow, so each in-flight request holds a VU for a while.
      preAllocatedVUs: 20,
      maxVUs: 80,
      gracefulStop: '30s',
      exec: 'video_compress',
      tags: { scenario: 'video_compress' },
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

export function video_compress() {
  record('video_compress',
    http.post(BASE + '/api/video/compress',
      { file: http.file(VID, 'sample_360p_1s.mp4', 'video/mp4') }));
}

function val(o, k) { return (o && o[k] !== undefined && o[k] !== null) ? o[k] : null; }

export function handleSummary(data) {
  const out = { level: LEVEL, duration: DURATION, include_ai: false, scenarios: {} };

  const s = 'video_compress';
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
  ret['stdout'] = 'Phase A [' + LEVEL + '] Isolated VideoService -> ' + SUMMARY_OUT + '\n';
  return ret;
}
