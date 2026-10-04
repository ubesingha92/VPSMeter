# VPSMeter

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE.txt)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-4EAA25.svg)](vpsmeter.sh)

A fast, lightweight, and modern server & VPS benchmarking script for Linux and BSD systems.

VPSMeter is an enhanced fork of [`nench.sh`](https://github.com/n-st/nench) ("new bench.sh") by n-st, loosely based on the classic `freevps.us/bench.sh`. It evaluates hardware specifications, CPU performance (single-core and multi-core), disk I/O latency and sequential throughput, and worldwide network speed over IPv4 and IPv6.

---

## Quick Start

Run VPSMeter instantly using `curl`:

```bash
curl -sL https://raw.githubusercontent.com/ubesingha92/VPSMeter/master/vpsmeter.sh | bash
```

Or using `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/ubesingha92/VPSMeter/master/vpsmeter.sh | bash
```

### Local Execution & Logging

Clone and execute locally, redirecting output to both the terminal and a log file:

```bash
git clone https://github.com/ubesingha92/VPSMeter.git
cd VPSMeter
bash vpsmeter.sh 2>&1 | tee vpsmeter.log
```

> **Warning:** VPSMeter tests disk write throughput and network limits under full load for a few minutes. Avoid running it on production systems under critical traffic.

---

## What's New in This Fork

- **Maintained Global Speedtest Endpoints (5 x IPv4 + 5 x IPv6):**
  Uses modern, active POPs: Cloudflare CDN (Anycast) plus OVHcloud regional facilities in Singapore (SG), Roubaix (EU), Beauharnois (CA), and Hillsboro (US). The defunct 2019 endpoints (dead Softlayer domains, 404 Leaseweb files, Online.net, and Cachefly placeholder pages) have been removed.
- **Dual Bandwidth Units:**
  Every speed measurement reports both binary megabytes per second (`MiB/s`) and telecom megabits per second (`Mbps`) side-by-side (`1 MiB/s = 8.39 Mbps`).
- **Connection Latency (RTT) Reporting:**
  Network speedtests display the TCP connection latency in milliseconds alongside transfer speeds, explaining regional throughput differences.
- **RAM Sequential Speed Benchmark (Zero Dependencies):**
  Measures memory write and read bandwidth directly via Linux shared memory (`/dev/shm`) in `GiB/s` and `Gbps` without requiring external tools like `sysbench`.
- **Sequential Disk Read & Write:**
  Complements the 3-run sequential write test with a sequential read throughput measurement on the written block.
- **Hypervisor & TCP Congestion Control Detection:**
  Identifies virtualization platforms (KVM, LXC, VMware, Xen, OpenVZ, WSL, Baremetal) and the active TCP congestion control algorithm (e.g. `bbr`, `cubic`).
- **Clear Failure Diagnostics:**
  Unresponsive endpoints, connection timeouts without received data, and empty responses output explicit `FAILED` statuses instead of misleading `0.00 MiB/s` figures.
- **Multi-Core CPU Benchmark:**
  Runs a parallel multi-core SHA256 test across all available CPU threads in addition to the single-threaded SHA256, bzip2, and AES-256-CBC benchmarks.
- **Robust Hardware & Architecture Support:**
  Compatible with x86_64, aarch64 (ARM64), and BSD. Reads swap directly from `/proc/meminfo` without requiring root privileges (`swapon`), safely detects CPU frequency across cloud hypervisors, and falls back to `/tmp` if the working directory is read-only.
- **Endpoint Health Checking Companion:**
  Includes `check-endpoints.sh` to pre-validate all remote speedtest endpoints, featuring automatic host IPv6 connectivity detection.

---

## Example Output

Sample output from a 4-core Linux cloud VPS with dual-stack IPv4/IPv6 networking:

```text
-------------------------------------------------
 vpsmeter.sh v2026.10.04 -- https://github.com/ubesingha92/VPSMeter
 benchmark timestamp:    2026-10-04 12:00:00 UTC
-------------------------------------------------

Processor:    AMD EPYC 7763 64-Core Processor
CPU cores:    4
Frequency:    2445.404 MHz
RAM:          7.7 GiB
Swap:         2.0 GiB
Virtual:      KVM
TCP CC:       bbr
Kernel:       Linux 6.8.0-45-generic x86_64

Disks:
vda          80G   SSD

CPU: SHA256-hashing 500 MB
    1.820 seconds
CPU: bzip2-compressing 500 MB
    4.650 seconds
CPU: AES-encrypting 500 MB
    1.120 seconds
CPU: multi-core SHA256-hashing 500 MB x 4
    1.910 seconds

RAM: sequential access speed (/dev/shm)
    write speed:  12.45 GiB/s (99.6 Gbps)
    read speed:   18.20 GiB/s (145.6 Gbps)

ioping: seek rate
    min/avg/max/mdev = 82.4 us / 145.2 us / 4.12 ms / 98.6 us
ioping: sequential read speed
    generated 18.4 k requests in 5.00 s, 4.50 GiB, 3.68 k iops, 921.6 MiB/s

dd: sequential write and read speed
    1st run:    842.15 MiB/s (7064.5 Mbps)
    2nd run:    895.40 MiB/s (7511.6 Mbps)
    3rd run:    878.60 MiB/s (7370.7 Mbps)
    average:    872.05 MiB/s (7315.6 Mbps)
    read speed: 915.20 MiB/s (7677.3 Mbps)

IPv4 speedtests
    your IPv4:    198.51.100.xxxx

    Cloudflare CDN:       112.50 MiB/s (943.7 Mbps)   (lat: 1.2 ms)
    OVH SGP (SG):          42.10 MiB/s (353.2 Mbps)   (lat: 182.4 ms)
    OVH RBX (EU):         108.40 MiB/s (909.3 Mbps)   (lat: 14.5 ms)
    OVH BHS (CA):          68.75 MiB/s (576.8 Mbps)   (lat: 82.1 ms)
    OVH HIL (US):          54.20 MiB/s (454.7 Mbps)   (lat: 138.9 ms)

IPv6 speedtests
    your IPv6:    2001:db8:cafe:xxxx

    Cloudflare CDN:       114.20 MiB/s (958.0 Mbps)   (lat: 1.1 ms)
    OVH SGP (SG):          41.80 MiB/s (350.7 Mbps)   (lat: 181.2 ms)
    OVH RBX (EU):         110.15 MiB/s (924.0 Mbps)   (lat: 14.2 ms)
    OVH BHS (CA):          70.25 MiB/s (589.3 Mbps)   (lat: 81.8 ms)
    OVH HIL (US):          55.10 MiB/s (462.2 Mbps)   (lat: 138.5 ms)

Notes: far endpoints read slower than near ones (single stream + latency);
the near-region line is your real ceiling. 1 MiB/s = 8.39 Mbps.

-------------------------------------------------
```

---

## Benchmark Details & Methodology

### 1. System Specifications
- **Processor & Cores:** Detects CPU model name and physical/virtual core counts across Linux and BSD.
- **Frequency:** Pulls current CPU clock frequency from `/proc/cpuinfo`, sysfs scaling governors, or `sysctl`.
- **Memory & Swap:** Collects total RAM and Swap allocation directly from `/proc/meminfo` (Linux) or `sysctl`/`swapinfo` (BSD), functioning without root privileges.
- **Virtualization & TCP CC:** Identifies hypervisor platform (KVM, LXC, VMware, Xen, OpenVZ, WSL, Baremetal) and active TCP congestion control algorithm (e.g. BBR, Cubic).
- **Disks:** Summarizes non-loop block devices, reporting size and media type (SSD vs HDD) via `lsblk` or boot dmesg.

### 2. CPU Benchmarks
- **SHA256:** Hashes 500 MB of zero-fill data using `sha256sum` or `sha256`.
- **bzip2:** Compresses 500 MB of data using standard `bzip2`.
- **AES-256-CBC:** Encrypts 500 MB using OpenSSL's AES-256-CBC cipher.
- **Multi-Core SHA256:** Hashes `500 MB * N_cores` in parallel threads to evaluate multi-threaded scaling and thermal throttling.

### 3. RAM Access Benchmark
- **Sequential RAM Read & Write:** Writes and reads block data directly in Linux POSIX shared memory (`/dev/shm`), evaluating memory bandwidth in `GiB/s` and `Gbps` with zero external dependencies.

### 4. Storage Benchmarks
- **ioping Seek Rate (Latency):** Measures random read I/O response times (`ioping -DR -w 5 .`).
- **ioping Sequential Read:** Measures sustained read throughput and IOPS (`ioping -DRL -w 5 .`).
- **dd Sequential Write & Read:** Performs three 1 GB writes (`bs=64k count=16k conv=fdatasync`) to evaluate disk write speed, computes the average, and tests direct sequential read speed on the written block.

### 5. Network Speedtests
- Tests a 10-second download window against 5 geographically distributed endpoints for IPv4 and IPv6:
  - **Cloudflare Anycast CDN** (Global)
  - **OVH Singapore (SG)** (Asia-Pacific)
  - **OVH Roubaix (EU)** (Europe)
  - **OVH Beauharnois (CA)** (North America East)
  - **OVH Hillsboro (US)** (North America West)
- **Connection Latency (RTT):** Captures TCP handshake connect time to remote POPs, helping diagnose geographic latency limits.
- **Understanding single-stream metrics:** Speedtests run as single HTTP/HTTPS streams. Far-away endpoints will naturally report lower speeds due to TCP bandwidth-delay product (BDP) and network latency. The closest geographical endpoint represents your server's true connection ceiling.
- **Unit conversions:** `1 MiB/s = 1,048,576 bytes/s = 8.3886 Mbps (≈ 8.39 Mbps)`.

---

## Verifying Endpoints (`check-endpoints.sh`)

A dedicated verification utility is provided to ensure all upstream download files remain online and healthy:

```bash
bash check-endpoints.sh
```

### Options:
- `-4, --ipv4-only`: Only verify IPv4 endpoints (skips IPv6).
- `-6, --strict-ipv6`: Force testing IPv6 even if the local host lacks an IPv6 route.
- `-h, --help`: Display help and usage options.

### Sample Output:
```text
VPSMeter Endpoint Health Check
Target: ./vpsmeter.sh
IPv6:   Available on host
--------------------------------------------------------------------------------
[PASS] -4 https://speed.cloudflare.com/__down?bytes=50000000     -> HTTP 200,   50.00 MB in  0.5s
[PASS] -4 https://sin1-sgp.speedtest.network.ovh.net/files/100Mb.dat -> HTTP 200,  100.00 MB in  2.4s
[PASS] -4 https://lil1-rbx.speedtest.network.ovh.net/files/100Mb.dat -> HTTP 200,  100.00 MB in  0.9s
[PASS] -4 https://ymq1-bhs.speedtest.network.ovh.net/files/100Mb.dat -> HTTP 200,  100.00 MB in  1.4s
[PASS] -4 https://pdx1-hil.speedtest.network.ovh.net/files/100Mb.dat -> HTTP 200,  100.00 MB in  1.8s
[PASS] -6 https://speed.cloudflare.com/__down?bytes=50000000     -> HTTP 200,   50.00 MB in  0.5s
[PASS] -6 https://sin1-sgp.speedtest.network.ovh.net/files/100Mb.dat -> HTTP 200,  100.00 MB in  2.3s
[PASS] -6 https://lil1-rbx.speedtest.network.ovh.net/files/100Mb.dat -> HTTP 200,  100.00 MB in  0.9s
[PASS] -6 https://ymq1-bhs.speedtest.network.ovh.net/files/100Mb.dat -> HTTP 200,  100.00 MB in  1.5s
[PASS] -6 https://pdx1-hil.speedtest.network.ovh.net/files/100Mb.dat -> HTTP 200,  100.00 MB in  1.8s
--------------------------------------------------------------------------------
Summary: 10 total, 10 passed, 0 failed, 0 skipped
All active endpoints healthy!
```

---

## Dependencies

- **Core (required):** `bash`, `curl`, `coreutils` (GNU `dd`), `awk`.
- **Optional / Recommended:**
  - `ioping` (system package or bundled x86_64 binary)
  - `bzip2` (for bzip2 compression benchmark)
  - `openssl` (for AES benchmark)
  - `util-linux` (`lsblk`)

On Debian/Ubuntu:
```bash
sudo apt update && sudo apt install -y curl coreutils gawk bzip2 openssl ioping
```

---

## Credits & License

- Original script: `nench.sh` by [n-st](https://github.com/n-st/nench).
- Inspired by `bench.sh` from [freevps.us](https://freevps.us).
- Current fork maintained by [ubesingha92](https://github.com/ubesingha92/VPSMeter).
- Licensed under the [Apache License, Version 2.0](LICENSE.txt).
