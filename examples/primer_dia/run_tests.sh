#!/bin/bash
# Pruebas del ejemplo con el testkit del framework: ./run_tests.sh [filtro]
cd "$(dirname "$0")" || exit 1
set -o pipefail
perl -e 'alarm shift; exec @ARGV' 300 godot --headless --path . -s res://addons/jornada/testkit/runner.gd -- "$@" 2>&1 \
	| grep -v "Case mismatch\|This file will not open"
