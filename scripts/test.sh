#!/usr/bin/env bash

# Exit if any command fails
set -e

RED='\033[0;31m'
YELLOW='\033[0;93m'
GREEN='\033[0;32m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Generate mock objects
dart run build_runner build --delete-conflicting-outputs

# Run the Dart linter
set +e # We don't care to fail on lint warnings
dart analyze
set -e

echo -e "\n${CYAN}Running osv-scanner...${NC}"
osv-scanner -lockfile=pubspec.lock

echo -e "\n${CYAN}Running unit tests...${NC}"
rm -rf coverage

# Run tests
flutter test -r expanded \
    --coverage \
    --no-test-assets \
    --test-randomize-ordering-seed "random"

if [ -s "coverage/lcov.info" ]; then
    # Coverage report
    # We don't seem to get function coverage for Flutter/Dart so remove that from the report
    genhtml coverage/lcov.info -o coverage/html \
        -t "StickerDocs Core" \
        --no-function-coverage
else
    echo -e "\n${YELLOW}There was no test coverage report.${NC}"
fi

echo -e "\n${GREEN}Core tests passed.${NC}"