#!/usr/bin/env bash

##########
# vpsmeter.sh (fork of nench.sh)
# ==============================
# current version at https://github.com/ubesingha92/VPSMeter
# - loosely based on the established freevps.us/bench.sh
# - includes CPU, RAM, disk, and ioping measurements
# - multi-core CPU test alongside single-threaded ones
# - RAM sequential read & write throughput via /dev/shm
# - disk sequential write & read speed via dd
# - reduced number of speedtests (10 x 50-100 MB), retaining useful European,
#   North American, Singapore and anycast POPs
# - network speedtests report speed and connection latency (RTT)
# - runs IPv6 speedtest by default (if the server has IPv6 connectivity)
# Run using `curl -sL https://raw.githubusercontent.com/ubesingha92/VPSMeter/master/vpsmeter.sh | bash`
# or `wget -qO- https://raw.githubusercontent.com/ubesingha92/VPSMeter/master/vpsmeter.sh | bash`
# - required packages: curl, coreutils (dd), awk
# - optional packages: ioping, bzip2, openssl, util-linux, procps
##########

command_exists()
{
    command -v "$1" > /dev/null 2>&1
}

Bps_to_MiBps()
{
    awk '
    BEGIN { ok = 0 }
    {
        val = $0 + 0
        if (val > 0) {
            printf "%.2f MiB/s (%.1f Mbps)\n", val / 1048576, val * 8 / 1000000
            ok = 1
        }
    }
    END {
        if (!ok) {
            print "0.00 MiB/s (0.0 Mbps)"
        }
    }'
}

Bps_to_GiBps()
{
    awk '
    BEGIN { ok = 0 }
    {
        val = $0 + 0
        if (val >= 1073741824) {
            printf "%.2f GiB/s (%.1f Gbps)\n", val / 1073741824, val * 8 / 1000000000
            ok = 1
        } else if (val > 0) {
            printf "%.2f MiB/s (%.1f Mbps)\n", val / 1048576, val * 8 / 1000000
            ok = 1
        }
    }
    END {
        if (!ok) {
            print "0.00 MiB/s (0.0 Mbps)"
        }
    }'
}

B_to_MiB()
{
    awk '
    BEGIN { ok = 0 }
    {
        val = $0 + 0
        if (val > 0) {
            printf "%.0f MiB\n", val / 1048576
            ok = 1
        }
    }
    END {
        if (!ok) {
            print "-"
        }
    }'
}

redact_ip()
{
    local ip
    ip=$(printf '%s' "$1" | tr -d ' \r\n\t')
    case "$ip" in
        *.*)
            printf '%s.xxxx\n' "$(printf '%s' "$ip" | cut -d . -f 1-3)"
            ;;
        *:*)
            printf '%s:xxxx\n' "$(printf '%s' "$ip" | cut -d : -f 1-3)"
            ;;
        *)
            printf '%s\n' "$ip"
            ;;
    esac
}

# Determine safe writable path for temporary dd file
TEST_DIR="."
if [ ! -w "." ]; then
    TEST_DIR="${TMPDIR:-/tmp}"
fi
TEST_FILE="${TEST_DIR}/vpsmeter_test_$$"
MEM_TEST_FILE="/dev/shm/vpsmeter_mem_$$"
CLEANUP_IOPING=0

cleanup()
{
    rm -f "$TEST_FILE" "$MEM_TEST_FILE" test_$$ 2>/dev/null
    if [ "$CLEANUP_IOPING" -eq 1 ] && [ ! -t 0 ]; then
        rm -f ioping.static 2>/dev/null
    fi
}
trap cleanup EXIT
trap 'cleanup; trap - INT; kill -s INT $$' INT
trap 'cleanup; trap - TERM; kill -s TERM $$' TERM

command_benchmark()
{
    local quiet=0
    if [ "$1" = "-q" ]
    then
        quiet=1
        shift
    fi

    local cmd="$1"
    if command_exists "$cmd"
    then
        ( time "$gnu_dd" if=/dev/zero bs=1M count=500 2> /dev/null | \
            "$@" > /dev/null ) 2>&1
    else
        if [ "$quiet" -eq 0 ]
        then
            printf '[command `%s` not found]\n' "$cmd"
        fi
        return 1
    fi
}

multicore_benchmark()
{
    local njobs="$1"
    shift
    local cmd="$1"
    command_exists "$cmd" || return 1
    ( time (
        local i=1
        while [ "$i" -le "$njobs" ]; do
            "$gnu_dd" if=/dev/zero bs=1M count=500 2> /dev/null | \
                "$@" > /dev/null &
            i=$((i + 1))
        done
        wait
    ) ) 2>&1
}

dd_benchmark()
{
    local keep="$1"
    # returns IO speed in B/s
    LC_ALL=C "$gnu_dd" if=/dev/zero of="$TEST_FILE" bs=64k count=16k conv=fdatasync 2>&1 | \
        awk -F, '
            {
                io=$NF
            }
            END {
                if (io ~ /TB\/s/)      { printf("%.0f\n", 1000*1000*1000*1000 * io) }
                else if (io ~ /GB\/s/) { printf("%.0f\n", 1000*1000*1000 * io) }
                else if (io ~ /MB\/s/) { printf("%.0f\n", 1000*1000 * io) }
                else if (io ~ /KB\/s/) { printf("%.0f\n", 1000 * io) }
                else if (io ~ /B\/s/)  { printf("%.0f\n", 1 * io) }
                else                   { printf("%.0f\n", 1 * io) }
            }'
    if [ "$keep" != "keep" ]; then
        rm -f "$TEST_FILE" 2>/dev/null
    fi
}

dd_read_benchmark()
{
    # returns IO read speed in B/s
    [ -f "$TEST_FILE" ] || return 1
    local out
    out=$(LC_ALL=C "$gnu_dd" if="$TEST_FILE" of=/dev/null bs=64k iflag=direct 2>&1)
    if printf '%s' "$out" | grep -qi "invalid argument"; then
        out=$(LC_ALL=C "$gnu_dd" if="$TEST_FILE" of=/dev/null bs=64k 2>&1)
    fi
    printf '%s\n' "$out" | awk -F, '
        {
            io=$NF
        }
        END {
            if (io ~ /TB\/s/)      { printf("%.0f\n", 1000*1000*1000*1000 * io) }
            else if (io ~ /GB\/s/) { printf("%.0f\n", 1000*1000*1000 * io) }
            else if (io ~ /MB\/s/) { printf("%.0f\n", 1000*1000 * io) }
            else if (io ~ /KB\/s/) { printf("%.0f\n", 1000 * io) }
            else if (io ~ /B\/s/)  { printf("%.0f\n", 1 * io) }
            else                   { printf("%.0f\n", 1 * io) }
        }'
    rm -f "$TEST_FILE" 2>/dev/null
}

calc_avg_io()
{
    awk -v a="$1" -v b="$2" -v c="$3" '
    BEGIN {
        sum = 0; count = 0
        if (a ~ /^[0-9]+$/ && a > 0) { sum += a; count++ }
        if (b ~ /^[0-9]+$/ && b > 0) { sum += b; count++ }
        if (c ~ /^[0-9]+$/ && c > 0) { sum += c; count++ }
        if (count > 0) { printf "%.0f\n", sum / count }
        else { print "0" }
    }'
}

ram_benchmark()
{
    [ -n "$gnu_dd" ] || return 1
    [ -d "/dev/shm" ] && [ -w "/dev/shm" ] || return 1

    local shm_avail_kb count out_w out_r
    shm_avail_kb=$(df -k /dev/shm 2>/dev/null | awk 'NR==2 {print $4}')
    case "$shm_avail_kb" in
        ''|*[!0-9]*) return 1 ;;
    esac

    if [ "$shm_avail_kb" -gt 600000 ]; then
        count=512
    elif [ "$shm_avail_kb" -gt 150000 ]; then
        count=128
    else
        return 1
    fi

    out_w=$(LC_ALL=C "$gnu_dd" if=/dev/zero of="$MEM_TEST_FILE" bs=1M count="$count" 2>&1)
    out_r=$(LC_ALL=C "$gnu_dd" if="$MEM_TEST_FILE" of=/dev/null bs=1M 2>&1)
    rm -f "$MEM_TEST_FILE" 2>/dev/null

    local w_rate r_rate
    w_rate=$(printf '%s\n' "$out_w" | awk -F, '
        { io=$NF }
        END {
            if (io ~ /TB\/s/)      { printf("%.0f\n", 1000*1000*1000*1000 * io) }
            else if (io ~ /GB\/s/) { printf("%.0f\n", 1000*1000*1000 * io) }
            else if (io ~ /MB\/s/) { printf("%.0f\n", 1000*1000 * io) }
            else if (io ~ /KB\/s/) { printf("%.0f\n", 1000 * io) }
            else if (io ~ /B\/s/)  { printf("%.0f\n", 1 * io) }
            else                   { printf("%.0f\n", 1 * io) }
        }')

    r_rate=$(printf '%s\n' "$out_r" | awk -F, '
        { io=$NF }
        END {
            if (io ~ /TB\/s/)      { printf("%.0f\n", 1000*1000*1000*1000 * io) }
            else if (io ~ /GB\/s/) { printf("%.0f\n", 1000*1000*1000 * io) }
            else if (io ~ /MB\/s/) { printf("%.0f\n", 1000*1000 * io) }
            else if (io ~ /KB\/s/) { printf("%.0f\n", 1000 * io) }
            else if (io ~ /B\/s/)  { printf("%.0f\n", 1 * io) }
            else                   { printf("%.0f\n", 1 * io) }
        }')

    printf '%s %s\n' "$w_rate" "$r_rate"
}

download_benchmark()
{
    local result code speed size time_connect
    result=$(curl -L --fail --max-time 10 --connect-timeout 5 -so /dev/null -w '%{speed_download} %{size_download} %{time_connect}' "$@")
    code=$?
    speed=${result%% *}
    local rest=${result#* }
    size=${rest%% *}
    time_connect=${rest##* }
    case "$size" in
        ''|*[!0-9]*) size=0 ;;
    esac

    case "$code" in
        0|28)
            if [ "$size" -gt 100000 ]; then
                local spd_fmt lat_fmt
                spd_fmt=$(printf '%s\n' "$speed" | Bps_to_MiBps | tr -d '\r\n')
                lat_fmt=$(awk -v t="$time_connect" 'BEGIN {
                    val = t + 0
                    if (val > 0) printf "%.1f ms", val * 1000
                    else print "-"
                }')
                printf '%-26s (lat: %s)\n' "$spd_fmt" "$lat_fmt"
            else
                printf 'FAILED (no data received)\n'
            fi
            ;;
        *)
            printf 'FAILED (curl exit %s)\n' "$code"
            ;;
    esac
}

if ! command_exists curl
then
    printf '%s\n' 'This script requires curl, but it could not be found.' 1>&2
    exit 1
fi

if command_exists gdd
then
    gnu_dd='gdd'
elif command_exists dd
then
    gnu_dd='dd'
else
    printf '%s\n' 'This script requires dd, but it could not be found.' 1>&2
    exit 1
fi

if ! "$gnu_dd" --version > /dev/null 2>&1
then
    printf '%s\n' 'It seems your system only has a non-GNU version of dd.'
    printf '%s\n' 'dd write tests disabled.'
    gnu_dd=''
fi

printf '%s\n' '-------------------------------------------------'
printf ' vpsmeter.sh v2026.10.04 -- https://github.com/ubesingha92/VPSMeter\n'
date -u '+ benchmark timestamp:    %F %T UTC'
printf '%s\n' '-------------------------------------------------'

printf '\n'

# ioping setup
ioping_cmd=""
if command_exists ioping
then
    ioping_cmd="ioping"
elif [ -x "./ioping.static" ] && ./ioping.static -v > /dev/null 2>&1
then
    ioping_cmd="./ioping.static"
else
    local_os=$(uname -s 2>/dev/null)
    local_arch=$(uname -m 2>/dev/null)
    if [ "$local_os" = "Linux" ] && [ "$local_arch" = "x86_64" ]
    then
        if curl -fsSL --max-time 10 -o ioping.static https://wget.racing/ioping.static 2>/dev/null || \
           curl -fsSL --max-time 10 -o ioping.static http://wget.racing/ioping.static 2>/dev/null
        then
            chmod +x ioping.static 2>/dev/null
            if ./ioping.static -v > /dev/null 2>&1
            then
                ioping_cmd="./ioping.static"
                CLEANUP_IOPING=1
            else
                rm -f ioping.static 2>/dev/null
            fi
        fi
    fi
fi

# Basic info
if [ "$(uname)" = "Linux" ]
then
    cpu_name=$(awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo 2>/dev/null | sed 's/^[ \t]*//;s/[ \t]*$//')
    if [ -z "$cpu_name" ]; then
        cpu_name=$(lscpu 2>/dev/null | awk -F: '/Model name/ {print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
    fi
    [ -z "$cpu_name" ] && cpu_name="$(uname -m)"
    printf 'Processor:    %s\n' "$cpu_name"

    cpu_cores=$(awk -F: '/^processor/ {core++} END {print core}' /proc/cpuinfo 2>/dev/null)
    [ -z "$cpu_cores" ] && cpu_cores=$(nproc 2>/dev/null || echo 1)
    printf 'CPU cores:    %s\n' "$cpu_cores"

    cpu_freq=$(awk -F: ' /cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo 2>/dev/null | sed 's/^[ \t]*//;s/[ \t]*$//')
    if [ -n "$cpu_freq" ]; then
        printf 'Frequency:    %s MHz\n' "$cpu_freq"
    elif [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
        awk '{ printf "Frequency:    %.2f MHz\n", $1 / 1000 }' /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null
    else
        printf 'Frequency:    -\n'
    fi

    ram_info=$(free -h 2>/dev/null | awk 'NR==2 {print $2}')
    if [ -z "$ram_info" ] && [ -r /proc/meminfo ]; then
        ram_info=$(awk '/MemTotal/ { printf "%.1f GiB\n", $2 / 1048576 }' /proc/meminfo)
    fi
    printf 'RAM:          %s\n' "${ram_info:--}"

    swap_total_kb=0
    if [ -r /proc/meminfo ]; then
        swap_total_kb=$(awk '/SwapTotal/ {print $2}' /proc/meminfo 2>/dev/null)
    fi
    if [ -n "$swap_total_kb" ] && [ "$swap_total_kb" -gt 0 ] 2>/dev/null; then
        swap_info=$(free -h 2>/dev/null | awk '/Swap/ {print $2}')
        if [ -z "$swap_info" ]; then
            swap_info=$(awk -v kb="$swap_total_kb" 'BEGIN { printf "%.1f GiB\n", kb / 1048576 }')
        fi
        printf 'Swap:         %s\n' "$swap_info"
    else
        printf 'Swap:         -\n'
    fi

    virt=""
    if command_exists systemd-detect-virt; then
        virt=$(systemd-detect-virt 2>/dev/null)
    fi
    if [ -z "$virt" ] || [ "$virt" = "none" ]; then
        if [ -r /sys/class/dmi/id/product_name ]; then
            virt=$(tr -d '\0' < /sys/class/dmi/id/product_name 2>/dev/null | sed 's/^[ \t]*//;s/[ \t]*$//')
        elif [ -r /sys/class/dmi/id/sys_vendor ]; then
            virt=$(tr -d '\0' < /sys/class/dmi/id/sys_vendor 2>/dev/null | sed 's/^[ \t]*//;s/[ \t]*$//')
        fi
    fi
    if [ -z "$virt" ] || [ "$virt" = "none" ]; then
        if grep -qiE 'qemu|kvm' /proc/cpuinfo 2>/dev/null; then
            virt="KVM"
        elif grep -qi 'vmware' /proc/cpuinfo 2>/dev/null; then
            virt="VMware"
        elif grep -qi 'xen' /proc/cpuinfo 2>/dev/null; then
            virt="Xen"
        elif [ -f /proc/user_beancounters ]; then
            virt="OpenVZ"
        fi
    fi
    case "$virt" in
        kvm*|*KVM*) virt="KVM" ;;
        qemu*|*QEMU*) virt="QEMU" ;;
        vmware*|*VMware*) virt="VMware" ;;
        xen*|*Xen*) virt="Xen" ;;
        lxc*|*LXC*) virt="LXC" ;;
        docker*|*Docker*) virt="Docker" ;;
        openvz*|*OpenVZ*) virt="OpenVZ" ;;
        oracle*|virtualbox*|*VirtualBox*) virt="VirtualBox" ;;
        microsoft*|wsl*|*WSL*) virt="WSL / Hyper-V" ;;
        none|""|*Standard*|*Default*) virt="Dedicated / Baremetal" ;;
    esac
    printf 'Virtual:      %s\n' "$virt"

    tcp_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    [ -n "$tcp_cc" ] && printf 'TCP CC:       %s\n' "$tcp_cc"
else
    # FreeBSD and other BSDs
    printf 'Processor:    '
    sysctl -n hw.model 2>/dev/null || uname -m
    printf 'CPU cores:    '
    sysctl -n hw.ncpu 2>/dev/null || echo 1
    printf 'Frequency:    '
    sysctl -n dev.cpu.0.freq 2>/dev/null | awk '{print $1 " MHz"}' || \
        grep -Eo -- '[0-9.]+-MHz' /var/run/dmesg.boot 2>/dev/null | tr -- '-' ' ' | sort -u || echo '-'
    printf 'RAM:          '
    sysctl -n hw.physmem 2>/dev/null | B_to_MiB

    if [ "$(swapinfo 2>/dev/null | wc -l)" -lt 2 ]
    then
        printf 'Swap:         -\n'
    else
        printf 'Swap:         '
        swapinfo -k 2>/dev/null | awk 'NR>1 && $1!="Total" {total+=$2} END {print total*1024}' | B_to_MiB
    fi

    virt=$(sysctl -n kern.vm_guest 2>/dev/null)
    case "$virt" in
        none|"") virt="Dedicated / Baremetal" ;;
        kvm) virt="KVM" ;;
        xen) virt="Xen" ;;
        vmware) virt="VMware" ;;
        bhyve) virt="Bhyve" ;;
    esac
    printf 'Virtual:      %s\n' "$virt"

    tcp_cc=$(sysctl -n net.inet.tcp.cc.algorithm 2>/dev/null)
    [ -n "$tcp_cc" ] && printf 'TCP CC:       %s\n' "$tcp_cc"
fi
printf 'Kernel:       '
uname -s -r -m

printf '\n'

printf 'Disks:\n'
if command_exists lsblk && [ -n "$(lsblk 2>/dev/null)" ]
then
    lsblk --nodeps --noheadings --output NAME,SIZE,ROTA --exclude 1,2,7,11 2>/dev/null | sort | \
        awk '{ if ($3 == 0) { type="SSD" } else if ($3 == 1) { type="HDD" } else { type="-" }; printf("%-8s %8s  %s\n", $1, $2, type) }'
elif [ -r "/var/run/dmesg.boot" ]
then
    awk '/(ad|ada|da|vtblk)[0-9]+: [0-9]+.B/ { printf("%-8s %8.1f GiB\n", $1, $2/1024) }' /var/run/dmesg.boot | sort -u
elif command_exists df
then
    df -h --output=source,fstype,size 2>/dev/null | awk 'NR == 1 || /^\/dev/'
else
    printf '[ no data available ]\n'
fi

printf '\n'

# CPU tests
export TIMEFORMAT='%3R seconds'

printf 'CPU: SHA256-hashing 500 MB\n    '
command_benchmark -q sha256sum || command_benchmark -q sha256 || printf '[no SHA256 command found]\n'

printf 'CPU: bzip2-compressing 500 MB\n    '
command_benchmark bzip2

printf 'CPU: AES-encrypting 500 MB\n    '
command_benchmark openssl enc -e -aes-256-cbc -pass pass:12345678 | sed '/^\*\*\* WARNING : deprecated key derivation used\.$/d;/^Using -iter or -pbkdf2 would be better\.$/d'

cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
case "$cores" in
    ''|*[!0-9]*) cores=1 ;;
esac
[ "$cores" -lt 1 ] && cores=1

printf 'CPU: multi-core SHA256-hashing 500 MB x %s\n    ' "$cores"
multicore_benchmark "$cores" sha256sum || multicore_benchmark "$cores" sha256 || printf '[no SHA256 command found]\n'

printf '\n'

# RAM speed test (/dev/shm)
printf 'RAM: sequential access speed (/dev/shm)\n'
if [ -z "$gnu_dd" ]; then
    printf '    %s\n' '[disabled due to missing GNU dd]'
else
    ram_speeds=$(ram_benchmark)
    if [ -n "$ram_speeds" ]; then
        ram_w=${ram_speeds%% *}
        ram_r=${ram_speeds##* }
        printf '    write speed:  %s\n' "$(printf '%s\n' "$ram_w" | Bps_to_GiBps)"
        printf '    read speed:   %s\n' "$(printf '%s\n' "$ram_r" | Bps_to_GiBps)"
    else
        printf '    %s\n' '[not available (no /dev/shm or low memory)]'
    fi
fi

printf '\n'

# ioping
printf 'ioping: seek rate\n    '
if [ -n "$ioping_cmd" ]; then
    "$ioping_cmd" -DR -w 5 . 2>/dev/null | tail -n 1
else
    printf '[ioping not available]\n'
fi

printf 'ioping: sequential read speed\n    '
if [ -n "$ioping_cmd" ]; then
    "$ioping_cmd" -DRL -w 5 . 2>/dev/null | tail -n 2 | head -n 1
else
    printf '[ioping not available]\n'
fi

printf '\n'

# dd disk test
printf 'dd: sequential write and read speed\n'

if [ -z "$gnu_dd" ]
then
    printf '    %s\n' '[disabled due to missing GNU dd]'
else
    io1=$( dd_benchmark )
    printf '    1st run:    %s\n' "$(printf '%s\n' "$io1" | Bps_to_MiBps)"

    io2=$( dd_benchmark )
    printf '    2nd run:    %s\n' "$(printf '%s\n' "$io2" | Bps_to_MiBps)"

    io3=$( dd_benchmark keep )
    printf '    3rd run:    %s\n' "$(printf '%s\n' "$io3" | Bps_to_MiBps)"

    ioavg=$( calc_avg_io "$io1" "$io2" "$io3" )
    printf '    average:    %s\n' "$(printf '%s\n' "$ioavg" | Bps_to_MiBps)"

    iord=$( dd_read_benchmark )
    if [ -n "$iord" ] && [ "$iord" -gt 0 ] 2>/dev/null; then
        printf '    read speed: %s\n' "$(printf '%s\n' "$iord" | Bps_to_MiBps)"
    fi
fi

printf '\n'

# Network speedtests

ipv4=$(curl -4 -fsSL --max-time 5 https://icanhazip.com 2>/dev/null || \
       curl -4 -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || \
       curl -4 -fsSL --max-time 5 http://icanhazip.com 2>/dev/null | tr -d ' \r\n\t')

if [ -n "$ipv4" ]
then
    printf 'IPv4 speedtests\n'
    printf '    your IPv4:    %s\n' "$(redact_ip "$ipv4")"
    printf '\n'

    printf '    Cloudflare CDN:       '
    download_benchmark -4 https://speed.cloudflare.com/__down?bytes=50000000

    printf '    OVH SGP (SG):         '
    download_benchmark -4 https://sin1-sgp.speedtest.network.ovh.net/files/100Mb.dat

    printf '    OVH RBX (EU):         '
    download_benchmark -4 https://lil1-rbx.speedtest.network.ovh.net/files/100Mb.dat

    printf '    OVH BHS (CA):         '
    download_benchmark -4 https://ymq1-bhs.speedtest.network.ovh.net/files/100Mb.dat

    printf '    OVH HIL (US):         '
    download_benchmark -4 https://pdx1-hil.speedtest.network.ovh.net/files/100Mb.dat

else
    printf 'No IPv4 connectivity detected\n'
fi

printf '\n'

ipv6=$(curl -6 -fsSL --max-time 5 https://icanhazip.com 2>/dev/null || \
       curl -6 -fsSL --max-time 5 https://api6.ipify.org 2>/dev/null || \
       curl -6 -fsSL --max-time 5 http://icanhazip.com 2>/dev/null | tr -d ' \r\n\t')

if [ -n "$ipv6" ]
then
    printf 'IPv6 speedtests\n'
    printf '    your IPv6:    %s\n' "$(redact_ip "$ipv6")"
    printf '\n'

    printf '    Cloudflare CDN:       '
    download_benchmark -6 https://speed.cloudflare.com/__down?bytes=50000000

    printf '    OVH SGP (SG):         '
    download_benchmark -6 https://sin1-sgp.speedtest.network.ovh.net/files/100Mb.dat

    printf '    OVH RBX (EU):         '
    download_benchmark -6 https://lil1-rbx.speedtest.network.ovh.net/files/100Mb.dat

    printf '    OVH BHS (CA):         '
    download_benchmark -6 https://ymq1-bhs.speedtest.network.ovh.net/files/100Mb.dat

    printf '    OVH HIL (US):         '
    download_benchmark -6 https://pdx1-hil.speedtest.network.ovh.net/files/100Mb.dat

else
    printf 'No IPv6 connectivity detected\n'
fi

printf '\n'
printf 'Notes: far endpoints read slower than near ones (single stream + latency);\n'
printf 'the near-region line is your real ceiling. 1 MiB/s = 8.39 Mbps.\n'
printf '\n'
printf '%s\n' '-------------------------------------------------'
