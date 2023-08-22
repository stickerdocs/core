#!/usr/bin/env bash

# Exit if any command fails
set -e

# Generate mock objects
dart run build_runner build --delete-conflicting-outputs

# Run the Dart linter
dart analyze

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