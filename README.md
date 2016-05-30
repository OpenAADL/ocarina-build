This repository proposes a script, `build_ocarina.sh` to compile and
test Ocarina. It relies on bash constructs to coordinate various
activities to

- fetch Ocarina source, along with its runtime
- compile Ocarina, and install it in a local directory
- run Ocarina testsuites,
- and eventually collect coverage metrics

```
Usage: ./build_ocarina-suite.sh [switches]
 -u : update source directory
 -s : reset source directory (needs -u)
 -h : print usage
 -d : debug traces

 -c : build Ocarina with coverage on
 -g : build Ocarina with debug on
 -t : run tests
```

* The following install a freh copy of Ocarina:

```
./build_ocarina-suite.sh -s -u
```

* To compile and install Ocarina:

```
./build_ocarina-suite.sh -b
```
