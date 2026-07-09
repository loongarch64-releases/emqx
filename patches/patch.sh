#!/bin/bash

set -euo pipefail

SRC="${1}"
VERSION="${2}"
MAJOR_VER=$(echo "$VERSION" | cut -d. -f1)
MINOR_VER=$(echo "$VERSION" | cut -d. -f2)
PATCH_VER=$(echo "$VERSION" | cut -d. -f3)
VER_NUM=$(( 10#$MAJOR_VER * 1000000 + 10#$MINOR_VER * 1000 + 10#$PATCH_VER ))

patch_jiffy()
{
    local JIFFY_DIR="${DEP_BASE}/jiffy"

    sed -i 's/defined(__riscv) ||/& defined(__loongarch64) ||/' "${JIFFY_DIR}/c_src/double-conversion/utils.h"
}

patch_rocksdb()
{
    local ROCKSDB_DIR="${DEP_BASE}/rocksdb/deps/rocksdb"

    # 避免重复补丁
    if grep -q "loongarch64" "${ROCKSDB_DIR}/Makefile"; then
    sed -i 's/-mcpu=loongarch64/-march=loongarch64/' "${ROCKSDB_DIR}/CMakeLists.txt"
    else
    sed -i 's/sparc64/sparc64 loongarch64/' "${ROCKSDB_DIR}/Makefile"
    sed -i 's/defined(_M_ARM64)/& || defined(__loongarch64)/' "${ROCKSDB_DIR}/util/xxhash.h"
    sed -i '/pause/a \
#elif defined(__loongarch64) \
  asm volatile("dbar 0");' "${ROCKSDB_DIR}/port/port_posix.h"
    sed -i '/return cycles/a \
#elif defined(__loongarch64) \
  unsigned long result; \
  asm volatile ("rdtime.d\\t%0,$r0" : "=r" (result)); \
  return result;' "${ROCKSDB_DIR}/utilities/transactions/lock/range/range_tree/lib/portability/toku_time.h"
    sed -i '/endif(CMAKE_SYSTEM_PROCESSOR MATCHES "s390x")/a \
if(CMAKE_SYSTEM_PROCESSOR MATCHES "loongarch64") \
  CHECK_C_COMPILER_FLAG("-march=loongarch64" HAS_LOONGARCH64) \
  if(HAS_LOONGARCH64) \
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -march=loongarch64 -mtune=loongarch64") \
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=loongarch64 -mtune=loongarch64") \
  endif(HAS_LOONGARCH64) \
endif(CMAKE_SYSTEM_PROCESSOR MATCHES "loongarch64")' "${ROCKSDB_DIR}/CMakeLists.txt"
    sed -i '/if(CMAKE_SYSTEM_PROCESSOR MATCHES "^s390x")/i \
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "^loongarch64") \
      set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=loongarch64") \
    endif()' "${ROCKSDB_DIR}/CMakeLists.txt"
    fi
    
    # 旧版本的 rocksdb 依赖隐式包含的 <cstdint>，而构建环境的 GCC 较新，去掉了这个隐式包含
    sed -i '/#pragma once/a \
#include <cstdint>' "${ROCKSDB_DIR}/db/blob/blob_file_meta.h"
    sed -i '/#pragma once/a \
#include <cstdint>' "${ROCKSDB_DIR}/include/rocksdb/trace_record.h"
    sed -i '/#pragma once/a \
#include <cstdint>' "${ROCKSDB_DIR}/include/rocksdb/trace_record_result.h"
}

# 通用补丁
universal_adaptation()
{
    local DEP_BASE="${1}"
    patch_jiffy "${DEP_BASE}"
    patch_rocksdb "${DEP_BASE}"
}

# 不同版本适配
multi_version_adaptation()
{
    local DEP_BASE="${1}"

    if [ "${VER_NUM}" -ge 6002001 ]; then
        # 和前面版本一样，在没有 mnesia_hook 的 erlang 上走 mnesia 后端
        local MRIA_CONFIG="${DEP_BASE}/mria/src/mria_config.erl"
        local MARIA_RLOG="${DEP_BASE}/mria/src/mria_rlog.erl"
        sed -i '/-spec load_config()/,/consistency_check()/ {/consistency_check()/i\
    copy_from_env(db_backend),
}' "${MRIA_CONFIG}"
        sed -i '/mnesia_hook:register_hook/d' "${MARIA_RLOG}"
        sed -i '/mria_rlog_replica:create_tabs()/d' "${MARIA_RLOG}"
        sed -i '/-spec init()/{
  N
  /-spec init().*\ninit()/a\
    case mria_config:whoami() of\
        mnesia ->\
            ok;\
        _ ->\
            mnesia_hook:register_hook(post_commit, fun ?MODULE:intercept_trans/2),\
            mria_rlog_replica:create_tabs()\
    end.
}' "${MARIA_RLOG}"
    fi
}

patch()
{
    CLEAR_VER=${VERSION#v} && CLEAR_VER=${CLEAR_VER#e}
    MAJOR_VER=$(echo "$CLEAR_VER" | cut -d. -f1)
    if [ "${MAJOR_VER}" -lt 6 ]; then
        DEP_BASE="${SRC}/_build/default/lib"
    else
        DEP_BASE="${SRC}/deps"
    fi
    echo "patching..."
    universal_adaptation "${DEP_BASE}"
    multi_version_adaptation "${DEP_BASE}"
    echo "done"
}

patch

