#!/usr/bin/env bash

# Exit if any command fails
set -e

flutter pub upgrade

# Disable this or it will pull down the broken version of libsodium
# flutter pub upgrade --major-versions

flutter clean
flutter pub get
flutter pub outdated