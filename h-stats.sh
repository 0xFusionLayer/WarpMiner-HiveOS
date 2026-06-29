#!/usr/bin/env bash

. /hive/miners/custom/warpminer/h-manifest.conf
[[ -z $CUSTOM_LOG_BASENAME ]] && CUSTOM_LOG_BASENAME="/var/log/miner/warpminer/log"

# Initialize arrays for storing device hashrates
declare -A device_hashrates

# Read the log file and parse the most recent hashrates
while IFS= read -r line; do
    if [[ $line =~ Device\ \[([0-9]+)\]\ hashRate:\ ([0-9.]+)kH ]]; then
        device="${BASH_REMATCH[1]}"
        hashrate="${BASH_REMATCH[2]}"
        device_hashrates[$device]=$hashrate
    fi
done < <(tail -n 100 $CUSTOM_LOG_BASENAME.log)

# Get GPU stats using jq
if [[ ! -z $gpu_stats ]]; then
    temp_array=$(jq '.temp' <<< "$gpu_stats")
    fan_array=$(jq '.fan' <<< "$gpu_stats")
else
    temp_array="[]"
    fan_array="[]"
fi

# Get miner uptime
if [[ -f /proc/$(pidof warpminer)/stat ]]; then
    uptime=$((`date +%s` - `stat -c %Y /proc/$(pidof warpminer)/stat`))
else
    uptime=0
fi

# Get accepted/rejected shares count from log
acc=$(grep -c "Solutions accepted" $CUSTOM_LOG_BASENAME.log)
rej=$(grep -c "Solutions rejected" $CUSTOM_LOG_BASENAME.log)

# Sort hashrates by device number and convert to JSON array
sorted_hs=$(for device in $(echo "${!device_hashrates[@]}" | tr ' ' '\n' | sort -n); do
    echo ${device_hashrates[$device]}
done | jq -s '.')

# Build complete stats JSON using jq
stats=$(jq -n \
    --argjson hs "$sorted_hs" \
    --arg hs_units "khs" \
    --argjson temp "$temp_array" \
    --argjson fan "$fan_array" \
    --arg uptime "$uptime" \
    --arg ver "$CUSTOM_VERSION" \
    --arg acc "$acc" \
    --arg rej "$rej" \
    '{$hs, $hs_units, $temp, $fan, uptime: ($uptime|tonumber), $ver, ar: [($acc|tonumber), ($rej|tonumber)]}'
)

# Calculate total hashrate from latest device hashrates
khs=0
for hashrate in "${device_hashrates[@]}"; do
    khs=$(echo "$khs + $hashrate" | bc)
done

[[ -z $khs ]] && khs=0
[[ -z $stats ]] && stats="null"

# Output stats
# echo stats: $stats
# echo khs:   $khs