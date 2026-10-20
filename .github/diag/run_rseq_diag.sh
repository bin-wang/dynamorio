#!/bin/bash
# DIAG (temporary): loop api.rseq / api.rseq_splitvma to catch the
# "Failed to synchronize with all threads when detaching" failure, sampling
# thread state with gdb/procfs when a run hangs and collecting DR logs.
set -u
OUT=$GITHUB_WORKSPACE/diag-out
mkdir -p "$OUT"
{
  grep -m1 "model name" /proc/cpuinfo
  echo "nproc=$(nproc) kernel=$(uname -r)"
  ldd --version | head -1
  grep -m1 flags /proc/cpuinfo | tr ' ' '\n' | grep -E 'avx512|amx|shstk|pku|rdpid' | tr '\n' ' '
  echo
} | tee "$OUT/cpu.txt"
cd "$GITHUB_WORKSPACE/build/suite/tests"
N=${N:-5}
fails=0

run_one() {
  local bin=$1 tag=$2 extra=$3 tun=$4
  local out=$OUT/$tag.out
  local t0 t1 rc s k pid sampled=0
  t0=$(date +%s.%N)
  # setsid: the test does kill(0, SIGALRM), so isolate its process group.
  setsid env GLIBC_TUNABLES="glibc.pthread.rseq=0${tun}" RSEQ_DIAG_OPS="$extra" \
    ./bin/$bin > "$out" 2>&1 &
  pid=$!
  for s in $(seq 1 360); do
    sleep 0.5
    kill -0 $pid 2>/dev/null || break
    if [ $s -eq 30 ] && [ $sampled -eq 0 ]; then
      # Still running after 15s: a passing run takes <5s.  Sample its threads.
      sampled=1
      for k in 1 2 3; do
        {
          echo "=== sample $k at $(date +%T.%N)"
          for t in /proc/$pid/task/*; do
            echo "--- $t comm=$(cat $t/comm) wchan=$(cat $t/wchan 2>/dev/null)"
            echo "syscall: $(cat $t/syscall 2>/dev/null)"
            grep -E "^(State|SigPnd|ShdPnd|SigBlk|SigIgn|SigCgt|Cpus_allowed_list|voluntary|nonvoluntary)" $t/status
            cat $t/schedstat 2>/dev/null
          done
        } >> "$OUT/$tag.gdb" 2>&1
        timeout 90 gdb -p $pid -batch -nx -ex "set pagination off" \
          -ex "info threads" -ex "thread apply all bt 25" \
          -ex "thread apply all info registers rip rsp rax rdi rsi" \
          -ex "thread apply all x/12i \$pc-24" >> "$OUT/$tag.gdb" 2>&1
        sleep 3
      done
    fi
  done
  wait $pid
  rc=$?
  t1=$(date +%s.%N)
  if grep -q "All done" "$out"; then
    echo "PASS $tag rc=$rc $(echo "$t1 - $t0" | bc)s"
    rm -f "$out"
  else
    echo "FAIL $tag rc=$rc $(echo "$t1 - $t0" | bc)s"
    tail -4 "$out"
    fails=$((fails + 1))
  fi
}

echo "##### Phase 1: serial, no logging"
for i in $(seq 1 $N); do
  run_one api.rseq rseq.p1.$i "" ""
  run_one api.rseq_splitvma split.p1.$i "" ""
done

echo "##### Phase 2: both tests concurrently, no logging"
for i in $(seq 1 $N); do
  run_one api.rseq rseq.p2.$i "" "" &
  run_one api.rseq_splitvma split.p2.$i "" "" &
  wait
done

echo "##### Phase 3: glibc AVX-512 disabled via tunables"
NOAVX=":glibc.cpu.hwcaps=-AVX512F,-AVX512VL,-AVX512BW,-AVX512DQ,-AVX512CD,-AVX512_VBMI,-AVX512_VBMI2"
for i in $(seq 1 $N); do
  run_one api.rseq rseq.p3.$i "" "$NOAVX"
  run_one api.rseq_splitvma split.p3.$i "" "$NOAVX"
done

echo "##### Phase 4: DR logging (loglevel 3, all masks)"
for i in 1 2 3; do
  for b in api.rseq api.rseq_splitvma; do
    d=$OUT/logs.$b.$i
    mkdir -p "$d"
    run_one $b log.$b.$i "-loglevel 3 -logmask 0x0fffffff -logdir $d" ""
    # Keep logs only for failures (they are large).
    if [ ! -e "$OUT/log.$b.$i.out" ]; then rm -rf "$d"; fi
  done
done

echo "##### Total failures: $fails"
exit 0
