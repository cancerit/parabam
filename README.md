# Parabam

Parabam is a tool for processing sequencing files in parralell. It uses pythons native multiprocessing framework to apply a user defined rule on an input file.

Full documentation can be found [here](http://parabam.readthedocs.org/).

## INSTALL

Installation is via `pip`.  Simply execute with the path to the packaged distribution:

```bash
VERSION=X.X.X
pip install https://github.com/cancerit/parabam/releases/download/$VERSION/parabam-${VERSION}.tar.gz
```

**Note:** `pip install parabam` will only work for versions pre `2.3.0`, as `2.3.0` and later are not published on PyPI.

### Package Dependancies

`pip` will install the relevant dependancies, listed here for convenience:

* [numpy](https://numpy.org/)
* [pysam](https://www.scipy.org/)

### Development Dependencies

#### Setup VirtualEnv

Parabam is a Cython package. In order to set it up for development use, you'll need to install Cython to compile `.pyx` files to `.c` files.

**Note:** Whenever you need to test changes you've made in `.pyx` files, you'll need to do `python setup.py sdist && python setup.py develop`, otherwise, those changes are not effective.

```bash
cd $PROJECTROOT
hash virtualenv || pip3 install virtualenv
python3 -m venv env
source env/bin/activate
pip3 install cython  # in order to be able to compile pyx files
python setup.py sdist  # compile pyx files into c files
python setup.py develop  # install parabam or update existing installation
```

#### Create a release

As for `2.3.0` and later, this package is not published on PyPI, to ease its installation, we should upload it's cython compiled package with each of our release. You'll need to run `python setup.py sdist` to build the compiled package, and then upload the `tar.gz` file in `dist` folder as an attachment with each release.
