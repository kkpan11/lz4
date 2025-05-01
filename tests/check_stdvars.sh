#!/usr/bin/env bash
# Verify that every real compile and link command receives
# the CC / CFLAGS / CPPFLAGS / LDFLAGS / LDLIBS markers.
#
#   Usage:  tests/check_stdvars.sh build.log
#
# The log should be produced with:
#       make -nr V=1 …  > build.log
# (‘-n’ = dry-run, ‘-r’ = no builtin rules, ‘V=1’ = verbose)

set -euo pipefail

log_file=${1:?need build-log file}

# ---------- markers injected from the test target ----------
CC_TAG='-DCC_TEST'
CF_TAG='-DCFLAGS_TEST'
CP_TAG='-DCPPFLAGS_TEST'
LD_TAG='-DLDFLAGS_TEST'
LL_TAG='-DLDLIBS_TEST'
# -----------------------------------------------------------

compile_seen=0  compile_ok=0
link_seen=0     link_ok=0
fail=0

while IFS= read -r line; do
    # Skip empty, comment, or progress-echo lines
    [[ $line =~ ^[[:space:]]*$           ]] && continue
    [[ $line =~ ^[[:space:]]*#           ]] && continue
    [[ $line =~ ^[[:space:]]*echo[[:space:]] ]] && continue

    # Consider only real cc/clang/gcc/clang++ invocations
    if [[ $line =~ (^|[[:space:]])(cc|gcc|g\+\+|clang|clang\+\+)([[:space:]]|$) ]]; then
        if [[ $line == *" -c "* ]]; then        # --- compile step
            ((compile_seen++))
            if [[ $line == *"$CC_TAG"* && $line == *"$CF_TAG"* && $line == *"$CP_TAG"* ]]; then
                ((compile_ok++))
            else
                echo >&2 "✖ compile cmd missing marker(s):"
                echo >&2 "  $line"
                fail=1
            fi
        else                                     # --- link step
            ((link_seen++))
            if [[ $line == *"$LD_TAG"* && $line == *"$LL_TAG"* ]]; then
                ((link_ok++))
            else
                echo >&2 "✖ link cmd missing marker(s):"
                echo >&2 "  $line"
                fail=1
            fi
        fi
    fi
done < "$log_file"

if (( fail )); then
    echo >&2 "standard-variable propagation test **FAILED**"
    echo >&2 "  compile: $compile_ok / $compile_seen OK"
    echo >&2 "  link   : $link_ok / $link_seen OK"
    exit 1
fi

echo "✓ $compile_seen compile + $link_seen link commands: all markers present"
