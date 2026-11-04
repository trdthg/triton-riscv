#!/usr/bin/env bash
#
# Build and install: Triton with the C++ triton-shared plugin, then this
# repository's triton_riscv package. Run scripts/setup.sh once first -- the
# Makefile's `all` target and `make setup` do that for you.
#
# Environment: see scripts/env.sh. Set PYTHON to build into another interpreter.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/env.sh
source "${ROOT_DIR}/scripts/env.sh"

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

# Stage the freshly built tool where the package looks for it -- release.sh does
# the same for the wheel -- so a source checkout resolves it the same way.
_python_tag="$("${PYTHON}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
mkdir -p "${TRITON_RISCV_DIR}/backend/bin"
ln -sfn ${TRITON_DIR}/build/cmake.linux-*-cpython-${_python_tag}/third_party/triton_shared/tools/triton-shared-opt/triton-shared-opt \
    "${TRITON_RISCV_DIR}/backend/bin/triton-shared-opt"
unset _python_tag

"${PYTHON}" -m pip install --no-build-isolation -e "${TRITON_RISCV_DIR}"

"${PYTHON}" -c "import triton; import triton_riscv.compiler as c; print(triton.__version__); print(c.__file__)"
"${TRITON_VENV}/bin/triton-shared-opt" --version
