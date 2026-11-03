#!/usr/bin/env bash
#
# Rebuild Triton and the triton-shared plugin from the current checkout and
# reinstall them into TRITON_VENV.
#
# Run it after changing the backend Python code, the C++ sources or the lowering
# pipeline:
#
#   source scripts/env.sh
#   scripts/rebuild.sh
#
set -euo pipefail

_rebuild_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_rebuild_repo_root="$(cd "${_rebuild_script_dir}/.." && pwd)"

# shellcheck source=scripts/env.sh
source "${_rebuild_repo_root}/scripts/env.sh"

if [[ ! -d "${TRITON_DIR}" ]]; then
  echo "TRITON_DIR does not exist: ${TRITON_DIR}" >&2
  echo "Run scripts/build.sh first, or set TRITON_DIR." >&2
  exit 1
fi

if [[ ! -x "${TRITON_VENV}/bin/python" ]]; then
  echo "python not found in TRITON_VENV: ${TRITON_VENV}" >&2
  echo "Activate your environment (venv or conda) and install build deps first." >&2
  exit 1
fi

if [[ ! -d "${LLVM_SYSPATH}" ]]; then
  echo "LLVM_SYSPATH does not exist: ${LLVM_SYSPATH}" >&2
  echo "Run scripts/build.sh first, or override LLVM_SYSPATH." >&2
  exit 1
fi

# Building the stock Triton checkout needs an LLVM with the NVPTX/AMDGPU targets
# and lld.
if ! "${LLVM_SYSPATH}/bin/llvm-config" --targets-built 2>/dev/null | grep -qw NVPTX; then
  echo "warning: ${LLVM_SYSPATH} does not provide NVPTX; run scripts/build.sh first" >&2
fi

_expected_python_tag="$("${TRITON_VENV}/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

# CMake caches the source and build directories, so a build tree created for a
# different Python version or from a checkout that has since moved must go.
if [[ -n "${BUILD_DIR:-}" && -d "${BUILD_DIR}" ]]; then
  _reconfigure_build_dir=0

  if [[ "${BUILD_DIR}" != *"cpython-${_expected_python_tag}" ]]; then
    _reconfigure_build_dir=1
  fi

  if [[ -f "${BUILD_DIR}/CMakeCache.txt" ]]; then
    _cached_build_root="$(sed -n 's|^# For build in directory: ||p' "${BUILD_DIR}/CMakeCache.txt" | head -n1)"
    if [[ -n "${_cached_build_root}" && "${_cached_build_root}" != "${BUILD_DIR}" ]]; then
      _reconfigure_build_dir=1
    fi
  fi

  if [[ "${_reconfigure_build_dir}" -eq 1 ]]; then
    echo "Removing stale Triton build directory: ${BUILD_DIR}" >&2
    rm -rf "${BUILD_DIR}"
    unset BUILD_DIR
    unset TRITON_SHARED_OPT_PATH
  fi
fi

# setuptools/wheel reuse staging directories under triton/build; drop them so a
# previous build cannot leak files into the next wheel.
if [[ -d "${TRITON_DIR}/build" ]]; then
  find "${TRITON_DIR}/build" -maxdepth 1 -type d \( -name 'lib.*' -o -name 'bdist.*' \) -print -exec rm -rf {} +
fi

PYTHON="${TRITON_VENV}/bin/python" "${_rebuild_repo_root}/scripts/install-dev.sh"

# A fresh build may have created a new build tree, so locate it again.
if [[ -z "${BUILD_DIR:-}" || ! -d "${BUILD_DIR}" ]]; then
  BUILD_DIR="$(
    find "${TRITON_DIR}/build" -maxdepth 1 -mindepth 1 -type d -name "cmake.linux-*-cpython-${_expected_python_tag}" 2>/dev/null | sort | head -n1 || true
  )"
fi
if [[ -z "${BUILD_DIR:-}" || ! -d "${BUILD_DIR}" ]]; then
  echo "Unable to locate the Triton build directory under ${TRITON_DIR}/build" >&2
  exit 1
fi
TRITON_SHARED_OPT_PATH="${BUILD_DIR}/third_party/triton_shared/tools/triton-shared-opt/triton-shared-opt"
if [[ ! -x "${TRITON_SHARED_OPT_PATH}" ]]; then
  echo "triton-shared-opt not found or not executable: ${TRITON_SHARED_OPT_PATH}" >&2
  exit 1
fi

"${TRITON_VENV}/bin/python" -c "import triton; import triton_riscv.compiler as c; print(triton.__version__); print(c.__file__)"
"${TRITON_SHARED_OPT_PATH}" --version

unset _rebuild_script_dir _rebuild_repo_root
unset _expected_python_tag _reconfigure_build_dir _cached_build_root
