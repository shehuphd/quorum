#!/usr/bin/env bash
# macOS double-click entry point. Runs the shared launcher from this folder.
cd "$(dirname "$0")"
exec ./launch.sh
