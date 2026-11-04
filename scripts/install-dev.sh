#!/usr/bin/env bash
#
# Build and install the current checkout for development.
#
#   1. Install Triton from TRITON_DIR. TRITON_PLUGIN_DIRS is deliberately unset:
#      it makes setup.py symlink the plugin into Triton's own package and
#      register a second `triton_shared` entry point next to this repository's.
#   2. Add the plugin to Triton's CMake build tree and build it. Triton's
#      CMakeLists reads TRITON_PLUGIN_DIRS as a plain CMake variable, so the
#      plugin can take part in the build without setuptools getting involved.
#      This is what produces the triton-shared-opt executable the backend
#      invokes at compile time.
#   3. Install this repository, which provides the triton_riscv package, its
#      `triton_shared` entry point and the triton-shared-opt console script.
#
# scripts/build.sh and scripts/rebuild.sh both end up here.
#
# Environment: see scripts/env.sh, which this script sources. Set PYTHON to
# install into a different interpreter.
set -euo pipefail

_install_dev_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_install_dev_repo_root="$(cd "${_install_dev_dir}/.." && pwd)"

# shellcheck source=scripts/env.sh
source "${_install_dev_dir}/env.sh"

PYTHON="${PYTHON:-${TRITON_VENV}/bin/python}"

echo "Installing Triton into ${PYTHON}..."
unset TRITON_PLUGIN_DIRS
PIP_DISABLE_PIP_VERSION_CHECK=1 "${PYTHON}" -m pip install --no-build-isolation -e "${TRITON_DIR}"

_expected_python_tag="$("${PYTHON}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
TRITON_BUILD_DIR="$(
    find "${TRITON_DIR}/build" -maxdepth 1 -mindepth 1 -type d -name "cmake.linux-*-cpython-${_expected_python_tag}" 2>/dev/null | sort | head -n1
)"
if [[ -z "${TRITON_BUILD_DIR}" ]]; then
    echo "Unable to locate the Triton build directory under ${TRITON_DIR}/build" >&2
    exit 1
fi

echo "Building the triton-shared plugin in ${TRITON_BUILD_DIR}..."
# TRITON_WHEEL_DIR is Triton's wheel staging directory. setup.py points it at the
# package directory, so with an editable install the plugin's POST_BUILD copy
# drops triton-shared-opt into the source tree. This is not a wheel build, so
# point it inside the build tree instead (it must be defined: Triton's
# CMakeLists errors out otherwise).
cmake -DTRITON_PLUGIN_DIRS="${_install_dev_repo_root}" \
    -DTRITON_WHEEL_DIR="${TRITON_BUILD_DIR}/wheel-staging" \
    "${TRITON_BUILD_DIR}"
cmake --build "${TRITON_BUILD_DIR}" -j "${MAX_JOBS:-$(nproc)}"

echo "Installing the triton_riscv package..."
PIP_DISABLE_PIP_VERSION_CHECK=1 "${PYTHON}" -m pip install --no-build-isolation -e "${_install_dev_repo_root}"

unset _install_dev_dir _install_dev_repo_root _expected_python_tag TRITON_BUILD_DIR
