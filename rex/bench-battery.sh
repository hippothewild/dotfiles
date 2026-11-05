#!/bin/bash
# bench-battery.sh LABEL PROCESS_REGEX [SECONDS=600] [INTERVAL=10]
# Compare terminal apps' power use. Run once per app, on battery, with the
# other app quit and the same workload each time, e.g.:
#   bench-battery.sh rex  '^(Rex|rex)$' 600  # `top` command names, regex
#   bench-battery.sh cmux '^cmux'                      600
# Reports (no sudo): per-process CPU% and Energy Impact averages from `top`,
# and whole-system battery draw (W) from the battery's amperage x voltage.
set -u
label=${1:?label}; regex=${2:?process regex}; secs=${3:-600}; step=${4:-10}
out=~/.local/state/battery-bench; mkdir -p "$out"
csv="$out/$label-$(date +%Y%m%d-%H%M%S).csv"

source=$(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/")
[ "$source" = "Battery Power" ] || echo "WARN: on '$source' - system watts will read ~0/charging; process numbers still valid." >&2
pct0=$(pmset -g batt | grep -o '[0-9]*%' | head -1)

watts() { # positive = draw from battery
  ioreg -rn AppleSmartBattery | awk -F' = ' '
    /"Amperage"/ {a=$2} /"Voltage"/ && !v {v=$2}
    END { if (a>9223372036854775807/2) a-=18446744073709551616; printf "%.2f", -a*v/1e6 }'
}

echo "ts,sys_watts,proc_cpu,proc_power" > "$csv"
n=$((secs/step))
for ((i=0;i<n;i++)); do
  # 2 samples: the first top sample is cumulative-since-boot, use the second
  row=$(top -l 2 -n 200 -stats command,cpu,power 2>/dev/null | awk '/^COMMAND/{s++} s==2' \
        | awk -v re="$regex" '{cmd=$1; for(j=2;j<=NF-2;j++) cmd=cmd" "$j; if (cmd ~ re) {c+=$(NF-1); p+=$NF}} END {printf "%.2f,%.2f", c, p}')
  echo "$(date +%s),$(watts),${row:-0,0}" >> "$csv"
  sleep "$step"
done

pct1=$(pmset -g batt | grep -o '[0-9]*%' | head -1)
awk -F, -v l="$label" -v p0="$pct0" -v p1="$pct1" -v src="$source" 'NR>1 {w+=$2; c+=$3; p+=$4; k++}
  END { printf "%s: samples=%d  sys=%.2f W  proc_cpu=%.1f%%  energy_impact=%.1f  battery %s -> %s (%s)\n", l,k,w/k,c/k,p/k,p0,p1,src }' "$csv"
echo "csv: $csv"
