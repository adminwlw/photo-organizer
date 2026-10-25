#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

flutter pub get
flutter analyze
flutter test
flutter build ipa --release "$@"

echo "IPA output: $(pwd)/build/ios/ipa"
