#!/bin/bash

# Check if the user provided a test phase name
if [ -z "$1" ]; then
  echo "❌ Error: Please specify the test phase."
  echo "💡 Usage: ./record_metrics.sh [baseline|istio|linkerd]"
  exit 1
fi

PHASE=$1
FILENAME="${PHASE}_results.txt"
NAMESPACE="thesis-test"

echo "📊 Starting metrics recording for Phase: $PHASE"
echo "💾 Saving data to: $FILENAME"
echo "🛑 Press [Ctrl+C] to stop recording when your k6 test finishes."
echo "--------------------------------------------------------"

# Ensure the file is empty before starting a new test
> "$FILENAME"

# The infinite recording loop
while true; do 
  echo "--- $(date '+%H:%M:%S') ---" >> "$FILENAME"
  kubectl top pods -n "$NAMESPACE" >> "$FILENAME"
  sleep 1
done