This repository proposes a script, `build_ocarina.sh`, to get source
code, compile and test Ocarina.

It relies on shell constructs to coordinate various activities to:

- fetch Ocarina source, with its runtimes PolyORB-HI/Ada and
  PolyORB-HI/C, and the AADLib library
- compile Ocarina, and install it in a local directory
- run Ocarina testsuites, and eventually collect coverage metrics

```
Usage: ./build_ocarina.sh [switches]

General commands
 -h | --help        : print usage
 -u | --update      : update Ocarina source directory
 -b | --build       : configure, build and install Ocarina
 -t | --run-test    : run Ocarina testsuite, plus runtimes and AADLib
 -p | --package     : package ocarina distribution as tarball

Update-time options, options to be passed along with -u
 -s | --reset       : reset source directory prior to update

Build-time options, options to be passed along with -b
 --prefix=<dir>     : install ocarina in <dir>
 --enable-gcov      : enable coverage during ocarina build
 --enable-debug     : enable debug during ocarina build
 --enable-python    : enable Python bindings

Scenarios, specific combination of parameters
 --scenarion=<name> : run a specific scenario

 Valid names are fresh-install nightly-build taste (see source code for details)
 Note: this may overwrite other configuration parameters
```

* The following command gets a fresh copy of Ocarina source code:

```
./build_ocarina.sh -s -u
```

* The following command compiles and installs Ocarina:

```
./build_ocarina.sh -b
```
