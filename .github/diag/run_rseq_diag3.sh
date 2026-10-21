#!/bin/bash
# DIAG (temporary): with an app nop added to the rseq loop, check whether
# detach synch now succeeds quickly on all CPUs, and where suspends land.
set -u
OUT=$GITHUB_WORKSPACE/diag-out
mkdir -p "$OUT"
{
  grep -m1 "model name" /proc/cpuinfo
  echo "nproc=$(nproc) kernel=$(uname -r)"
} | tee "$OUT/cpu.txt"
cd "$GITHUB_WORKSPACE/build/suite/tests"
N=${N:-10}

run_one() {
  local bin=$1 tag=$2 extra=$3
  local t0 t1 rc status
  t0=$(date +%s.%N)
  timeout 300 setsid env GLIBC_TUNABLES="glibc.pthread.rseq=0" RSEQ_DIAG_OPS="$extra" \
    ./bin/$bin > "$OUT/$tag.out" 2>&1
  rc=$?
  t1=$(date +%s.%N)
  status=PASS
  grep -q "All done" "$OUT/$tag.out" || status=FAIL
  echo "$status $tag rc=$rc $(echo "$t1 - $t0" | bc)s"
  [ $status = PASS ] && rm -f "$OUT/$tag.out"
}

pc_offsets() {
  local log=$1 start
  start=$(grep -a -n 'seeking 5 state' "$log" | tail -1 | cut -d: -f1)
  awk -v s="${start:-1}" 'NR>s && /recreate_app : looking for/ {
    pc=strtonum($5); frag=strtonum($9); printf "+%d\n", pc-frag }' "$log" |
    sort | uniq -c | sort -rn | awk '{printf "%s:%s ", $2, $1}'
  echo
}

echo "##### Phase A: serial, no logging"
for i in $(seq 1 $N); do
  run_one api.rseq rseq.a.$i ""
  run_one api.rseq_splitvma split.a.$i ""
done

echo "##### Phase B: concurrent, no logging"
for i in $(seq 1 5); do
  run_one api.rseq rseq.b.$i "" &
  run_one api.rseq_splitvma split.b.$i "" &
  wait
done

echo "##### Phase C: logged (suspend PC offsets in the detach synch)"
for i in 1 2; do
  for b in api.rseq api.rseq_splitvma; do
    d=$OUT/logs.$b.$i
    mkdir -p "$d"
    run_one $b log.$b.$i "-loglevel 3 -logmask 0x0fffffff -logdir $d"
    log=$(ls "$d"/*/log.0.*.html | head -1)
    echo "  unsafe=$(grep -a -c 'not at safe spot' "$log") offsets: $(pc_offsets "$log")"
    grep -a -m1 'suspended at safe spot\|waiting at safe spot' "$log" | sed 's/^/  /'
    # Keep the synch-relevant part of the main log for inspection.
    grep -a -n 'recreate_app\|safe spot\|Synch' "$log" | tail -400 > "$OUT/$b.$i.synch.txt"
    rm -rf "$d"
  done
done
exit 0
