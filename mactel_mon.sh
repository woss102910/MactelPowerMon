#!/bin/bash

SAMPLES=5

total_watts=0
total_idle_watts=0
total_ram_used=0
total_ram_cache=0
total_ram_free=0
total_cpu=0
total_batt_minutes=0
total_batt_idle_minutes=0
total_temp=0

GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[0;33m"
NC="\033[0m"

SCRIPT_PATH="$(realpath "$0")"
RAM_TOTAL=$(gawk -v r=$(sysctl -n hw.memsize) 'BEGIN{print r/1024/1024}')

is_ac_connected() {
    ioreg -rn AppleSmartBattery | grep -q '"ExternalConnected" = Yes'
}

echo "Starting sampling for $SAMPLES samples (~7s each)..."

for ((i=1;i<=SAMPLES;i++)); do
    echo -e "${GREEN}--- Sample $i ---${NC}"

    # 🔹 Detect AC power
    if is_ac_connected; then
        MODE="AC"
    else
        MODE="BATTERY"
    fi

    # 🔹 powermetrics (only consumption)
    pm_watts=$(sudo powermetrics smc -n 1 2>/dev/null \
        | gawk '/\(CPUs\+GT\+SA\)/ {match($0,/([0-9]+\.[0-9]+)/,a); print a[1]}')
    pm_watts=${pm_watts:-0}

    # 🔹 CPU/GPU temperature with osx-cpu-temp
    temp=$(osx-cpu-temp | sed 's/°C//')
    total_temp=$(gawk -v t=$total_temp -v x=$temp 'BEGIN{print t+x}')    

    # 🔹 ioreg (battery info)
    read volt amp time_rem <<< $(ioreg -rn AppleSmartBattery | gawk '
        /LegacyBatteryInfo/ {
            match($0, /"Voltage"=([0-9]+)/, v)
            match($0, /"Amperage"=([0-9]+)/, a)
        }
        /TimeRemaining/ {
            match($0, /= ([0-9]+)/, t)
        }
        END {
            amp=a[1]+0
            volt=v[1]+0
            time=t[1]+0
            if(amp>9223372036854775807) amp-=18446744073709551616
            print volt, (amp<0?-amp:amp), time
        }
    ')

    ioreg_watts=$(gawk -v v=$volt -v a=$amp 'BEGIN{printf "%.2f",v*a/1000000}')

    # 🔹 Combined consumption weighted
    if [[ "$MODE" == "BATTERY" && -n "$pm_watts" ]]; then
        watts=$(gawk -v p=$pm_watts -v i=$ioreg_watts 'BEGIN{
            # 60% powermetrics + 40% ioreg
            printf "%.2f",i*0.4+p*0.6
        }')
    else
        watts=$pm_watts
    fi

    total_watts=$(gawk -v t=$total_watts -v w=$watts 'BEGIN{print t+w}')

    # 🔹 RAM usage
    read used cache free <<< $(vm_stat | gawk '
        BEGIN{ps=4096}
        /Pages wired down/ {w=$4}
        /Pages active/ {a=$3}
        /Pages inactive/ {i=$3}
        /Pages free/ {f=$3}
        END{
            print (w+a)*ps/1024/1024, i*ps/1024/1024, f*ps/1024/1024
        }')

    total_ram_used=$(gawk -v t=$total_ram_used -v u=$used 'BEGIN{print t+u}')
    total_ram_cache=$(gawk -v t=$total_ram_cache -v c=$cache 'BEGIN{print t+c}')
    total_ram_free=$(gawk -v t=$total_ram_free -v f=$free 'BEGIN{print t+f}')

    echo "Power mode: $MODE"
    echo "Base consumption (powermetrics): ${pm_watts} W"
    [[ "$MODE" == "BATTERY" ]] && echo "Combined consumption: ${watts} W"
    echo "RAM used: $used MB, RAM cache: $cache MB, RAM free: $free MB"

    # 🔹 Processes
    PROCESSES=$(ps -axo pid,%cpu,command | gawk -v SPATH="$SCRIPT_PATH" '
    NR>1 {
        pid=$1; cpu=$2
        cmd=""
        for(i=3;i<=NF;i++) cmd=cmd $i " "
        sub(/[ \t]+$/, "", cmd)

        type="REAL"
        if (cmd ~ SPATH ||
            cmd ~ /^ps / || cmd ~ /^awk / || cmd ~ /^gawk / ||
            cmd ~ /^sort / || cmd ~ /^head / || cmd ~ /^sleep / ||
            cmd ~ /^ioreg / || cmd ~ /^powermetrics / || cmd ~ /^vm_stat /)
            type="INTERNAL"

        print pid "|" cpu "|" cmd "|" type
    }')

    REAL=$(echo "$PROCESSES" | gawk -F"|" '$4=="REAL"')
    INTERNAL=$(echo "$PROCESSES" | gawk -F"|" '$4=="INTERNAL"')

    cpu_total=$(echo "$REAL" | gawk -F"|" '{s+=$2} END{printf "%.2f",s}')
    total_cpu=$(gawk -v t=$total_cpu -v c=$cpu_total 'BEGIN{print t+c}')

    # 🔹 Top 5 real processes
    TOP5_REAL=$(echo "$REAL" | sort -t"|" -k2 -nr | head -5)
    cpu_top5=$(echo "$TOP5_REAL" | gawk -F"|" '{s+=$2} END{printf "%.2f",s}')  

    # 🔹 More realistic idle model
    idle=$(gawk -v p=$watts -v t=$cpu_total -v h=$cpu_top5 '
    BEGIN{
        dyn = p * 0.6         # dynamic consumption portion
        base = p - dyn
        if(t>0) dyn_idle = dyn * ((t - h) / t)
        else dyn_idle = dyn
        idle = base + dyn_idle
        if(idle < 0) idle = 0
        printf "%.2f", idle
    }')

    # 🔹 Battery estimation
    if [[ "$MODE" == "BATTERY" && $ioreg_watts > 0 ]]; then
        batt_minutes=$(gawk -v time=$time_rem -v w=$ioreg_watts -v c=$watts 'BEGIN{
            if(c>0) printf "%.0f",time*(w/c)
            else print 0
        }')
        batt_idle_minutes=$(gawk -v time=$time_rem -v w=$ioreg_watts -v c=$idle 'BEGIN{
            if(c>0) printf "%.0f",time*(w/c)
            else print 0
        }')
        echo "Estimated battery time: $batt_minutes min"
        total_batt_minutes=$(gawk -v t=$total_batt_minutes -v b=$batt_minutes 'BEGIN{print t+b}')
        total_batt_idle_minutes=$(gawk -v t=$total_batt_idle_minutes -v b=$batt_idle_minutes 'BEGIN{print t+b}')
    fi

    # 🔹 Show top 10 real processes with estimated W
    echo "Top 10 processes by CPU (estimated consumption in W):"
    printf "%-8s %-6s %-120s %-6s\n" PID %CPU COMMAND WATTS
    echo "$REAL" | sort -t"|" -k2 -nr | head -10 | while IFS="|" read pid cpu cmd type; do
        watt=$(gawk -v p=$cpu -v t=$cpu_total -v w=$watts 'BEGIN{printf "%.2f", (p/t)*w}')
        printf "%-8s %-6s %-120s %-6s\n" "$pid" "$cpu" "$cmd" "$watt"
    done

    total_idle_watts=$(gawk -v t=$total_idle_watts -v i=$idle 'BEGIN{print t+i}')

    echo -e "${GREEN}Estimated ideal idle (after closing top 5): $idle W${NC}"
    [[ "$MODE" == "BATTERY" ]] && echo "Estimated battery time after closing top 5: $batt_idle_minutes min"
    echo "CPU/GPU Temperature: ${temp} °C"

    sleep 7
done

# 🔹 Averages
avg_watts=$(gawk -v t=$total_watts -v n=$SAMPLES 'BEGIN{printf "%.2f",t/n}')
avg_idle=$(gawk -v t=$total_idle_watts -v n=$SAMPLES 'BEGIN{printf "%.2f",t/n}')
avg_cpu=$(gawk -v t=$total_cpu -v n=$SAMPLES 'BEGIN{printf "%.2f",t/n}')
avg_temp=$(gawk -v t=$total_temp -v n=$SAMPLES 'BEGIN{printf "%.2f",t/n}')
avg_batt=$(gawk -v t=$total_batt_minutes -v n=$SAMPLES 'BEGIN{printf "%.0f",t/n}')
avg_batt_idle=$(gawk -v t=$total_batt_idle_minutes -v n=$SAMPLES 'BEGIN{printf "%.0f",t/n}')
avg_ram_used=$(gawk -v t=$total_ram_used -v n=$SAMPLES 'BEGIN{printf "%.0f",t/n}')
avg_ram_cache=$(gawk -v t=$total_ram_cache -v n=$SAMPLES 'BEGIN{printf "%.0f",t/n}')
avg_ram_free=$(gawk -v t=$total_ram_free -v n=$SAMPLES 'BEGIN{printf "%.0f",t/n}')

echo -e "${CYAN}-----------------------------------${NC}"
echo -e "${CYAN}Averages over $SAMPLES samples:${NC}"
echo "Total CPU usage average: $avg_cpu %"
echo "Base consumption average: $avg_watts W"
echo "Idle average: $avg_idle W"
echo "CPU/GPU Temperature average: $avg_temp °C"
echo "RAM used average: $avg_ram_used MB"
echo "RAM cache average: $avg_ram_cache MB"
echo "RAM free average: $avg_ram_free MB"
[[ "$MODE" == "BATTERY" ]] && echo "Estimated battery time average: $avg_batt min"
[[ "$MODE" == "BATTERY" ]] && echo "Estimated battery time after closing top 5 average: $avg_batt_idle min"
