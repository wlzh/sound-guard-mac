#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift run GuardTests
swift build --product SoundGuard
swift run SoundGuard --self-test-ui
zsh scripts/check-docs.sh
git diff --check
echo 'AUTOMATED_GATE=PASS; HARDWARE_AND_LONG_RUN=SEE_DOCS'
