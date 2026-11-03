#!/usr/bin/env bash
#
# Build the standalone `triton-riscv` wheel with the compiled
# `triton-shared-opt` executable bundled into the package.
#
# Run this after Triton (with the triton-shared plugin) has been built, so that
# the freshly built tool can be located under <triton_dir>/build. scripts/release.sh
# calls it after building the plugin; it also works standalone for local
# packaging checks.
#
# Usage:
#   build-triton-riscv-wheel.sh <repo_root> <triton_dir> <output_dir>
#
# Environment:
#   PYTHON                    interpreter used to build/repair the wheel
#                             (default: python3)
#   TRITON_SHARED_OPT_BINARY  explicit path to an already-built triton-shared-opt;
#                             when unset, the newest one under <triton_dir>/build
#                             is used
#   TRITON_RISCV_SKIP_REPAIR  set to 1 to skip `auditwheel repair` (local dev)
set -euo pipefail

if [ $# -ne 3 ]; then
    echo "usage: $0 <repo_root> <triton_dir> <output_dir>" >&2
    exit 1
fi

REPO_ROOT="$(realpath "$1")"
TRITON_DIR="$(realpath "$2")"
OUTPUT_DIR="$3"
PYTHON="${PYTHON:-python3}"

mkdir -p "${OUTPUT_DIR}"

STAGED_BIN="${REPO_ROOT}/backend/bin/triton-shared-opt"
RAW_WHEEL_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "${RAW_WHEEL_DIR}"
    rm -f "${STAGED_BIN}"
}
trap cleanup EXIT

# Locate the freshly built tool. An explicit path wins (release.sh stashes the
# executable because the frontend wheel build wipes the CMake build tree);
# otherwise use the newest one under <triton_dir>/build.
if [[ -n "${TRITON_SHARED_OPT_BINARY:-}" ]]; then
    TRITON_SHARED_OPT="${TRITON_SHARED_OPT_BINARY}"
else
    TRITON_SHARED_OPT="$(
        find "${TRITON_DIR}/build" -type f \
            -path '*/third_party/triton_shared/tools/triton-shared-opt/triton-shared-opt' \
            -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true
    )"
fi
if [[ -z "${TRITON_SHARED_OPT:-}" || ! -f "${TRITON_SHARED_OPT}" ]]; then
    echo "ERROR: triton-shared-opt not found (set TRITON_SHARED_OPT_BINARY or build it under ${TRITON_DIR}/build)" >&2
    exit 1
fi

echo "Bundling triton-shared-opt: ${TRITON_SHARED_OPT}"
mkdir -p "$(dirname "${STAGED_BIN}")"
install -m755 "${TRITON_SHARED_OPT}" "${STAGED_BIN}"
# The tool is statically linked against MLIR/LLVM and ships with debug info;
# stripping takes it from hundreds of MB down to well under a hundred.
strip --strip-unneeded "${STAGED_BIN}" 2>/dev/null || true

# The PEP 517 build backend must be importable because we build without
# isolation (the manylinux images already provide matching setuptools/wheel).
if ! "${PYTHON}" -c "import setuptools, wheel" >/dev/null 2>&1; then
    "${PYTHON}" -m pip install --quiet --disable-pip-version-check "setuptools>=64" wheel
fi

"${PYTHON}" -m pip wheel \
    --no-build-isolation --no-deps --disable-pip-version-check \
    --wheel-dir "${RAW_WHEEL_DIR}" \
    "${REPO_ROOT}"

shopt -s nullglob
raw_wheels=("${RAW_WHEEL_DIR}"/*.whl)
if [[ "${#raw_wheels[@]}" -ne 1 ]]; then
    echo "ERROR: expected exactly one built wheel, found ${#raw_wheels[@]}" >&2
    exit 1
fi

if [[ "${TRITON_RISCV_SKIP_REPAIR:-0}" == "1" ]]; then
    cp "${raw_wheels[0]}" "${OUTPUT_DIR}/"
else
    auditwheel repair "${raw_wheels[@]}" -w "${OUTPUT_DIR}"
fi

echo "Backend wheel(s) in ${OUTPUT_DIR}:"
ls -1 "${OUTPUT_DIR}"/*.whl
