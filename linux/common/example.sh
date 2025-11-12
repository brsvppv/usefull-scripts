#!/usr/bin/env bash
# Example Linux script - non-destructive smoke test
# Purpose: print basic system info
set -euo pipefail

echo "Running example Linux script from usefull-scripts"
printf "Kernel: %s\n" "$(uname -sr)"
printf "User: %s\n" "${USER:-$(whoami)}"
exit 0
