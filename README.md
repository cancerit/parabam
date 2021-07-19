# Parabam

Parabam is a tool for processing sequencing files in parallel. It uses pythons native multiprocessing framework to apply a user defined rule on an input file.

Full documentation can be found [here](http://parabam.readthedocs.org/).

## INSTALL

Installation is via `pip`.

```bash
# current release
pip install parabam
# specific version
pip install parabam==$VERSION
```

**Note:** `pip install parabam` does not work for `2.3.1`/`3.0.0` use the following:

```bash
export VERSION=X.X.X
# directly from GitHub (incase pypi release hasn't been performed)
pip install https://github.com/cancerit/parabam/releases/download/$VERSION/parabam-${VERSION}.tar.gz
```

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
