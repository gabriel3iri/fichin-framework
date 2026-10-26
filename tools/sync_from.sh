#!/bin/bash
# Trae addons/jornada y examples/ desde un juego que use el framework: tools/sync_from.sh <ruta-al-juego> [rama]
# La rama por defecto es origin/main (lo ya integrado). Después: revisar `git status` y commitear.
set -euo pipefail
src="${1:?ruta al repo del juego}"
ref="${2:-origin/main}"
cd "$(dirname "$0")/.."
git -C "$src" fetch --quiet origin || true
rm -rf addons/jornada examples
git -C "$src" archive "$ref" addons/jornada examples | tar -x -C .
echo "framework copiado desde $src ($ref, $(git -C "$src" rev-parse --short "$ref"))"
