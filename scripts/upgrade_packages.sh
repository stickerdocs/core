#!/usr/bin/env bash

# Exit if any command fails
set -e

flutter pub upgrade
flutter pub upgrade --major-versions
flutter clean
flutter pub get
flutter pub outdated