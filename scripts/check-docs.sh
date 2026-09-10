#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(tr -d '[:space:]' < VERSION)"
build="$(tr -d '[:space:]' < BUILD_NUMBER)"
test "$version" = '0.1.0'
test "$build" = '1'
for file in README.md LICENSE CONTRIBUTING.md SECURITY.md CHANGELOG.md docs/README.md docs/TESTING.md docs/prd/README.md "docs/prd/v$version/prd.md"; do
    test -s "$file"
done
grep -Fq "# v$version 产品需求文档" "docs/prd/v$version/prd.md"
test "$(grep -c '^\- \[ \] A[0-9][0-9] ' "docs/prd/v$version/prd.md")" = '28'
grep -Fq '尚无可运行 App' README.md
grep -Fq 'NOT RUN' docs/TESTING.md
grep -Fq 'MIT License' LICENSE
echo 'DOCUMENT_BASELINE=PASS; APP_BUILD=NOT_RUN; FUNCTIONAL_TESTS=NOT_RUN'
