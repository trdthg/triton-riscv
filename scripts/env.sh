#!/usr/bin/env bash
#
# Development environment for a triton-riscv source checkout. Source it, do not
# execute it:
#
#   source scripts/env.sh
#
# Export any of the values below beforehand to override them.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Source this script instead of executing it: source scripts/env.sh" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Locations
# ---------------------------------------------------------------------------

TRITON_RISCV_DIR="${TRITON_RISCV_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TRITON_DIR="${TRITON_DIR:-${TRITON_RISCV_DIR}/triton}"
BUDDY_DIR="${BUDDY_DIR:-$(cd "${TRITON_RISCV_DIR}/.." && pwd)/buddy-mlir}"
TRITON_VENV="${TRITON_VENV:-${CONDA_PREFIX:-${TRITON_RISCV_DIR}/.venv}}"

# The toolchains scripts/build.sh downloads.
LLVM_SYSPATH="${LLVM_SYSPATH:-${TRITON_RISCV_DIR}/.cache/llvm}"
LLVM_BINARY_DIR="${LLVM_BINARY_DIR:-${LLVM_SYSPATH}/bin}"
BUDDY_MLIR_BINARY_DIR="${BUDDY_MLIR_BINARY_DIR:-${TRITON_RISCV_DIR}/.cache/buddy/bin}"

# ---------------------------------------------------------------------------
# Build time
# ---------------------------------------------------------------------------

# Upstream Triton downloads host-specific GPU toolchains that riscv64 has no
# builds for; disable them for every build started from this shell.
# shellcheck source=scripts/_gpu-stub-env.sh
source "${TRITON_RISCV_DIR}/scripts/_gpu-stub-env.sh" "${TRITON_RISCV_DIR}/.cache/gpu-deps-stub"

# ---------------------------------------------------------------------------
# Run time
# ---------------------------------------------------------------------------

# Read by Triton.
TRITON_HOME="${TRITON_HOME:-${HOME}}"
TRITON_CACHE_DIR="${TRITON_CACHE_DIR:-${TRITON_HOME}/.triton/cache}"
TRITON_DUMP_DIR="${TRITON_DUMP_DIR:-${TRITON_HOME}/.triton/dump}"
TRITON_OVERRIDE_DIR="${TRITON_OVERRIDE_DIR:-${TRITON_HOME}/.triton/override}"

# Read by the backend. The freshly built triton-shared-opt is pointed at even
# when missing, so that a stale copy under backend/bin/ is never used silently.
_python_tag="$("${TRITON_VENV}/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
BUILD_DIR="$(find "${TRITON_DIR}/build" -maxdepth 1 -mindepth 1 -type d -name "cmake.linux-*-cpython-${_python_tag:-*}" 2>/dev/null | sort | head -n1)"
unset _python_tag
TRITON_SHARED_OPT_PATH="${TRITON_SHARED_OPT_PATH:-${BUILD_DIR}/third_party/triton_shared/tools/triton-shared-opt/triton-shared-opt}"
TRITON_SHARED_DUMP_PATH="${TRITON_SHARED_DUMP_PATH:-${TRITON_DUMP_DIR}/shared}"

# ---------------------------------------------------------------------------
# Shell
# ---------------------------------------------------------------------------

export TRITON_RISCV_DIR TRITON_DIR BUDDY_DIR TRITON_VENV
export LLVM_SYSPATH LLVM_BINARY_DIR BUDDY_MLIR_BINARY_DIR
export TRITON_HOME TRITON_CACHE_DIR TRITON_DUMP_DIR TRITON_OVERRIDE_DIR
export TRITON_SHARED_OPT_PATH TRITON_SHARED_DUMP_PATH
export PATH="${TRITON_VENV}/bin:${LLVM_BINARY_DIR}:${BUDDY_MLIR_BINARY_DIR}:${PATH}"
# Keep the repository's own triton/ checkout from shadowing the installed one.
export PYTHONSAFEPATH=1
