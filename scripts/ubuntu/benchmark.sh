#!/bin/bash
# =============================================================================
# Proxmox benchmark script — Ubuntu VM vs LXC (Ryzen 9 7950X)
# Usage:
#   ./benchmark.sh vm           — run as the VM
#   ./benchmark.sh lxc          — run as the LXC container
#   ./benchmark.sh vm  --verbose — show full output from all tools
#   ./benchmark.sh lxc --verbose — show full output from all tools
# =============================================================================

set -e

# --- Argument check ----------------------------------------------------------
if [[ "$1" != "vm" && "$1" != "lxc" ]]; then
    echo "Usage: $0 [vm|lxc] [--verbose]"
    exit 1
fi

ENV="$1"
VERBOSE=false
if [[ "$2" == "--verbose" || "$2" == "-v" ]]; then
    VERBOSE=true
fi
RESULTS_DIR="$HOME/results/$ENV"
IPERF_SERVER="192.168.1.170"   # <-- change to your Proxmox host IP if different

# --- Colors ------------------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()   { echo -e "${GREEN}[DONE]${NC}  $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }

# =============================================================================
# STEP 1 — Create results folder
# =============================================================================
log "Creating results folder: $RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
ok "Folder ready: $RESULTS_DIR"

# =============================================================================
# STEP 2 — Install tools
# =============================================================================
log "Updating package index..."
if $VERBOSE; then
    apt-get update
else
    apt-get update -qq
fi

log "Installing sysbench, fio, iperf3..."
if $VERBOSE; then
    apt-get install -y sysbench fio iperf3 make gcc perl git
else
    apt-get install -y sysbench fio iperf3 make gcc perl git > /dev/null
fi
ok "sysbench, fio, iperf3 installed"

# UnixBench
if [[ ! -d "$HOME/byte-unixbench" ]]; then
    log "Cloning UnixBench..."
    if $VERBOSE; then
        git clone https://github.com/kdlucas/byte-unixbench.git "$HOME/byte-unixbench"
    else
        git clone -q https://github.com/kdlucas/byte-unixbench.git "$HOME/byte-unixbench"
    fi
    ok "UnixBench cloned"
else
    ok "UnixBench already present, skipping clone"
fi

# =============================================================================
# STEP 3 — sysbench CPU
# =============================================================================
# sysbench helper: tee to terminal in verbose, save to file only otherwise
sb_run() {
    local outfile="$1"; shift
    if $VERBOSE; then
        sysbench "$@" 2>&1 | tee "$outfile"
    else
        sysbench "$@" > "$outfile" 2>&1
    fi
}

log "Running sysbench CPU single-thread (30s)..."
sb_run "$RESULTS_DIR/cpu_single.txt" cpu --threads=1 --time=30 run
ok "cpu_single.txt saved"

log "Running sysbench CPU multi-thread 32 threads (30s)..."
sb_run "$RESULTS_DIR/cpu_multi.txt" cpu --threads=32 --time=30 run
ok "cpu_multi.txt saved"

# =============================================================================
# STEP 4 — sysbench memory
# =============================================================================
log "Running sysbench memory sequential..."
sb_run "$RESULTS_DIR/mem_seq.txt" memory --memory-block-size=1M --memory-total-size=100G --threads=1 run
ok "mem_seq.txt saved"

log "Running sysbench memory random..."
sb_run "$RESULTS_DIR/mem_rnd.txt" memory --memory-block-size=4K --memory-total-size=10G --memory-access-mode=rnd --threads=1 run
ok "mem_rnd.txt saved"

# =============================================================================
# STEP 5 — fio disk I/O
# =============================================================================
FIO_DIR="$RESULTS_DIR/fio_tmp"
mkdir -p "$FIO_DIR"

# fio output flag: tee to terminal only in verbose mode
fio_run() {
    local label="$1"; shift
    if $VERBOSE; then
        fio "$@" --output-format=normal 2>&1 | tee "$RESULTS_DIR/$label.txt"
    else
        fio "$@" --output="$RESULTS_DIR/$label.txt"
    fi
}

log "Running fio sequential read (30s)..."
fio_run fio_seq_read --name=seq_read --rw=read --bs=1M --size=4G --direct=1 \
    --numjobs=1 --runtime=30 --directory="$FIO_DIR"
ok "fio_seq_read.txt saved"

log "Running fio sequential write (30s)..."
fio_run fio_seq_write --name=seq_write --rw=write --bs=1M --size=4G --direct=1 \
    --numjobs=1 --runtime=30 --directory="$FIO_DIR"
ok "fio_seq_write.txt saved"

log "Running fio random read 4K (30s)..."
fio_run fio_rnd_read --name=rnd_read --rw=randread --bs=4K --size=4G --direct=1 \
    --numjobs=4 --runtime=30 --directory="$FIO_DIR"
ok "fio_rnd_read.txt saved"

log "Running fio random write 4K (30s)..."
fio_run fio_rnd_write --name=rnd_write --rw=randwrite --bs=4K --size=4G --direct=1 \
    --numjobs=4 --runtime=30 --directory="$FIO_DIR"
ok "fio_rnd_write.txt saved"

log "Cleaning up fio temp files..."
rm -rf "$FIO_DIR"

# =============================================================================
# STEP 6 — iperf3 network
# =============================================================================
log "Running iperf3 TCP test (30s) — make sure iperf3 -s is running on $IPERF_SERVER"
if $VERBOSE; then
    iperf3 -c "$IPERF_SERVER" -t 30 -P 4 2>&1 | tee "$RESULTS_DIR/net_tcp.txt" && ok "net_tcp.txt saved" || warn "iperf3 TCP test failed — is the server running on $IPERF_SERVER? Skipping UDP."
else
    if iperf3 -c "$IPERF_SERVER" -t 30 -P 4 > "$RESULTS_DIR/net_tcp.txt" 2>&1; then
        ok "net_tcp.txt saved"
    else
        warn "iperf3 TCP test failed — is the server running on $IPERF_SERVER? Skipping UDP."
    fi
fi

if grep -q "sender" "$RESULTS_DIR/net_tcp.txt" 2>/dev/null; then
    log "Running iperf3 UDP test (30s)..."
    if $VERBOSE; then
        iperf3 -c "$IPERF_SERVER" -t 30 -u -b 10G 2>&1 | tee "$RESULTS_DIR/net_udp.txt"
    else
        iperf3 -c "$IPERF_SERVER" -t 30 -u -b 10G > "$RESULTS_DIR/net_udp.txt" 2>&1
    fi
    ok "net_udp.txt saved"
fi

# =============================================================================
# STEP 7 — UnixBench
# =============================================================================
log "Building and running UnixBench (this takes ~10-15 minutes)..."
cd "$HOME/byte-unixbench/UnixBench"
./Run 2>&1 | tee "$RESULTS_DIR/unixbench_output.txt"
ok "unixbench_output.txt saved"
cd "$HOME"

# =============================================================================
# STEP 8 — Extract key metrics summary
# =============================================================================
SUMMARY="$RESULTS_DIR/summary.txt"
log "Extracting key metrics into summary.txt..."

{
    echo "=============================================="
    echo " Benchmark summary — $ENV — $(date)"
    echo "=============================================="

    echo ""
    echo "--- sysbench CPU ---"
    grep 'events per second' "$RESULTS_DIR/cpu_single.txt" | sed 's/^/  single-thread: /'
    grep 'events per second' "$RESULTS_DIR/cpu_multi.txt"  | sed 's/^/  multi-thread:  /'

    echo ""
    echo "--- sysbench memory ---"
    grep 'transferred' "$RESULTS_DIR/mem_seq.txt" | sed 's/^/  sequential: /'
    grep 'transferred' "$RESULTS_DIR/mem_rnd.txt" | sed 's/^/  random:     /'

    echo ""
    echo "--- fio disk I/O ---"
    grep -E 'READ:|WRITE:' "$RESULTS_DIR/fio_seq_read.txt"  | sed 's/^/  seq read:   /'
    grep -E 'READ:|WRITE:' "$RESULTS_DIR/fio_seq_write.txt" | sed 's/^/  seq write:  /'
    grep -E 'READ:|WRITE:' "$RESULTS_DIR/fio_rnd_read.txt"  | sed 's/^/  rnd read:   /'
    grep -E 'READ:|WRITE:' "$RESULTS_DIR/fio_rnd_write.txt" | sed 's/^/  rnd write:  /'

    echo ""
    echo "--- iperf3 network ---"
    grep -E 'sender|receiver' "$RESULTS_DIR/net_tcp.txt" 2>/dev/null | sed 's/^/  tcp: /' || echo "  tcp: not available"
    grep -E 'sender|receiver' "$RESULTS_DIR/net_udp.txt" 2>/dev/null | sed 's/^/  udp: /' || echo "  udp: not available"

    echo ""
    echo "--- UnixBench ---"
    grep 'System Benchmarks Index Score' "$RESULTS_DIR/unixbench_output.txt" 2>/dev/null | sed 's/^/  /' || echo "  not available"

    echo ""
    echo "=============================================="
    echo " All raw results in: $RESULTS_DIR"
    echo "=============================================="
} | tee "$SUMMARY"

echo ""
ok "All benchmarks complete. Results saved to $RESULTS_DIR"
echo -e "${CYAN}Paste the contents of $SUMMARY into the chat to generate the report.${NC}"