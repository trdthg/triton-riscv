#!/usr/bin/env bash
# Build and install the current checkout: Triton with the C++ triton-shared
# plugin, then this repository's triton_riscv package. Needs scripts/env.sh's
# environment. Set PYTHON to install into a different interpreter.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
PYTHON="${PYTHON:-${TRITON_VENV}/bin/python}"

# Build with clang, as the official Triton wheels do: clang tolerates the
# "deprecated aggregate builder" pattern MLIR's generated code uses, while gcc
# turns it into an error under Triton's -Werror. Select it via CC/CXX rather
# than TRITON_BUILD_WITH_CLANG_LLD, which would also force lld.
export CC="${CC:-clang}"
export CXX="${CXX:-clang++}"

# setup.py must not see TRITON_PLUGIN_DIRS: it would symlink the backend into
# triton.backends and register a second `triton_shared` entry point. Its CMake
# side only needs the same path as a CMake variable, and TRITON_APPEND_CMAKE_ARGS
# is appended after setup.py's own arguments, so it wins. TRITON_WHEEL_DIR is
# redirected too, so the plugin's POST_BUILD copy does not land in the source
# tree (setup.py points it at the package directory).
export TRITON_APPEND_CMAKE_ARGS="-DTRITON_PLUGIN_DIRS=${TRITON_RISCV_DIR} -DTRITON_WHEEL_DIR=${TRITON_DIR}/build/wheel-staging${TRITON_APPEND_CMAKE_ARGS:+ ${TRITON_APPEND_CMAKE_ARGS}}"

"${PYTHON}" -m pip install --no-build-isolation -e "${TRITON_DIR}"
"${PYTHON}" -m pip install --no-build-isolation -e "${TRITON_RISCV_DIR}"
