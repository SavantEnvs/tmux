#!/usr/bin/env bash
#
# mayhem/build.sh — build tmux's seven in-tree libFuzzer harnesses (fuzz/*-fuzzer.c, the same set
# OSS-Fuzz builds) with ASan+UBSan, their -standalone reproducers, and a normal-flags tmux for test.sh.
# Runs inside the commit image as `mayhem` in /mayhem; re-runnable and offline (all deps are apt -dev).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
HARNESSES="cmd-parse-fuzzer format-fuzzer input-fuzzer json-fuzzer layout-fuzzer style-fuzzer sixel-fuzzer"

# upstream's generated build files are gitignored; (re)generate them from the committed autotools sources
[ -x ./configure ] || ./autogen.sh

# 1) Test build: normal flags, out of tree, no sanitizers and no fuzzing stubs (test.sh runs this tmux).
rm -rf mayhem/build-tests
mkdir -p mayhem/build-tests
(
  cd mayhem/build-tests
  env -u CFLAGS -u LDFLAGS ../../configure --enable-images CC="$CC" CFLAGS="-O1 $COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS" >/dev/null
  make -j"$MAYHEM_JOBS" tmux >/dev/null
)

# 2) Fuzz build: the project's objects sanitized, DWARF 3, with SanCov instrumentation (fuzzer-no-link).
rm -rf mayhem/build-fuzz
mkdir -p mayhem/build-fuzz
cd mayhem/build-fuzz
FUZZ_CFLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS"
env -u CFLAGS -u LDFLAGS ../../configure --enable-fuzzing --enable-images CC="$CC" \
  CFLAGS="$FUZZ_CFLAGS" LDFLAGS="$SANITIZER_FLAGS" >/dev/null
make -j"$MAYHEM_JOBS" tmux >/dev/null
LIBS="$(printf 'include Makefile\nprint-%%:\n\t@echo $($*)\n' | make -s -f - print-LIBS)"
OBJS="$(ls ./*.o compat/*.o)"

# LeakSanitizer off at build time (leaks are not the class this fleet fuzzes for).
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o standalone_main.o

for h in $HARNESSES; do
  if [ "$h" = sixel-fuzzer ]; then
    # fuzz/sixel-fuzzer.c is not in upstream's Makefile.am and no longer compiles (it calls now-static
    # sixel_free/sixel_size_in_cells), so build our own copy of the harness with the project's flags
    mkdir -p fuzz
    printf 'include Makefile\nfuzz/%s.o: $(srcdir)/mayhem/harnesses/%s.c\n\t$(COMPILE) -c -o $@ $<\n' "$h" "$h" \
      | make -s -f - "fuzz/$h.o" >/dev/null
  else
    make -s "fuzz/$h.o" >/dev/null 2>&1 || make -s "fuzz/$h.o" >/dev/null
  fi
  $CC $FUZZ_CFLAGS $LIB_FUZZING_ENGINE "fuzz/$h.o" $OBJS lsan_off.o $LIBS -o "/mayhem/$h"
  $CC $FUZZ_CFLAGS standalone_main.o "fuzz/$h.o" $OBJS lsan_off.o $LIBS -o "/mayhem/$h-standalone"
done
