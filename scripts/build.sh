#!/usr/bin/env bash
#
# Fetch the pinned Triton checkout plus the LLVM and buddy tools it needs, build
# the triton-shared plugin and install everything into the virtualenv.
#
#   scripts/build.sh
#
# Safe to re-run: cached downloads and the existing build tree are reused.
#
# Environment:
#   PYTHON       interpreter to install into (default: <repo>/.venv/bin/python)
#   LLVM_SYSPATH use this LLVM instead of downloading the buddy-mlir release
#   MAX_JOBS     build parallelism (read by Triton's setup.py)
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRITON_DIR="${ROOT_DIR}/triton"
TRITON_HASH="$(<"${ROOT_DIR}/triton-hash.txt")"
CACHE_DIR="${ROOT_DIR}/.cache"

BUDDY_PYTHON_TAG="cp312-abi3"
BUDDY_RELEASE_TAG="$(tail -n 1 "${ROOT_DIR}/buddy-hash.txt")"
BUDDY_RELEASE_VERSION="${BUDDY_RELEASE_TAG#release/v}"
BUDDY_RELEASE_VERSION="${BUDDY_RELEASE_VERSION#nightly/v}"
BUDDY_RELEASE_URL="https://github.com/buddy-compiler/buddy-mlir/releases/download/${BUDDY_RELEASE_TAG}"

if [[ -z "${PYTHON:-}" ]]; then
    PYTHON="${ROOT_DIR}/.venv/bin/python"
    [ -x "${PYTHON}" ] || python3 -m venv "${ROOT_DIR}/.venv"
fi

case "$(uname -m)" in
    x86_64|amd64)
        BUDDY_PLATFORM="manylinux_2_28_x86_64"
        PIP_INDEX_ARGS=()
        ;;
    riscv64)
        BUDDY_PLATFORM="manylinux_2_39_riscv64"
        # Connection to https://ruyirepo.ruyicommunity.cn/pypi/simple/ is poor
        PIP_INDEX_ARGS=(--index-url https://gitlab.com/api/v4/projects/56254198/packages/pypi/simple)
        ;;
    *)
        echo "unsupported arch: $(uname -m)" >&2
        exit 1
        ;;
esac

# Unpack a buddy-mlir release into <dir>, mirroring the <dir>/bin layout the
# rest of the tooling expects. Skips the download when already unpacked.
download_release() {
    local name="$1"
    local url="$2"
    local dir="$3"

    if [ -d "${dir}/bin" ]; then
        return
    fi
    echo "Downloading ${name} from ${url}..."
    rm -rf "${dir}"
    mkdir -p "${dir}"
    curl -fL "${url}" | tar -xzf - -C "${dir}"
}

# Triton links the NVPTX/AMDGPU codegen libraries and lld unconditionally, and
# the buddy-mlir LLVM release provides them. An explicit LLVM_SYSPATH is used
# as-is instead of downloading.
if [[ -z "${LLVM_SYSPATH:-}" ]]; then
    download_release llvm \
        "${BUDDY_RELEASE_URL}/llvm-24.0.0git-${BUDDY_PYTHON_TAG}-${BUDDY_PLATFORM}.tar.gz" \
        "${CACHE_DIR}/llvm"
    LLVM_SYSPATH="${CACHE_DIR}/llvm"
fi
LLVM_BINARY_DIR="${LLVM_SYSPATH}/bin"

download_release buddy \
    "${BUDDY_RELEASE_URL}/buddy-${BUDDY_RELEASE_VERSION}-${BUDDY_PYTHON_TAG}-${BUDDY_PLATFORM}.tar.gz" \
    "${CACHE_DIR}/buddy"
BUDDY_MLIR_BINARY_DIR="${CACHE_DIR}/buddy/bin"

# Keep the token out of the repository's remote URL while authenticating CI
# clones and fetches. Without a token, Git remains usable for local builds.
GIT_AUTH_ARGS=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    GIT_AUTH_HEADER="$(printf 'x-access-token:%s' "${GITHUB_TOKEN}" | base64 | tr -d '\n')"
    GIT_AUTH_ARGS=(-c "http.extraHeader=AUTHORIZATION: basic ${GIT_AUTH_HEADER}")
fi

if [ ! -d "${TRITON_DIR}" ]; then
    git "${GIT_AUTH_ARGS[@]}" clone https://github.com/triton-lang/triton.git "${TRITON_DIR}"
fi
git config --global --add safe.directory "${ROOT_DIR}"
git config --global --add safe.directory "${TRITON_DIR}"
if ! git -C "${TRITON_DIR}" cat-file -e "${TRITON_HASH}^{commit}" 2>/dev/null; then
    git "${GIT_AUTH_ARGS[@]}" -C "${TRITON_DIR}" fetch origin "${TRITON_HASH}"
fi
git -C "${TRITON_DIR}" reset --hard "${TRITON_HASH}"

# Upstream Triton downloads host-specific GPU toolchains at build time; those do
# not exist for riscv64.
# shellcheck source=scripts/_gpu-stub-env.sh
source "${ROOT_DIR}/scripts/_gpu-stub-env.sh" "${CACHE_DIR}/gpu-deps-stub"

export LLVM_SYSPATH
export LLVM_BINARY_DIR
export BUDDY_MLIR_BINARY_DIR

export PATH="${LLVM_BINARY_DIR}:${PATH}"

echo "Installing build dependencies into ${PYTHON}..."
"${PYTHON}" -m pip install --upgrade pip
"${PYTHON}" -m pip install "${PIP_INDEX_ARGS[@]}" numpy "cmake>=3.20,<4.0"
"${PYTHON}" -m pip install -U \
    "setuptools>=40.8.0" \
    "ninja>=1.11.1" \
    "nanobind==2.10.2" \
    "pytest"

# Builds Triton with the triton-shared plugin and installs the triton_riscv
# package on top of it.
PYTHON="${PYTHON}" "${ROOT_DIR}/scripts/install-dev.sh"
