#!/usr/bin/env bash
#
# Development environment for a triton-riscv source checkout.
#
# Source it (do not execute it) before building or running anything from the
# repository:
#
#   source scripts/env.sh
#
# It locates the Triton checkout, the buddy-mlir/LLVM toolchain and the build
# tree, disables the host-specific GPU toolchain downloads that upstream Triton
# would otherwise attempt (see scripts/gpu-stub-env.sh), and exports the
# variables the backend reads at runtime. Every value can be overridden by
# exporting it beforehand.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Source this script instead of executing it: source scripts/env.sh" >&2
  exit 1
fi

_triton_riscv_env_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_triton_riscv_repo_root="$(cd "${_triton_riscv_env_dir}/.." && pwd)"
_triton_riscv_parent="$(cd "${_triton_riscv_repo_root}/.." && pwd)"

TRITON_RISCV_DIR="${TRITON_RISCV_DIR:-${_triton_riscv_repo_root}}"
# Same location scripts/build.sh clones into (and .gitignore ignores).
TRITON_DIR="${TRITON_DIR:-${TRITON_RISCV_DIR}/triton}"
BUDDY_DIR="${BUDDY_DIR:-${_triton_riscv_parent}/buddy-mlir}"
_default_triton_venv="${TRITON_RISCV_DIR}/.venv"

if [[ -n "${CONDA_PREFIX:-}" && -x "${CONDA_PREFIX}/bin/python" && ( -z "${TRITON_VENV:-}" || "${TRITON_VENV}" == "${_default_triton_venv}" ) ]]; then
  TRITON_VENV="${CONDA_PREFIX}"
elif [[ -z "${TRITON_VENV:-}" ]]; then
  if [[ -n "${CONDA_PREFIX:-}" && -x "${CONDA_PREFIX}/bin/python" ]]; then
    TRITON_VENV="${CONDA_PREFIX}"
  else
    TRITON_VENV="${_default_triton_venv}"
  fi
fi

# Compilation caches and dumps. TRITON_DUMP_DIR/TRITON_OVERRIDE_DIR are only
# used when the backend is asked to dump intermediate IR.
TRITON_HOME="${TRITON_HOME:-${HOME}}"
TRITON_RUNTIME_ROOT="${TRITON_RUNTIME_ROOT:-${HOME}/.triton}"
TRITON_CACHE_DIR="${TRITON_CACHE_DIR:-${TRITON_RUNTIME_ROOT}/cache}"
TRITON_DUMP_DIR="${TRITON_DUMP_DIR:-${TRITON_RUNTIME_ROOT}/dump}"
TRITON_OVERRIDE_DIR="${TRITON_OVERRIDE_DIR:-${TRITON_RUNTIME_ROOT}/override}"
TRITON_SHARED_DUMP_PATH="${TRITON_SHARED_DUMP_PATH:-${TRITON_DUMP_DIR}/shared}"

# The CMake build tree Triton and the triton-shared plugin are compiled into.
if [[ -z "${BUILD_DIR:-}" ]]; then
  _detected_python_tag=""
  if [[ -x "${TRITON_VENV}/bin/python" ]]; then
    _detected_python_tag="$("${TRITON_VENV}/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  fi

  _detected_build_dir=""
  if [[ -n "${_detected_python_tag}" ]]; then
    _detected_build_dir="$(
      find "${TRITON_DIR}/build" -maxdepth 1 -mindepth 1 -type d -name "cmake.linux-*-cpython-${_detected_python_tag}" 2>/dev/null | sort | head -n1 || true
    )"
  fi
  if [[ -z "${_detected_build_dir}" ]]; then
    _detected_build_dir="$(
      find "${TRITON_DIR}/build" -maxdepth 1 -mindepth 1 -type d -name 'cmake.linux-*-cpython-*' 2>/dev/null | sort | head -n1 || true
    )"
  fi

  BUILD_DIR="${_detected_build_dir}"
fi

# The triton-shared-opt executable the backend shells out to at compile time.
if [[ -z "${TRITON_SHARED_OPT_PATH:-}" && -x "${BUILD_DIR}/third_party/triton_shared/tools/triton-shared-opt/triton-shared-opt" ]]; then
  TRITON_SHARED_OPT_PATH="${BUILD_DIR}/third_party/triton_shared/tools/triton-shared-opt/triton-shared-opt"
fi

# LLVM: prefer an explicit LLVM_SYSPATH, then the release scripts/build.sh
# downloads from buddy-mlir, then a locally built buddy-mlir LLVM.
if [[ -z "${LLVM_SYSPATH:-}" ]]; then
  if [[ -d "${TRITON_RISCV_DIR}/.cache/llvm" ]]; then
    LLVM_SYSPATH="${TRITON_RISCV_DIR}/.cache/llvm"
  else
    LLVM_SYSPATH="${BUDDY_DIR}/llvm/build"
  fi
fi

# buddy tools (buddy-opt/buddy-llc): prefer the release scripts/build.sh
# downloads, then a locally built buddy-mlir.
if [[ -z "${BUDDY_MLIR_BINARY_DIR:-}" ]]; then
  if [[ -d "${TRITON_RISCV_DIR}/.cache/buddy/bin" ]]; then
    BUDDY_MLIR_BINARY_DIR="${TRITON_RISCV_DIR}/.cache/buddy/bin"
  else
    BUDDY_MLIR_BINARY_DIR="${BUDDY_DIR}/build/bin"
  fi
fi

JSON_SYSPATH="${JSON_SYSPATH:-${TRITON_RUNTIME_ROOT}/json}"
LLVM_BINARY_DIR="${LLVM_BINARY_DIR:-${LLVM_SYSPATH}/bin}"

# Optional cross toolchain for producing and running RVV ELF binaries (see
# docs/06-RISCV-QEMU.md).
RISCV_GNU_TOOLCHAIN_DIR="${RISCV_GNU_TOOLCHAIN_DIR:-${BUDDY_DIR}/build-for-triton-riscv/thirdparty/riscv-gnu-toolchain}"
if [[ -x "${RISCV_GNU_TOOLCHAIN_DIR}/bin/riscv64-unknown-linux-gnu-gcc" ]]; then
  TRITON_RISCV_CC="${TRITON_RISCV_CC:-${RISCV_GNU_TOOLCHAIN_DIR}/bin/riscv64-unknown-linux-gnu-gcc}"
  TRITON_RISCV_OBJDUMP="${TRITON_RISCV_OBJDUMP:-${RISCV_GNU_TOOLCHAIN_DIR}/bin/riscv64-unknown-linux-gnu-objdump}"
  TRITON_RISCV_SYSROOT="${TRITON_RISCV_SYSROOT:-${RISCV_GNU_TOOLCHAIN_DIR}/sysroot}"
fi
if [[ -x "${RISCV_GNU_TOOLCHAIN_DIR}/bin/qemu-riscv64" ]]; then
  TRITON_RISCV_QEMU="${TRITON_RISCV_QEMU:-${RISCV_GNU_TOOLCHAIN_DIR}/bin/qemu-riscv64}"
fi
TRITON_RISCV_LOWERING_MODE="${TRITON_RISCV_LOWERING_MODE:-linalg_loops}"

# Upstream Triton downloads host-specific GPU toolchains at build time; those do
# not exist for riscv64. Disable them for every build done from this shell.
# shellcheck source=scripts/gpu-stub-env.sh
source "${TRITON_RISCV_DIR}/scripts/gpu-stub-env.sh" "${TRITON_RISCV_DIR}/.cache/gpu-deps-stub"

export TRITON_RISCV_DIR
export TRITON_DIR
export BUDDY_DIR
export TRITON_VENV
export TRITON_HOME
export TRITON_RUNTIME_ROOT
export TRITON_CACHE_DIR
export TRITON_DUMP_DIR
export TRITON_OVERRIDE_DIR
export TRITON_SHARED_DUMP_PATH
export BUILD_DIR
export TRITON_SHARED_OPT_PATH
export LLVM_SYSPATH
export LLVM_BINARY_DIR
export BUDDY_MLIR_BINARY_DIR
export JSON_SYSPATH
export RISCV_GNU_TOOLCHAIN_DIR
export TRITON_RISCV_CC
export TRITON_RISCV_OBJDUMP
export TRITON_RISCV_SYSROOT
export TRITON_RISCV_QEMU
export TRITON_RISCV_LOWERING_MODE
# Needed by Triton's build to compile the triton-shared plugin alongside it.
export TRITON_PLUGIN_DIRS="${TRITON_RISCV_DIR}"
export PATH="${TRITON_VENV}/bin:${LLVM_BINARY_DIR}:${BUDDY_MLIR_BINARY_DIR}:${PATH}"
# Keep the repository's own triton/ checkout from shadowing the installed one.
export PYTHONSAFEPATH=1

unset _triton_riscv_env_dir
unset _triton_riscv_repo_root
unset _triton_riscv_parent
unset _default_triton_venv
unset _detected_python_tag
unset _detected_build_dir
