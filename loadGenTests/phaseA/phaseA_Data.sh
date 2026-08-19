#!/usr/bin/env bash
# Usage: source service_data.sh <service_name>

SERVICE_ARG="$1"

case "$SERVICE_ARG" in
  "digital")
    SERVICE_DIR="DigitalFiltersService"
    CONFIG="baseline_digital_filters_S1"
    JS_FILE="filters-test.js"
    HAS_ASSETS="true"
    ASSET_FILE="filter_input_128.png"
    K6_EXTRA_ENV="IMG_PATH=assets/filter_input_128.png"
    PREFLIGHT_CMD="curl -s -m 8 -o /dev/null -w '   filters/available -> http=%{http_code}\n' \"\$URL/api/filters/available\""
    ;;
  "fibonacci")
    SERVICE_DIR="FibonacciService"
    CONFIG="baseline_fibonacci_S1"
    JS_FILE="fibonacci-test.js"
    HAS_ASSETS="false"
    K6_EXTRA_ENV="FIB_N=\${FIB_N:-3000}"
    PREFLIGHT_CMD="curl -s -m 8 -X POST -H 'Content-Type: application/json' -d '{\"n\":10}' -o /dev/null -w '   api -> http=%{http_code}\n' \"\$URL/api/fibonacci/calculate\""
    ;;
  "integration")
    SERVICE_DIR="IntegrationService"
    CONFIG="baseline_integration_S1"
    JS_FILE="integration-test.js"
    HAS_ASSETS="false"
    K6_EXTRA_ENV=""
    PREFLIGHT_CMD="curl -s -m 8 -X POST -H 'Content-Type: application/json' -d '{\"function\":\"x\",\"lowerBound\":0,\"upperBound\":1,\"steps\":10}' -o /dev/null -w '   api -> http=%{http_code}\n' \"\$URL/api/integration/calculate\""
    ;;
  "permutation")
    SERVICE_DIR="PermutationService"
    CONFIG="baseline_permutation_S1"
    JS_FILE="permutation-test.js"
    HAS_ASSETS="false"
    K6_EXTRA_ENV=""
    PREFLIGHT_CMD="curl -s -m 8 -o /dev/null -w '   ingress -> http=%{http_code}\n' -X POST \"\$URL/api/permutation/generate\" -H 'Content-Type: application/json' -d '{\"set\":[1,2,3,4,5,6,7]}'"
    ;;
  "video")
    SERVICE_DIR="VideoService"
    CONFIG="baseline_video_S1"
    JS_FILE="video-test.js"
    HAS_ASSETS="true"
    ASSET_FILE="sample_360p_1s.mp4"
    K6_EXTRA_ENV="VID_PATH=assets/sample_360p_1s.mp4 RATE_LOW=6 RATE_MED=12 RATE_HIGH=18"
    PREFLIGHT_CMD="curl -s -m 20 -X POST -F 'file=@../../common/assets/sample_360p_1s.mp4;type=video/mp4' -o /dev/null -w '   api -> http=%{http_code}\n' \"\$URL/api/video/compress\""
    ;;
  *)
    echo "ERROR: Invalid service '$SERVICE_ARG'. Allowed: filters, permutation, video, fibonacci, integration"
    return 1 2>/dev/null || exit 1
    ;;
esac