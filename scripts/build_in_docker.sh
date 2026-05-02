#!/bin/bash
# 开启严格模式：
# -e: 命令失败即退出
# -u: 引用未定义变量即退出 (关键！)
# -o pipefail: 管道失败即退出
set -euo pipefail

UPSTREAM_OWNER=emqx
UPSTREAM_REPO=emqx
VERSION="${1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

DOCKER_IMAGE_NAME="${UPSTREAM_OWNER}/${UPSTREAM_REPO}-build-env"
DOCKERFILE_PATH="${ROOT_DIR}/Dockerfile.build"

PLATFORM='linux/loong64'

echo "🚀 Starting build process..."
echo "   🏢 Organization: ${UPSTREAM_OWNER}"
echo "   📦 Project:      ${UPSTREAM_REPO}"
echo "   🏷️  Version:      ${VERSION}"
echo "   🐳 Image Name:   ${DOCKER_IMAGE_NAME}"

if [ ! -f "$DOCKERFILE_PATH" ]; then
    echo "❌ Error: Dockerfile.build not found at ${DOCKERFILE_PATH}"
    exit 1
fi

# switch base-img based on version
CLEAR_VER=${VERSION#v} && CLEAR_VER=${CLEAR_VER#e}
MAJOR_VER=$(echo "$CLEAR_VER" | cut -d. -f1)
MINOR_VER=$(echo "$CLEAR_VER" | cut -d. -f2)
VER_NUM=$(( 10#$MAJOR_VER * 1000 + 10#$MINOR_VER ))
if [ "${VER_NUM}" -ge 5009 ]; then
    EL_VER=27
elif [ "${VER_NUM}" -ge 5004 ]; then
    EL_VER=26
elif [ "${VER_NUM}" -ge 5000 ]; then
    EL_VER=25
else
    EL_VER=24
fi
sed -i "s/ARG EL_VERSION=.*/ARG EL_VERSION=${EL_VER}/" "${DOCKERFILE_PATH}"

echo "🔨 Building Docker image: ${DOCKER_IMAGE_NAME} ..."
docker build -t "${DOCKER_IMAGE_NAME}" -f "${DOCKERFILE_PATH}" "${ROOT_DIR}"

echo "🏃 Running build inside container..."

docker run --rm \
    --platform "${PLATFORM}" \
    -v "${ROOT_DIR}:/src:z" \
    -w /src \
    -e VERSION="${VERSION}" \
    -e UPSTREAM_OWNER="${UPSTREAM_OWNER}" \
    -e UPSTREAM_REPO="${UPSTREAM_REPO}" \
    -e HOST_UID=$(id -u) \
    -e HOST_GID=$(id -g) \
    "${DOCKER_IMAGE_NAME}" \
    /bin/bash -c "./scripts/build.sh $VERSION $EL_VER"

echo "✅ Build completed successfully!"
