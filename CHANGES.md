# CHAGNGES

## NEXT

* Migrated fully to python3 syntax in cython
* Multiprocessing fork is slowly being dropped:
  * [see here](https://docs.python.org/3/library/multiprocessing.html#multiprocessing.get_context)
  * `telomerecat` no longer depends on parabam for BAM processing in bam2telbam
* Minimal support for parabam going forward

## 2.3.1

* removed some confusing output messages, which are notes for the developer.

## 2.3.0

* Supports python3
* Now compatible with latest version of pysam in Python3
* It can use a temp folder properly. Command line option `--temp_dir` is added to allow user to specify the folder path.
* It can output telbam files to a specified directory.

2017/9/20 - Parabam v2.2.5 - jhrf

- Added ability to return a dict from a subset rule in a similar manner to stat rule

