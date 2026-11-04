#!/usr/bin/env bash
#
# Rebuild Triton and the triton-shared plugin from the current checkout and
# reinstall them into TRITON_VENV. Run it after changing the backend Python
# code, the C++ sources or the lowering pipeline (scripts/build.sh must have
# run once):
#
#   source scripts/env.sh
#   scripts/rebuild.sh
#
set -euo pipefail

_rebuild_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/env.sh
source "${_rebuild_repo_root}/scripts/env.sh"

# setuptools/wheel reuse staging directories under triton/build; drop them so a
# previous build cannot leak files into the next wheel.
find "${TRITON_DIR}/build" -maxdepth 1 -type d \( -name 'lib.*' -o -name 'bdist.*' \) -exec rm -rf {} + 2>/dev/null || true

PYTHON="${TRITON_VENV}/bin/python" "${_rebuild_repo_root}/scripts/_install-dev.sh"

# Pick up a build tree the rebuild just created.
# shellcheck source=scripts/env.sh
source "${_rebuild_repo_root}/scripts/env.sh"

"${TRITON_VENV}/bin/python" -c "import triton; import triton_riscv.compiler as c; print(triton.__version__); print(c.__file__)"
"${TRITON_VENV}/bin/triton-shared-opt" --version
