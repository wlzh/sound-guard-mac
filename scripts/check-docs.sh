#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
plutil -lint Resources/Info.plist
ruby scripts/check-docs.rb
