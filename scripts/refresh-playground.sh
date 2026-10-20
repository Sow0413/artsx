#!/bin/bash
# SurveyApp と SurveyCore を、iPad の Swift Playgrounds 用パッケージへコピーする。
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/測量.swiftpm"
rm -rf "$dest/App" "$dest/SurveyCore"
mkdir -p "$dest/App" "$dest/SurveyCore"
cp -a "$root/SurveyApp/." "$dest/App/"
cp -a "$root/SurveyCore/Sources/SurveyCore/." "$dest/SurveyCore/"
find "$dest" -name .DS_Store -delete
echo "copied into $dest"
