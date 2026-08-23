#!/usr/bin/env bash
#
# Build a custom DIA-NN Docker image for use with nf-skyline-dia-ms.
#
# This script downloads the Dockerfile and entrypoint.sh from the
# nf-skyline-dia-ms GitHub repository and builds a Docker image for
# the specified version of DIA-NN.
#
# Usage:
#   bash build_diann_docker.sh <version>
#   e.g.: bash build_diann_docker.sh 2.3.2
#

set -euo pipefail

GITHUB_RAW_BASE="https://raw.githubusercontent.com/mriffle/nf-skyline-dia-ms/main/resources/diann-docker"
IMAGE_NAME="diann"

usage() {
    cat <<EOF
Usage: $0 <diann-version>

Build a custom DIA-NN Docker image for use with the nf-skyline-dia-ms
Nextflow workflow.

The workflow includes DIA-NN 1.8.1 by default. This script lets you
build a Docker image for a newer version of DIA-NN to use instead.

Note: This script only supports DIA-NN version 2.x releases.

Arguments:
  <diann-version>  DIA-NN 2.x version to build (e.g., 2.3.2)
                   Must match a release at:
                   https://github.com/vdemichev/DiaNN/releases
                   The number must match the release exactly: the first
                   2.x release is "2.0", not "2.0.0".

Options:
  -h, --help       Show this help message and exit

Examples:
  $0 2.3.2
  $0 2.6.1
EOF
    exit 0
}

# Parse options
if [ $# -eq 0 ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
fi

VERSION="$1"
TAG="${IMAGE_NAME}:${VERSION}"

# Check that docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in your PATH."
    echo "Install Docker from https://docs.docker.com/engine/install/"
    exit 1
fi

# Check if image already exists
if docker image inspect "$TAG" > /dev/null 2>&1; then
    echo "Error: Docker image '${TAG}' already exists."
    echo "If you want to rebuild it, first remove it with:"
    echo ""
    echo "    docker rmi ${TAG}"
    echo ""
    exit 1
fi

# Create temp build directory
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "Downloading build files..."
if ! wget -q -O "${BUILD_DIR}/Dockerfile" "${GITHUB_RAW_BASE}/Dockerfile"; then
    echo "Error: Failed to download Dockerfile."
    exit 1
fi

if ! wget -q -O "${BUILD_DIR}/entrypoint.sh" "${GITHUB_RAW_BASE}/entrypoint.sh"; then
    echo "Error: Failed to download entrypoint.sh."
    exit 1
fi
chmod +x "${BUILD_DIR}/entrypoint.sh"

# Fail early, and with a useful message, if the requested version does not exist.
# Without this the build gets as far as the download and dies inside Docker with
# a wget exit code and no explanation. The download URL is derived from the
# Dockerfile so the two cannot drift apart.
URL_TEMPLATE=$(grep -m1 -oE 'https://github\.com/vdemichev/DiaNN/releases/download/[^[:space:]]+\.zip' \
                    "${BUILD_DIR}/Dockerfile" || true)

if [ -z "$URL_TEMPLATE" ]; then
    echo "Warning: could not find the DIA-NN download URL in the Dockerfile."
    echo "Skipping the version check and attempting the build anyway."
else
    ASSET_URL="${URL_TEMPLATE//\$\{DIANN_VERSION\}/${VERSION}}"
    echo "Checking that DIA-NN ${VERSION} is available..."

    # wget exits 8 when the server answers with an error (a 404 here means the
    # version does not exist). Any other non-zero exit means we could not reach
    # GitHub at all, which is not the user's version being wrong.
    wget -q --spider "$ASSET_URL" && SPIDER_RC=0 || SPIDER_RC=$?

    if [ "$SPIDER_RC" -ne 0 ] && [ "$SPIDER_RC" -ne 8 ]; then
        echo "Warning: could not reach GitHub to check version ${VERSION}"
        echo "(wget exit code ${SPIDER_RC}). Continuing with the build anyway."
    elif [ "$SPIDER_RC" -eq 8 ]; then
        echo "Error: no DIA-NN Linux release found for version '${VERSION}'."
        echo ""
        echo "Expected to find:"
        echo "    ${ASSET_URL}"
        echo ""
        echo "Check the version number against the list of releases at:"
        echo "    https://github.com/vdemichev/DiaNN/releases"
        echo ""
        echo "The number must match the release exactly. For example, the first"
        echo "2.x release is '2.0', not '2.0.0'."
        exit 1
    fi
fi

echo "Building Docker image '${TAG}' for DIA-NN ${VERSION}..."
echo "This may take a few minutes."
echo ""

docker build --no-cache --build-arg DIANN_VERSION="${VERSION}" -t "${TAG}" "${BUILD_DIR}"

echo ""
echo "========================================================================"
echo "  Success! Docker image '${TAG}' has been built."
echo "========================================================================"
echo ""
echo "  To use this version of DIA-NN with nf-skyline-dia-ms, add the"
echo "  following line to the params section of your pipeline.config file:"
echo ""
echo "      images.diann = '${TAG}'"
echo ""
echo "  For example, your pipeline.config should look like:"
echo ""
echo "      params {"
echo "          images.diann = '${TAG}'"
echo "          // ... your other parameters ..."
echo "      }"
echo ""
echo "  Then run the workflow as usual. See the documentation for details:"
echo "  https://nf-skyline-dia-ms.readthedocs.io/"
echo "========================================================================"
