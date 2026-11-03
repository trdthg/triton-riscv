"""Minimal setup.py that only adjusts wheel tagging.

All metadata lives in ``pyproject.toml``. The package ships a native
``triton-shared-opt`` executable (and C++ launcher headers), so the wheel must
be platform-specific rather than ``py3-none-any``.
"""

from setuptools import setup
from setuptools.dist import Distribution
from wheel.bdist_wheel import bdist_wheel as _bdist_wheel


class BinaryDistribution(Distribution):
    def has_ext_modules(self):
        return True


class bdist_wheel(_bdist_wheel):
    def finalize_options(self):
        super().finalize_options()
        self.root_is_pure = False

    def get_tag(self):
        # The package is pure Python plus a standalone executable, so the wheel
        # is platform-specific but not tied to a CPython ABI version.
        _, _, plat = super().get_tag()
        return "py3", "none", plat


setup(distclass=BinaryDistribution, cmdclass={"bdist_wheel": bdist_wheel})
