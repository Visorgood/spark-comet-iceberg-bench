#!/usr/bin/env bash
# Records the machine and the settings the numbers depend on: OS, CPU, cores, memory,
# power source (macOS), Java, executor size. Read-only; writes out/$MACHINE_ID/machine.txt.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

mkdir -p "$OUT_DIR/$MACHINE_ID"
{
  echo "machine_id: $MACHINE_ID"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "os: $(uname -srm)"
  case "$(uname -s)" in
    Darwin)
      echo "macos: $(sw_vers -productVersion)"
      echo "cpu: $(sysctl -n machdep.cpu.brand_string)"
      echo "cores_physical: $(sysctl -n hw.physicalcpu)"
      echo "cores_performance: $(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo n/a)"
      echo "cores_efficiency: $(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null || echo n/a)"
      echo "memory_gb: $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))"
      echo "power: $(pmset -g ps | head -1 | sed "s/.*'\(.*\)'.*/\1/")"
      ;;
    Linux)
      echo "cpu: $(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo | sed 's/^ *//')"
      echo "cores_logical: $(nproc)"
      echo "memory_gb: $(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)"
      if [ -f /etc/os-release ]; then echo "distro: $(. /etc/os-release && echo "$PRETTY_NAME")"; fi
      ;;
  esac
  echo "java: $(java -version 2>&1 | head -1)"
  echo "executor: cores=$CORES heap=$EXEC_MEM offheap=$OFFHEAP driver=$DRIVER_MEM"
  echo "iterations: warmup=$WARMUP measured=$ITERATIONS"
} | tee "$OUT_DIR/$MACHINE_ID/machine.txt"
