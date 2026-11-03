#!/usr/bin/env bash
#
# Build and install the current checkout for development.
#
#   1. Install Triton from TRITON_DIR with TRITON_PLUGIN_DIRS set. That is what
#      makes Triton's build compile the triton-shared plugin and produce the
#      triton-shared-opt executable.
#   2. Undo the plugin vendoring Triton performs for TRITON_PLUGIN_DIRS: it
#      symlinks the plugin into triton.backends / triton.tools.extra and
#      registers a `triton_shared` entry point. We ship the backend as the
#      separate triton_riscv package instead, and backend discovery imports
#      every registered entry point, so leaving both in place would resolve
#      `triton_shared` twice and load whichever sorts last.
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

cd "${TRITON_DIR}"
echo "Installing Triton into ${PYTHON}..."
PIP_DISABLE_PIP_VERSION_CHECK=1 "${PYTHON}" -m pip install --no-build-isolation -e .

echo "Removing the vendored copy of the triton-shared plugin..."
"${PYTHON}" - "${_install_dev_repo_root}" <<'PY'
import configparser
import importlib.metadata
import os
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1]).resolve()

# Triton is installed by now, so this resolves to the installed package.
import triton
triton_dir = pathlib.Path(triton.__file__).resolve().parent

# Mirror the links Triton made for this plugin in add_link_to_backends().
# Matching on the target path instead would also catch the in-tree nvidia/amd
# backends, whose targets live next to Triton rather than under the plugin.
plugin_name = (repo_root / "backend" / "name.conf").read_text().strip()
links = [triton_dir / "backends" / plugin_name]
for extra, source in (("language", repo_root / "language"), ("tools", repo_root / "tools")):
    if source.is_dir():
        links += [triton_dir / extra / "extra" / entry for entry in os.listdir(source)]
for link in links:
    if link.is_symlink():
        link.unlink()

# The `triton_shared` entry point Triton registered for the plugin.
dist = importlib.metadata.distribution("triton")
try:
    entry_points = pathlib.Path(dist.locate_file(next(f for f in (dist.files or []) if str(f).endswith("entry_points.txt"))))
except StopIteration:
    entry_points = pathlib.Path(dist._path) / "entry_points.txt"  # type: ignore[attr-defined]

parser = configparser.ConfigParser()
parser.optionxform = str
parser.read(entry_points)
if parser.has_section("triton.backends") and parser.has_option("triton.backends", "triton_shared"):
    parser.remove_option("triton.backends", "triton_shared")
    with open(entry_points, "w") as handle:
        parser.write(handle)
PY

echo "Installing the triton_riscv package from ${_install_dev_repo_root}..."
PIP_DISABLE_PIP_VERSION_CHECK=1 "${PYTHON}" -m pip install --no-build-isolation -e "${_install_dev_repo_root}"

unset _install_dev_dir _install_dev_repo_root
