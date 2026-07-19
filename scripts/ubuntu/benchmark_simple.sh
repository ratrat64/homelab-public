#!/bin/bash

IPERF_SERVER="192.168.1.160"

echo "=== CPU ==="
sysbench cpu --threads=1 --time=30 run 2>&1 | tee cpu_single.txt
sysbench cpu --threads=16 --time=30 run 2>&1 | tee cpu_multi.txt

echo "=== Memory ==="
sysbench memory --memory-block-size=1M --memory-total-size=100G --threads=1 run 2>&1 | tee mem_seq.txt
sysbench memory --memory-block-size=4K --memory-total-size=10G --memory-access-mode=rnd --threads=1 run 2>&1 | tee mem_rnd.txt

echo "=== fio ==="
fio --name=seq_read --rw=read --bs=1M --size=16G --direct=1 --numjobs=1 --ioengine=psync --unlink=1 --output=fio_seq_read.txt
fio --name=seq_write --rw=write --bs=1M --size=16G --direct=1 --numjobs=1 --ioengine=psync --unlink=1 --output=fio_seq_write.txt
fio --name=rnd_read --rw=randread --bs=4K --size=4G --direct=1 --numjobs=4 --ioengine=libaio --iodepth=32 --runtime=60 --time_based --group_reporting --unlink=1 --output=fio_rnd_read.txt
fio --name=rnd_write --rw=randwrite --bs=4K --size=4G --direct=1 --numjobs=4 --ioengine=libaio --iodepth=32 --runtime=60 --time_based --group_reporting --unlink=1 --output=fio_rnd_write.txt

echo "=== Network ==="
iperf3 -c "$IPERF_SERVER" -t 30 -P 4 2>&1 | tee net_tcp.txt
iperf3 -c "$IPERF_SERVER" -t 30 -u -b 20G 2>&1 | tee net_udp.txt

echo "=== UnixBench ==="
cd ~/byte-unixbench/UnixBench && ./Run 2>&1 | tee unixbench_output.txt

echo "=== Done ==="
