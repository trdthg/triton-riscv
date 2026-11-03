#!/usr/bin/env bash
#
# Build the LLVM/MLIR that Triton is compiled against.
#
# Upstream Triton's build hard-codes the NVPTX and AMDGPU codegen libraries and
# the AMD backend needs lld, so the LLVM bundled with buddy-mlir (RISCV only) is
# not enough: building unpatched Triton on RISC-V requires an LLVM that also
# provides those targets plus lld.
#
# We build it from the buddy-mlir llvm-project fork so the MLIR revision matches
# the buddy tools (buddy-opt / buddy-llc / buddy-translate) used by the backend.
#
# Usage:
#   scripts/build-llvm.sh
#
# Environment:
#   TRITON_RISCV_CACHE_DIR   cache root (default: <repo>/.cache)
#   LLVM_INSTALL_DIR         install prefix (default: <cache>/llvm)
#   LLVM_BUILD_DIR           CMake build dir (default: <cache>/llvm-build)
#   LLVM_SRC_DIR             source checkout (default: <cache>/llvm-src)
#   TRITON_RISCV_LLVM_COMMIT buddy llvm-project commit to build
#   MAX_JOBS                 ninja parallelism (default: 32)
#   PYTHON                   interpreter for the (unused) MLIR bindings
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CACHE_DIR="${TRITON_RISCV_CACHE_DIR:-${ROOT_DIR}/.cache}"
SRC_DIR="${LLVM_SRC_DIR:-${CACHE_DIR}/llvm-src}"
BUILD_DIR="${LLVM_BUILD_DIR:-${CACHE_DIR}/llvm-build}"
INSTALL_DIR="${LLVM_INSTALL_DIR:-${CACHE_DIR}/llvm}"
LLVM_COMMIT="${TRITON_RISCV_LLVM_COMMIT:-3845a20590afedfbece4d000f97a6cfbbea3bf43}"
MAX_JOBS="${MAX_JOBS:-32}"

mkdir -p "${CACHE_DIR}"

if [ ! -d "${SRC_DIR}/.git" ]; then
    git clone --filter=blob:none https://github.com/Yranger/llvm-project.git "${SRC_DIR}"
fi
git -C "${SRC_DIR}" fetch --depth=1 origin "${LLVM_COMMIT}"
git -C "${SRC_DIR}" checkout -q "${LLVM_COMMIT}"
echo "LLVM source: $(git -C "${SRC_DIR}" log -1 --format='%H %s')"

cmake -G Ninja -S "${SRC_DIR}/llvm" -B "${BUILD_DIR}" \
    -DLLVM_ENABLE_PROJECTS="mlir;clang;lld" \
    -DLLVM_TARGETS_TO_BUILD="host;RISCV;NVPTX;AMDGPU" \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DCMAKE_BUILD_TYPE=RELEASE \
    -DLLVM_INSTALL_UTILS=ON \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}"

cmake --build "${BUILD_DIR}" -j "${MAX_JOBS}"
cmake --install "${BUILD_DIR}"

echo "LLVM installed to ${INSTALL_DIR}"
"${INSTALL_DIR}/bin/llvm-config" --targets-built
