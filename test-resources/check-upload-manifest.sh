#!/usr/bin/env bash
#
# Compare the Panorama upload manifest a stub run produced against the expected manifest for
# that config, so any change to what gets uploaded -- or where -- shows up as a diff.
#
#   Usage: test-resources/check-upload-manifest.sh <config-file-name> [--update]
#
# The config name is the bare file name, e.g. 'test-diann-upload-no-metadata.config'. The
# expected manifest lives at test-resources/expected/<config-basename>.uploads.tsv. Configs
# with no expected file are skipped, so this is safe to run for every config in the matrix.
#
# Each run uploads under nextflow/<timestamp>/<session-id>/, both of which change every run,
# so that prefix is replaced with <RUN> before comparing.
set -euo pipefail

CONFIG="${1:?usage: check-upload-manifest.sh <config-file-name> [--update]}"
MODE="${2:-check}"

EXPECTED="test-resources/expected/${CONFIG%.config}.uploads.tsv"
ACTUAL="results/nf-skyline-dia-ms/panorama/panorama_uploads.tsv"

if [ ! -f "$EXPECTED" ] && [ "$MODE" != "--update" ]; then
    echo "No expected upload manifest for ${CONFIG}; skipping."
    exit 0
fi

if [ ! -f "$ACTUAL" ]; then
    echo "::error::Expected an upload manifest at ${ACTUAL} but the run produced none."
    echo "If this config should not upload anything, delete ${EXPECTED}."
    exit 1
fi

normalized=$(mktemp)
sed -E 's#https://[^[:space:]]*/nextflow/[^/]+/[^/]+#<RUN>#' "$ACTUAL" > "$normalized"

if [ "$MODE" = "--update" ]; then
    mkdir -p "$(dirname "$EXPECTED")"
    cp "$normalized" "$EXPECTED"
    echo "Wrote ${EXPECTED}"
    exit 0
fi

if ! diff -u "$EXPECTED" "$normalized"; then
    echo "::error::Panorama uploads changed for ${CONFIG}."
    echo "If the change is intended, regenerate with:"
    echo "  nextflow run . -stub-run -c test-resources/${CONFIG} -c test-resources/ci.config"
    echo "  test-resources/check-upload-manifest.sh ${CONFIG} --update"
    exit 1
fi

echo "Upload manifest matches for ${CONFIG}."
