#!/usr/bin/env bash
# Per-service settings for run_phaseA_Core.sh. Sourced by the Core, never run on its own:
#   source phaseA_Data.sh <service_key>
#
# Service keys:
#   S1 (single hop)      digital | fibonacci | integration | permutation | video | ai
#   S2-ext (chain → AI)  permutation_ai | digital_ai
#
# Sets, for the selected service:
#   SERVICE_DIR    directory holding the k6 script and results/
#   SERVICE_SLUG   service part of the run label
#   SCENARIO_TAG   scenario part of the run label: S1 or S2ext. The Core builds
#                  CONFIG="<config label>_<SERVICE_SLUG>_<SCENARIO_TAG>"  (e.g. baseline_fibonacci_S1)
#   JS_FILE        k6 script, copied to the load generator
#   HAS_ASSETS     "true" if the scenario posts a fixed binary asset
#   ASSET_FILE     that asset, in loadGenTests/common/assets/ (only when HAS_ASSETS=true)
#   DEFAULT_RATES  "LOW MED HIGH" req/s when the k6 script reads RATE_LOW/MED/HIGH, overridable
#                  with the Core's -R; empty when the script's rates are fixed
#   USES_AI        "true" if requests reach the external AI host
#   K6_EXTRA_ENV   extra k6 environment, expanded HERE (locally), not on the load generator
#   PREFLIGHT_CMD  one smoke request; eval'd later by the Core, so \$URL and \$COMMON stay
#                  escaped and resolve at that point
#
# Expects the caller to have set: URL, COMMON, and FIB_N (fibonacci work-unit size, -N).

SERVICE_ARG="$1"

# Defaults, overridden per service below.
SCENARIO_TAG="S1"
HAS_ASSETS="false"
ASSET_FILE=""
DEFAULT_RATES=""
USES_AI="false"
K6_EXTRA_ENV=""

case "$SERVICE_ARG" in
  "digital")
    SERVICE_DIR="DigitalFiltersService"
    SERVICE_SLUG="digital_filters"
    JS_FILE="filters-test.js"
    HAS_ASSETS="true"
    ASSET_FILE="filter_input_128.png"
    K6_EXTRA_ENV="IMG_PATH=assets/filter_input_128.png"
    PREFLIGHT_CMD="curl -s -m 8 -o /dev/null -w '   filters/available -> http=%{http_code}\n' \"\$URL/api/filters/available\""
    ;;
  "fibonacci")
    SERVICE_DIR="FibonacciService"
    SERVICE_SLUG="fibonacci"
    JS_FILE="fibonacci-test.js"
    K6_EXTRA_ENV="FIB_N=$FIB_N"
    PREFLIGHT_CMD="curl -s -m 8 -X POST -H 'Content-Type: application/json' -d '{\"n\":10}' -o /dev/null -w '   api -> http=%{http_code}\n' \"\$URL/api/fibonacci/calculate\""
    ;;
  "integration")
    SERVICE_DIR="IntegrationService"
    SERVICE_SLUG="integration"
    JS_FILE="integration-test.js"
    PREFLIGHT_CMD="curl -s -m 8 -X POST -H 'Content-Type: application/json' -d '{\"function\":\"x\",\"lowerBound\":0,\"upperBound\":1,\"steps\":10}' -o /dev/null -w '   api -> http=%{http_code}\n' \"\$URL/api/integration/calculate\""
    ;;
  "permutation")
    SERVICE_DIR="PermutationService"
    SERVICE_SLUG="permutation"
    JS_FILE="permutation-test.js"
    PREFLIGHT_CMD="curl -s -m 8 -o /dev/null -w '   ingress -> http=%{http_code}\n' -X POST \"\$URL/api/permutation/generate\" -H 'Content-Type: application/json' -d '{\"set\":[1,2,3,4,5,6,7]}'"
    ;;
  "video")
    SERVICE_DIR="VideoService"
    SERVICE_SLUG="video"
    JS_FILE="video-test.js"
    HAS_ASSETS="true"
    ASSET_FILE="sample_360p_1s.mp4"
    DEFAULT_RATES="6 12 18"
    K6_EXTRA_ENV="VID_PATH=assets/sample_360p_1s.mp4"
    PREFLIGHT_CMD="curl -s -m 20 -X POST -F \"file=@\$COMMON/assets/sample_360p_1s.mp4;type=video/mp4\" -o /dev/null -w '   api -> http=%{http_code}\n' \"\$URL/api/video/compress\""
    ;;
  "ai")
    SERVICE_DIR="AiService"
    SERVICE_SLUG="ai"
    JS_FILE="ai-test.js"
    DEFAULT_RATES="3 6 12"
    USES_AI="true"
    # The prompt is seeded; this is exactly what the MCP tool computes (Python random.Random(42)).
    AI_EXPECTED="$(python3 -c 'import random, json; r = random.Random(42); print(json.dumps([r.randint(1, 100) for _ in range(10)]))')"
    K6_EXTRA_ENV="EXPECTED='$AI_EXPECTED'"
    PREFLIGHT_CMD="curl -s -m 10 -o /dev/null -w '   Ai/health -> http=%{http_code}\n' \"\$URL/api/Ai/health\""
    ;;
  "permutation_ai")
    SERVICE_DIR="PermutationService"
    SERVICE_SLUG="permutation"
    SCENARIO_TAG="S2ext"
    JS_FILE="permutation-ai-test.js"
    DEFAULT_RATES="3 6 12"
    USES_AI="true"
    PREFLIGHT_CMD="curl -s -m 30 -X POST -H 'Content-Type: application/json' -d '{\"count\":3,\"minVal\":1,\"maxVal\":10,\"seed\":42}' -o /dev/null -w '   permutation/generate-from-ai -> http=%{http_code}\n' \"\$URL/api/permutation/generate-from-ai\""
    ;;
  "digital_ai")
    SERVICE_DIR="DigitalFiltersService"
    SERVICE_SLUG="digital_filters"
    SCENARIO_TAG="S2ext"
    JS_FILE="filters-ai-test.js"
    DEFAULT_RATES="3 6 12"
    USES_AI="true"
    PREFLIGHT_CMD="curl -s -m 30 -X POST -H 'Content-Type: application/json' -d '{\"filterName\":\"blur\",\"kernelSize\":3}' -o /dev/null -w '   filters/apply-ai-matrix -> http=%{http_code}\n' \"\$URL/api/filters/apply-ai-matrix\""
    ;;
  *)
    echo "ERROR: Invalid service '$SERVICE_ARG'. Allowed: digital, fibonacci, integration, permutation, video, ai, permutation_ai, digital_ai"
    return 1 2>/dev/null || exit 1
    ;;
esac
