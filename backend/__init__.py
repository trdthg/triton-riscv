"""Triton backend for RISC-V.

This package is installed both ways:

* as the ``triton_riscv`` distribution, discovered by Triton through the
  ``triton.backends`` entry point, and
* as the in-tree ``triton.backends.triton_shared`` plugin when the repository
  is used through ``TRITON_PLUGIN_DIRS``.

The modules are identical in both layouts; only the package prefix differs.

Importing ``triton`` here matters: Triton discovers external backends eagerly
while ``triton.backends`` is being initialized. Importing a submodule such as
``triton_riscv.compiler`` first would therefore re-enter the discovery loop
with a half-initialized module. Importing the host package first makes direct
submodule imports safe.
"""

import sys

import triton as _triton  # noqa: F401  (force host discovery before submodules)

# ``triton.backends.triton_shared`` was the import path when the backend was
# only available as an in-tree plugin. Keep it working for code written against
# it; in that layout the module is already registered under this name and the
# call is a no-op.
sys.modules.setdefault("triton.backends.triton_shared", sys.modules[__name__])
