from setuptools import setup, Extension
from pathlib import Path
import os

def maybe_cythonize():
    """Build Cython extensions if available; fallback to .c files."""
    try:
        from Cython.Build import cythonize
        use_cython = True
        print("[parabam] Using Cython")
    except ImportError:
        use_cython = False

    extensions = []

    modules = [
        "parabam.core",
        "parabam.chaser",
        "parabam.merger",
        "parabam.command.core",
        "parabam.command.stat",
        "parabam.command.subset",
    ]

    for mod in modules:
        parts = mod.split(".")
        src_base = os.path.join(*parts)
        pyx_file = Path(f"{src_base}.pyx")
        c_file = Path(f"{src_base}.c")

        if use_cython and pyx_file.exists():
            # Rebuild only if .pyx is newer than .c
            if not c_file.exists() or pyx_file.stat().st_mtime > c_file.stat().st_mtime:
                print(f"[parabam] Generating {c_file} from {pyx_file}")
                from Cython.Build import cythonize
                cythonize([str(pyx_file)], compiler_directives={"language_level": "3"})
            source_file = str(pyx_file)
        else:
            if not c_file.exists():
                raise FileNotFoundError(f"Cannot find {c_file}. Install Cython to generate it from {pyx_file}")
            source_file = str(c_file)

        extensions.append(Extension(mod, [source_file]))

    if use_cython:
        from Cython.Build import cythonize
        extensions = cythonize(extensions, compiler_directives={"language_level": "3"})

    return extensions


setup(ext_modules=maybe_cythonize())
