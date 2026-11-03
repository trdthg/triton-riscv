# triton-riscv

Triton compiler for RISC-V platforms.

This repository is forked from [triton-shared](https://github.com/microsoft/triton-shared) and provides a Triton compiler backend for RISC-V. The upstream triton-shared repo is no longer maintained, so this project is developed independently under the name triton-riscv.

Triton acts as a frontend (Python AST → TTIR); triton-riscv handles the rest of the pipeline (TTIR → Linalg → LLVM IR → native object). No NVIDIA or AMD toolchain is required.

**Compilation pipeline:**

```
Python @triton.jit
  └─► TTIR          (triton: ast_to_ttir + make_ttir passes)
        └─► Linalg MLIR   (triton-shared-opt --triton-to-linalg-experimental)
              └─► LLVM MLIR  (Buddy Compiler lowering passes)
                    └─► LLVM IR  (mlir-translate --mlir-to-llvmir)
                          └─► native .o  (llc -filetype=obj)
```

## Clone

```sh
git clone https://github.com/RuyiAI-Stack/triton-riscv.git triton-riscv
TRITON_RISCV_DIR="$(pwd)/triton-riscv"
```

`scripts/build.sh` clones the Triton revision pinned in `triton-hash.txt` and
downloads the LLVM and buddy tools published under `buddy-hash.txt`, so neither
needs a manual checkout.

> Note: Ensure PyTorch is available in your virtual environment. For RISC-V, since PyTorch does not officially support RISC-V yet, you can build from source or use third-party builds: https://community-ci.openruyi.cn/pypi/riscv64/dev/+simple/torch . To use the third-party builds, python 3.12 or 3.13 are required.

Triton is used **unpatched**. Building the stock Triton checkout on RISC-V
requires the LLVM it links against to provide the NVPTX and AMDGPU codegen
libraries plus `lld` (upstream Triton hard-codes them), and it requires skipping
the host-specific GPU toolchains Triton downloads at build time (nvcc, AMD
codegen, proton), which do not exist for `riscv64`:

- The buddy-mlir LLVM release published under `buddy-hash.txt` is built with
  those extra targets; `scripts/build.sh` downloads it into `.cache/llvm` (set
  `TRITON_LLVM_DIR` to use an existing LLVM instead).
- `scripts/gpu-stub-env.sh` points every GPU download location at an
  empty stub directory and disables the components that need CUDA/ROCm headers.

## Prerequisites

### Create a virtual environment

Use either a Python venv or an existing conda environment:

```sh
python -m venv "${TRITON_RISCV_DIR}/.venv" --prompt triton-riscv
source "${TRITON_RISCV_DIR}/.venv/bin/activate"
```

Or with conda:

```sh
conda activate ruyiai
```

When a conda environment is active, `scripts/env.sh` automatically uses `CONDA_PREFIX` as `TRITON_VENV`.

### Install dependencies

1. Install the [LLVM/MLIR build dependencies](https://github.com/buddy-compiler/buddy-mlir?tab=readme-ov-file#llvmmlir-dependencies) of the Ruyi Buddy Compiler. The LLVM and buddy tools themselves are published as releases and downloaded by `scripts/build.sh`; a local `buddy-mlir` build is only needed for the RVV cross toolchain and QEMU (see [docs/06-RISCV-QEMU.md](docs/06-RISCV-QEMU.md)).

2. Install triton-riscv Python dependencies in the active environment:

   ```sh
   pip install cmake ninja pytest-xdist nanobind==2.10.2 setuptools
   ```

   `cmake`, `ninja`, and `nanobind` are needed because the rebuild script uses `pip install --no-build-isolation` to reuse the active environment instead of creating an isolated build environment.

## Environment helper

[`scripts/env.sh`](scripts/env.sh) centralizes the local environment variables needed by `triton-riscv`.

By default it assumes:

- `TRITON_RISCV_DIR=/path/to/triton-riscv`
- `TRITON_DIR=$TRITON_RISCV_DIR/triton` (where `scripts/build.sh` clones Triton)
- `TRITON_VENV=$CONDA_PREFIX` when a conda environment is active, otherwise `$TRITON_RISCV_DIR/.venv`
- `BUDDY_DIR=$TRITON_RISCV_DIR/../buddy-mlir`
- `BUILD_DIR` is auto-detected from `$TRITON_DIR/build/cmake.linux-*-cpython-*`
- runtime cache, dump, and JSON dependency directories default to `~/.triton`

It exports:

- `TRITON_RISCV_DIR`, `TRITON_DIR`, `TRITON_VENV`, `BUDDY_DIR`
- `LLVM_SYSPATH`, `LLVM_BINARY_DIR`, `BUDDY_MLIR_BINARY_DIR`, `JSON_SYSPATH`
- `BUILD_DIR`, `TRITON_SHARED_OPT_PATH`
- `TRITON_HOME`, `TRITON_CACHE_DIR`, `TRITON_DUMP_DIR`, `TRITON_OVERRIDE_DIR`
- `TRITON_PLUGIN_DIRS`, used by Triton's build to compile the plugin alongside it

It also prepends the venv, LLVM and buddy `bin` directories to `PATH`, sets
`PYTHONSAFEPATH=1` so the in-tree `triton/` checkout cannot shadow the installed
package, and disables the host-specific GPU toolchain downloads Triton would
otherwise attempt.

If your local layout differs, override variables before sourcing:

```sh
export TRITON_DIR=/path/to/triton
export TRITON_VENV=/path/to/triton-venv   # or rely on active conda env
export BUDDY_DIR=/path/to/buddy-mlir
source /path/to/triton-riscv/scripts/env.sh
```

This helper removes most of the repetitive local environment setup from the README, but it does not replace the external prerequisites themselves: a virtual environment, a Triton checkout, and the LLVM/buddy toolchains (`scripts/build.sh` fetches all three).

## Build and rebuild

On a clean checkout, `scripts/build.sh` clones the pinned Triton revision,
downloads the LLVM and buddy tools it needs, builds the triton-shared plugin
and installs Triton into `.venv`:

```sh
cd /path/to/triton-riscv
scripts/build.sh
```

After changing the backend, the lowering pipeline or the C++ sources, rebuild
Triton and the plugin without re-downloading anything:

```sh
conda activate ruyiai   # or: source /path/to/triton-riscv/.venv/bin/activate
cd /path/to/triton-riscv
source scripts/env.sh
scripts/rebuild.sh
```

[`scripts/rebuild.sh`](scripts/rebuild.sh) does the following:

- reuses the environment from `env.sh`
- removes a stale Triton build directory when it was created under an old path or with a different Python version
- runs [`scripts/install-dev.sh`](scripts/install-dev.sh), which installs Triton from `$TRITON_DIR` with the triton-shared plugin enabled, removes the copy of the plugin Triton symlinks into its own package, and installs this repository's `triton_riscv` package in its place
- verifies the rebuilt install with a Python import and `triton-shared-opt --version`

Use the same command sequence after changing the backend, lowering pipeline, or C++ sources.
If you change the buddy-opt pass pipeline or cached compilation behavior, clear Triton's cache after sourcing the environment and before rerunning tests:

```sh
rm -rf "$TRITON_CACHE_DIR"
```

Build artifacts are placed under `triton/build/{current_cmake_version}/third_party/triton_shared`.

## Verify the build

```sh
conda activate ruyiai   # or: source /path/to/triton-riscv/.venv/bin/activate
cd /path/to/triton-riscv
source scripts/env.sh
python -c "import triton; import triton_riscv.compiler as c; print(triton.__version__); print(c.__file__)"
"$TRITON_SHARED_OPT_PATH" --version
```

## Run the example test suite

```sh
pytest python/examples/ \
    --ignore=python/examples/test_core.py \
    --ignore=python/examples/test_annotations.py \
    --ignore=python/examples/flaggems \
    -v
```

To run a single test:

```sh
pytest python/examples/test_vec_add.py -v
```

## Generate and run RVV ELF files with QEMU

The backend can compile a Python Triton kernel directly to a self-contained RISC-V Linux ELF, automatically generate its runner, execute it with QEMU, and verify outputs. No user-written C runner is required.

```sh
source scripts/env.sh
python python/examples/rvv_vec_add_elf.py
```

See [docs/06-RISCV-QEMU.md](docs/06-RISCV-QEMU.md) for toolchain setup, the end-to-end API, output verification, and troubleshooting.

See [docs/07-Optimization.md](docs/07-Optimization.md) for the current code-generation bottlenecks, correctness gaps, and optimization priorities identified from the RVV and bufferization analysis.

## FAQ

Building on RISC-V often runs into dependency issues; we're happy to help if you run into trouble.

### Fortran library mismatch when building PyTorch

Preload the correct Fortran library by adding the following to your virtualenv’s `activate` script (e.g. `~/triton/.venv/bin/activate`):

```sh
export LD_PRELOAD=/usr/lib64/libgfortran.so.5:$LD_PRELOAD
```
