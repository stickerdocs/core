#!/usr/bin/env bash

# Exit if any command fails
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Generate mock objects
dart run build_runner build --delete-conflicting-outputs

# Run the Dart linter
dart analyze

echo -e "${CYAN}Running osv-scanner...${NC}"
osv-scanner -lockfile=pubspec.lock

# Run tests
flutter test -r expanded \
    --coverage \
    --no-test-assets \
    --test-randomize-ordering-seed "random"

# Coverage report
# We don't seem to get function coverage for Flutter/Dart so remove that from the report
genhtml coverage/lcov.info -o coverage/html \
    -t "StickerDocs Core" \
    --no-function-coverage