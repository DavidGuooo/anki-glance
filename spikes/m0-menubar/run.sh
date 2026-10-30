#!/bin/zsh
# PROTOTYPE — builds and runs the throwaway M0 spike. Log goes to stdout.
set -e
cd "$(dirname "$0")"
app=build/M0Spike.app
mkdir -p $app/Contents/MacOS
cp Info.plist $app/Contents/
swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx14.0 M0Spike.swift -o $app/Contents/MacOS/M0Spike
codesign -s - --force $app
exec $app/Contents/MacOS/M0Spike
