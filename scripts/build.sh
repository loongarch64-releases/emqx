#!/bin/bash
set -euo pipefail

UPSTREAM_OWNER=emqx
UPSTREAM_REPO=emqx
VERSION="${1}"
EL_VERSION="${2}"
echo "   🏢 Org:   ${UPSTREAM_OWNER}"
echo "   📦 Proj:  ${UPSTREAM_REPO}"
echo "   🏷️  Ver:   ${VERSION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DISTS="${ROOT_DIR}/dists"
SRCS="${ROOT_DIR}/srcs"
PATCHES="${ROOT_DIR}/patches"

mkdir -p "${DISTS}/${VERSION}" "${SRCS}"

# ==========================================
# 👇 用户自定义构建逻辑 (示例)
# ==========================================

echo "🔧 Compiling ${UPSTREAM_OWNER}/${UPSTREAM_REPO} ${VERSION}..."

# 1. 准备阶段：安装依赖、下载代码、应用补丁等
prepare()
{
    echo "📦 [Prepare] Setting up build environment..."
    
    git clone -b ${VERSION} --depth 1 "https://github.com/${UPSTREAM_OWNER}/${UPSTREAM_REPO}.git" "${SRCS}/${VERSION}"   

    echo "✅ [Prepare] Environment ready."
}

# 2. 编译阶段：核心构建命令
build()
{
    echo "🔨 [Build] Compiling source code..."
    export CC="cc -fPIC -mcmodel=medium  -fpermissive -w -std=gnu99"
    export CXX="c++ -fPIC -mcmodel=medium  -fpermissive -w -std=gnu99"
    
    pushd "${SRCS}/${VERSION}"

    if [ "${EL_VERSION}" -le 6 ]; then
	EMQX_GOAL=emqx
    else
	EMQX_GOAL=emqx-enterprise
    fi
    make "${EMQX_GOAL}" || true
    "${PATCHES}/patch.sh" "${SRCS}/${VERSION}" "${VERSION}"
    make "${EMQX_GOAL}-tgz"
    make "${EMQX_GOAL}-pkg"
    popd

    echo "✅ [Build] Compilation finished."
}

# 3. 后处理阶段：整理产物、清理临时文件、验证版本
post_build()
{
    echo "📦 [Post-Build] Organizing artifacts..."
    if [ "${EL_VERSION}" -eq 6 ]; then
	PKG_DIR="${SRCS}/${VERSION}/_packages/emqx"
    else
	PKG_DIR="${SRCS}/${VERSION}/_packages/emqx-enterprise"
    fi
    cp "${PKG_DIR}/emqx*" "${DISTS}/${VERSION}"
    chown -R "${HOST_UID}:${HOST_GID}" "${SRCS}" "${DISTS}"

    echo "✅ [Post-Build] Artifacts ready in ./dists/${VERSION}."
}

# 主入口
main()
{
    prepare
    build
    post_build
}

main

# ==========================================
# 👆 自定义逻辑结束
# ==========================================

cat > "${DISTS}/${VERSION}/release.txt" <<EOF
Project: ${UPSTREAM_REPO}
Organization: ${UPSTREAM_OWNER}
Version: ${VERSION}
Build Time: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

echo "✅ Compilation finished."
ls -lh "${DISTS}/${VERSION}"
