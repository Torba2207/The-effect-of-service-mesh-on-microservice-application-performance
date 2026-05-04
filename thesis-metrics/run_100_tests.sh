#!/bin/bash

# Validate inputs
if [ "$#" -ne 5 ]; then
    echo "❌ Error: Missing arguments."
    echo "💡 Usage: ./run_100_tests.sh [phase_name] [target_url] [iterations] [seconds_sleep] [rps]"
    echo "💡 Example: ./run_100_tests.sh baseline http://10.29.20.111:30000/api/permutation/generate 100 5 25"
    exit 1
fi

PHASE=$1
URL=$2
ITERATIONS=$3
SECONDS_SLEEP=$4
RPS=$5

# --- SSH CONFIGURATION FOR LOAD GENERATOR ---
SSH_KEY="~/Documents/PG/Projects/.sshkeys/pgPB"
LG_IP="10.29.20.130"
LG_USER="root"
LG_DIR="~/thesis-tests" # The folder on LG where permutation-test.js lives

echo "🚀 Starting automated test suite for Phase: $PHASE"
echo "🎯 Target URL: $URL"
echo "🔫 Load Generator: $LG_USER@$LG_IP"
echo "🔄 Total Iterations: $ITERATIONS"
echo "--------------------------------------------------------"

for ((i=1; i<=ITERATIONS; i++)); do
    echo "▶️  Starting Iteration $i of $ITERATIONS..."
    
    # 1. Start recording metrics locally in the background
    ./record_metrics.sh "${PHASE}${i}_${RPS}" > /dev/null 2>&1 &
    REC_PID=$!
    
    # 2. Wait $SECONDS_SLEEP seconds to establish a baseline
    #echo "⏳ Waiting $SECONDS_SLEEP seconds for baseline metrics..."
    #sleep $SECONDS_SLEEP
    
    # 3. Run the k6 load test via SSH on the LG machine
    # We pipe the output (> ...) locally so the summary file saves on your laptop, not the LG machine!
    echo "🔥 Triggering remote k6 load test on $LG_IP..."
    ssh -i $SSH_KEY $LG_USER@$LG_IP "cd $LG_DIR && k6 run -e TARGET_RPS=$RPS -e TARGET_URL='$URL' permutation-test.js" > "k6_${PHASE}${i}_rps${RPS}_summary.txt" 2>&1
    
    # 4. Wait $SECONDS_SLEEP seconds to capture the cooldown metrics
    echo "⏳ Waiting $SECONDS_SLEEP seconds for cooldown metrics..."
    sleep $SECONDS_SLEEP
    
    # 5. Stop the recording script safely
    echo "🛑 Stopping metrics recording for iteration $i."
    kill $REC_PID
    wait $REC_PID 2>/dev/null # Suppress the "Terminated" message
    
    echo "✅ Iteration $i complete."
    echo "--------------------------------------------------------"
done

echo "🎉 All $ITERATIONS iterations for $PHASE are complete!"