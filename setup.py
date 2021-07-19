import sys

from setuptools import Extension, setup
from setuptools.command.sdist import sdist as _sdist

class sdist(_sdist):
  def run(self):
    # Make sure the compiled Cython files in the distribution are up-to-date
    from Cython.Build import cythonize
    cythonize(['parabam/chaser.pyx','parabam/core.pyx','parabam/merger.pyx','parabam/command/core.pyx',
      'parabam/command/stat.pyx','parabam/command/subset.pyx'],
      compiler_directives={'language_level' : '3'})
    _sdist.run(self)

setup(name='parabam',
  version='3.0.1',
  url='https://github.com/cancerit/parabam',
  description='Parallel BAM File Analysis',
  author="JHR Farmery",
  license='GPL',
  author_email = 'cgphelp@sanger.ac.uk',
  packages = ['parabam','parabam.command'],
  package_dir = {'parabam':'parabam','parabam.command':'parabam/command'},
  install_requires = ['numpy','argparse','pysam >= 0.10.0'],
  scripts = ['parabam/bin/parabam'],
  cmdclass = {'sdist': sdist},
  ext_modules=[
    Extension("parabam.core", [ "parabam/core.c" ]),
    Extension("parabam.chaser", ["parabam/chaser.c"]),
    Extension("parabam.merger", ["parabam/merger.c"]),
    Extension("parabam.command.subset", ["parabam/command/subset.c"]),
    Extension("parabam.command.stat", ["parabam/command/stat.c"]),
    Extension("parabam.command.core", ["parabam/command/core.c"])
  ]
)
