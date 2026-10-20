#!/bin/bash
# DIAG (temporary): run api.rseq / api.rseq_splitvma with DR logging and keep
# a summary for every run (pass or fail) showing where the rseq loop thread was
# when detach synch finally succeeded (or the last failed attempt).
set -u
OUT=$GITHUB_WORKSPACE/diag-out
mkdir -p "$OUT"
{
  grep -m1 "model name" /proc/cpuinfo
  echo "nproc=$(nproc) kernel=$(uname -r)"
} | tee "$OUT/cpu.txt"
cd "$GITHUB_WORKSPACE/build/suite/tests"
N=${N:-6}
kept_pass=0
kept_fail=0

summarize() {
  local d=$1 sum=$2
  local dir main loop
  dir=$(ls -d "$d"/*/ | head -1)
  main=$(ls "$dir"/log.0.*.html | head -1)
  loop=$(ls "$dir"/log.1.*.html 2>/dev/null | head -1)
  {
    echo "### main log: $main"
    echo "not-at-safe-spot count: $(grep -a -c 'not at safe spot' "$main")"
    echo "### distinct 'pc is in F' during synch (count):"
    grep -a 'recreate_app : pc is in F' "$main" | sort | uniq -c | sort -rn | head
    echo "### safe-spot lines:"
    grep -a -n 'suspended at safe spot\|waiting at safe spot\|Synch succeeded\|suspended in good spot' "$main" | tail -20
    echo "### context before first 'Synch succeeded' after detach start:"
    local start n
    start=$(grep -a -n 'seeking 5 state' "$main" | tail -1 | cut -d: -f1)
    start=${start:-1}
    n=$(awk -v s="$start" 'NR>s && /Synch succeeded/ {print NR; exit}' "$main")
    if [ -n "$n" ]; then sed -n "$((n > 250 ? n - 250 : 1)),${n}p" "$main"; fi
    echo "### last 120 lines of main log:"
    tail -120 "$main"
    if [ -n "$loop" ]; then
      echo "### loop thread log: $loop"
      echo "### trace/fragment creation for rseq region (loop thread):"
      grep -a -n 'Fragment\|trace\|Trace\|drbbdup\|rseq\|handle_suspend_signal\|waiting for synch\|done waiting' "$loop" | tail -150
      echo "### last 300 lines of loop thread log:"
      tail -300 "$loop"
    fi
  } > "$sum" 2>&1
}

run_one() {
  local bin=$1 tag=$2
  local d=$OUT/logs.$tag
  mkdir -p "$d"
  local t0 t1 rc
  t0=$(date +%s.%N)
  timeout 300 setsid env GLIBC_TUNABLES="glibc.pthread.rseq=0" \
    RSEQ_DIAG_OPS="-loglevel 3 -logmask 0x0fffffff -logdir $d" \
    ./bin/$bin > "$OUT/$tag.out" 2>&1
  rc=$?
  t1=$(date +%s.%N)
  local status=PASS
  grep -q "All done" "$OUT/$tag.out" || status=FAIL
  echo "$status $tag rc=$rc $(echo "$t1 - $t0" | bc)s"
  summarize "$d" "$OUT/$tag.$status.summary.txt"
  # Keep full logs (compressed) for the first two passes and first fail only.
  if [ $status = PASS ] && [ $kept_pass -lt 2 ]; then
    kept_pass=$((kept_pass + 1)); tar czf "$OUT/$tag.PASS.logs.tgz" -C "$d" .
  elif [ $status = FAIL ] && [ $kept_fail -lt 1 ]; then
    kept_fail=$((kept_fail + 1)); tar czf "$OUT/$tag.FAIL.logs.tgz" -C "$d" .
  fi
  rm -rf "$d"
}

for i in $(seq 1 $N); do
  run_one api.rseq rseq.$i
  run_one api.rseq_splitvma split.$i
done
exit 0
