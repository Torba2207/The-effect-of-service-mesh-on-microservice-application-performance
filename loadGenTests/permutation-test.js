import http from 'k6/http';
import { check } from 'k6';

const TARGET_URL = __ENV.TARGET_URL;
// Read RPS from command line, default to 200 if not provided
const TARGET_RPS = __ENV.TARGET_RPS || 200; 

export const options = {
  scenarios: {
    constant_load: {
      executor: 'constant-arrival-rate',
      rate: TARGET_RPS, // How many requests...
      timeUnit: '1s',   // ...per second
      duration: '30s',
      // We still allocate 25 VUs so kube-proxy sees multiple connections
      preAllocatedVUs: 25, 
      // If the cluster gets slow, k6 is allowed to spin up to 200 VUs to maintain the target RPS
      maxVUs: 200,         
    },
  },
};

export default function () {
  const payload = JSON.stringify({
    set: [1, 2, 3, 4, 5, 6, 7] 
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };

  const res = http.post(TARGET_URL, payload, params);

  check(res, {
    'is status 200': (r) => r.status === 200,
  });
}
// baseline
// k6 run -e TARGET_RPS=200 -e TARGET_URL="http://10.29.20.111:30000/api/permutation/generate" permutation-test.js

// istio
// kubectl get svc istio-ingressgateway -n istio-system
// k6 run -e TARGET_RPS=200 -e TARGET_URL="http://10.29.20.111:32364/api/permutation/generate" permutation-test.js

// linkerd
// k6 run -e TARGET_RPS=200 -e TARGET_URL="http://10.29.20.111:30100/api/permutation/generate" permutation-test.js