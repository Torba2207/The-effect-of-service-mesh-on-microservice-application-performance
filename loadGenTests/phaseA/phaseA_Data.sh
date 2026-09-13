#!/usr/bin/env bash
# Per-service settings for run_phaseA_Core.sh. Sourced by the Core, never run on its own:
#   source phaseA_Data.sh <service_key>
# Service keys: digital | fibonacci | integration | permutation | video
#
# Sets, for the selected service:
#   SERVICE_DIR    directory holding the k6 script and results/
#   SERVICE_SLUG   service part of the run label; the Core builds
#                  CONFIG="<config label>_<SERVICE_SLUG>_S1"  (e.g. baseline_fibonacci_S1)
#   JS_FILE        k6 script, copied to the load generator
#   HAS_ASSETS     "true" if the scenario posts a fixed binary asset
#   ASSET_FILE     that asset, in loadGenTests/common/assets/ (only when HAS_ASSETS=true)
#   K6_EXTRA_ENV   extra k6 environment, expanded HERE (locally), not on the load generator
#   PREFLIGHT_CMD  one smoke request; eval'd later by the Core, so \$URL and \$COMMON stay
#                  escaped and resolve at that point
#
# Expects the caller to have set: URL, COMMON, and FIB_N (fibonacci work-unit size, -N).

SERVICE_ARG="$1"

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
    HAS_ASSETS="false"
    K6_EXTRA_ENV="FIB_N=$FIB_N"
    PREFLIGHT_CMD="curl -s -m 8 -X POST -H 'Content-Type: application/json' -d '{\"n\":10}' -o /dev/null -w '   api -> http=%{http_code}\n' \"\$URL/api/fibonacci/calculate\""
    ;;
  "integration")
    SERVICE_DIR="IntegrationService"
    SERVICE_SLUG="integration"
    JS_FILE="integration-test.js"
    HAS_ASSETS="false"
    K6_EXTRA_ENV=""
    PREFLIGHT_CMD="curl -s -m 8 -X POST -H 'Content-Type: application/json' -d '{\"function\":\"x\",\"lowerBound\":0,\"upperBound\":1,\"steps\":10}' -o /dev/null -w '   api -> http=%{http_code}\n' \"\$URL/api/integration/calculate\""
    ;;
  "permutation")
    SERVICE_DIR="PermutationService"
    SERVICE_SLUG="permutation"
    JS_FILE="permutation-test.js"
    HAS_ASSETS="false"
    K6_EXTRA_ENV=""
    PREFLIGHT_CMD="curl -s -m 8 -o /dev/null -w '   ingress -> http=%{http_code}\n' -X POST \"\$URL/api/permutation/generate\" -H 'Content-Type: application/json' -d '{\"set\":[1,2,3,4,5,6,7]}'"
    ;;
  "video")
    SERVICE_DIR="VideoService"
    SERVICE_SLUG="video"
    JS_FILE="video-test.js"
    HAS_ASSETS="true"
    ASSET_FILE="sample_360p_1s.mp4"
    K6_EXTRA_ENV="VID_PATH=assets/sample_360p_1s.mp4 RATE_LOW=6 RATE_MED=12 RATE_HIGH=18"
    PREFLIGHT_CMD="curl -s -m 20 -X POST -F \"file=@\$COMMON/assets/sample_360p_1s.mp4;type=video/mp4\" -o /dev/null -w '   api -> http=%{http_code}\n' \"\$URL/api/video/compress\""
    ;;
  *)
    echo "ERROR: Invalid service '$SERVICE_ARG'. Allowed: digital, fibonacci, integration, permutation, video"
    return 1 2>/dev/null || exit 1
    ;;
esac
