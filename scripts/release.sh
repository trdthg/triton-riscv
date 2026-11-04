#!/usr/bin/env bash

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: $0 <py_tag> <x86_64|riscv64>" >&2
    echo "example: $0 cp312-cp312 x86_64" >&2
    echo "         $0 cp312 x86_64" >&2
    exit 1
fi

PY_TAG="$1"
TARGET_ARCH="$2"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${PY_TAG}" =~ ^cp[0-9]+$ ]]; then
    PY_TAG="${PY_TAG}-${PY_TAG}"
fi

OUTPUT_DIR="${REPO_ROOT}/build/release/${TARGET_ARCH}/${PY_TAG}"
CONTAINER_PLUGIN_DIR=/workspace/triton-riscv
CONTAINER_TRITON_DIR="${CONTAINER_PLUGIN_DIR}/triton"
CONTAINER_OUTPUT_DIR="${CONTAINER_PLUGIN_DIR}/build/release/${TARGET_ARCH}/${PY_TAG}"

case "${TARGET_ARCH}" in
    x86_64)
        MANYLINUX_IMAGE="quay.io/pypa/manylinux_2_28_x86_64:latest"
        DOCKER_PLATFORM="linux/amd64"
        ;;
    riscv64)
        MANYLINUX_IMAGE="quay.io/pypa/manylinux_2_39_riscv64:latest"
        DOCKER_PLATFORM="linux/riscv64"
        ;;
    *)
        echo "unsupported target arch: ${TARGET_ARCH}" >&2
        exit 1
        ;;
esac

if [ -z "${IN_DOCKER:-}" ]; then
    mkdir -p "${OUTPUT_DIR}"

    DOCKER_RUN_ARGS=(run --rm -i)

    HOST_ARCH_RAW="$(uname -m)"
    case "${HOST_ARCH_RAW}" in
        amd64)
            HOST_ARCH="x86_64"
            ;;
        *)
            HOST_ARCH="${HOST_ARCH_RAW}"
            ;;
    esac

    # Support cross-compile
    if [ "${HOST_ARCH}" != "${TARGET_ARCH}" ]; then
        DOCKER_RUN_ARGS+=(--platform "${DOCKER_PLATFORM}")
    fi

    DOCKER_ENV_ARGS=()
    for proxy_var in http_proxy https_proxy ftp_proxy no_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY NO_PROXY ALL_PROXY all_proxy; do
        if [ -n "${!proxy_var:-}" ]; then
            DOCKER_ENV_ARGS+=(-e "${proxy_var}=${!proxy_var}")
        fi
    done
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        DOCKER_ENV_ARGS+=(-e GITHUB_TOKEN)
    fi

    docker "${DOCKER_RUN_ARGS[@]}" \
        "${DOCKER_ENV_ARGS[@]}" \
        -e IN_DOCKER=1 \
        -e PY_TAG="${PY_TAG}" \
        -e TARGET_ARCH="${TARGET_ARCH}" \
        -e BUILD_TRITON_RISCV_WHEEL="${BUILD_TRITON_RISCV_WHEEL:-1}" \
        -e HOST_UID="$(id -u)" \
        -e HOST_GID="$(id -g)" \
        -e HOME=/workspace \
        -v "${REPO_ROOT}:${CONTAINER_PLUGIN_DIR}" \
        -v /tmp/triton_riscv_docker_dnf_cache:/var/cache/dnf \
        -v /tmp/triton_riscv_docker_pip_cache:/workspace/.cache/pip \
        -w "${CONTAINER_PLUGIN_DIR}" \
        "${MANYLINUX_IMAGE}" \
        /bin/bash ./scripts/release.sh "${PY_TAG}" "${TARGET_ARCH}"

    echo "wheels are in ${OUTPUT_DIR}"
    exit 0
fi

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if [ -n "${RAW_WHEEL_DIR:-}" ]; then
        rm -rf "${RAW_WHEEL_DIR}"
    fi
    if [ -n "${STASHED_TRITON_SHARED_OPT:-}" ]; then
        rm -f "${STASHED_TRITON_SHARED_OPT}"
    fi
    if [ -e "${CONTAINER_OUTPUT_DIR}" ]; then
        chown -R "${HOST_UID}:${HOST_GID}" "${CONTAINER_OUTPUT_DIR}"
    fi
    if [ -e "${CONTAINER_TRITON_DIR}/build" ]; then
        chown -R "${HOST_UID}:${HOST_GID}" "${CONTAINER_TRITON_DIR}/build"
    fi
    exit "${status}"
}
trap cleanup EXIT INT TERM

export PYTHON="/opt/python/${PY_TAG}/bin/python"
export PATH="/opt/python/${PY_TAG}/bin:$PATH"

if [ -f /opt/rh/gcc-toolset-14/enable ]; then
    source /opt/rh/gcc-toolset-14/enable
fi

dnf install -y clang lld git

export TRITON_PYTHON_TAG="${PY_TAG}"

# shellcheck source=scripts/gpu-stub-env.sh
source "${CONTAINER_PLUGIN_DIR}/scripts/gpu-stub-env.sh" "${CONTAINER_PLUGIN_DIR}/.cache/gpu-deps-stub"

# scripts/build.sh builds the stock Triton checkout together with the
# triton-shared plugin, downloading the LLVM and buddy tools it needs, and
# produces the standalone triton-shared-opt executable the backend invokes at
# compile time.
rm -rf "${CONTAINER_TRITON_DIR}/build"
"${CONTAINER_PLUGIN_DIR}/scripts/build.sh"

# The frontend wheel below is built outside build.sh, so point it at the
# toolchains build.sh just populated.
export LLVM_SYSPATH="${CONTAINER_PLUGIN_DIR}/.cache/llvm"
export LLVM_BINARY_DIR="${LLVM_SYSPATH}/bin"
export BUDDY_MLIR_BINARY_DIR="${CONTAINER_PLUGIN_DIR}/.cache/buddy/bin"

# Stash the freshly built tool: the frontend wheel build below wipes the CMake
# build tree, but the backend wheel still needs the executable.
_found_tool="$(
    find "${CONTAINER_TRITON_DIR}/build" -type f \
        -path '*/third_party/triton_shared/tools/triton-shared-opt/triton-shared-opt' \
        -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true
)"
if [[ -z "${_found_tool}" || ! -f "${_found_tool}" ]]; then
    echo "ERROR: built triton-shared-opt not found under ${CONTAINER_TRITON_DIR}/build" >&2
    exit 1
fi
STASHED_TRITON_SHARED_OPT="$(mktemp)"
cp "${_found_tool}" "${STASHED_TRITON_SHARED_OPT}"
unset _found_tool

# 1) The stock Triton wheel: frontend only. The triton-shared backend is
#    shipped exclusively by the triton-riscv wheel below.
rm -rf "${CONTAINER_OUTPUT_DIR}" "${CONTAINER_TRITON_DIR}/build"
mkdir -p "${CONTAINER_OUTPUT_DIR}"
RAW_WHEEL_DIR="$(mktemp -d)"

cd "${CONTAINER_TRITON_DIR}"
"${PYTHON}" setup.py bdist_wheel -d "${RAW_WHEEL_DIR}"
auditwheel repair "${RAW_WHEEL_DIR}"/*.whl -w "${CONTAINER_OUTPUT_DIR}"
rm -rf "${RAW_WHEEL_DIR}"

# 2) The standalone triton-riscv backend package, bundling the stashed
#    triton-shared-opt. It is py3-none-<arch>, so it only needs to be built once
#    per architecture; the release workflow sets BUILD_TRITON_RISCV_WHEEL=1 for a
#    single Python version.
if [[ "${BUILD_TRITON_RISCV_WHEEL:-1}" == "1" ]]; then
    PYTHON="${PYTHON}" TRITON_SHARED_OPT_BINARY="${STASHED_TRITON_SHARED_OPT}" \
        "${CONTAINER_PLUGIN_DIR}/scripts/build-backend-wheel.sh" \
        "${CONTAINER_PLUGIN_DIR}" "${CONTAINER_TRITON_DIR}" "${CONTAINER_OUTPUT_DIR}"
fi
