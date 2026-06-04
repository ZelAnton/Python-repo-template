"""__ProjectName__ — the sample public API shipped with this template.

Replace it with your real package: rename the ``src/__PackageName__`` directory
(the init script already stamped it from your project name), update this module,
and implement your public surface. Re-export the public API here so callers can
``from __PackageName__ import ...`` without reaching into submodules.
"""

from __PackageName__.greeter import greet

__all__ = ["greet"]
