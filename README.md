This repository proposes a script, `build_ocarina.sh`, to get source
code, compile and test Ocarina.

It relies on bash constructs to coordinate various activities to:

- fetch Ocarina source, with its runtimes PolyORB-HI/Ada and
  PolyORB-HI/C
- compile Ocarina, and install it in a local directory
- run Ocarina testsuites, and eventually collect coverage metrics

```
Usage: ./build_ocarina.sh [switches]
 -u : update source directory
 -s : reset source directory (needs -u)
 -h : print usage
 -d : debug traces

 -b : build Ocarina
 -c : build Ocarina with coverage on (needs -b or -t)
 -g : build Ocarina with debug on (needs -b)
 -p : package Ocarina
 -t : run tests
```

* The following command gets a fresh copy of Ocarina source code:

```
./build_ocarina.sh -s -u
```

* The following command compiles and installs Ocarina:

```
./build_ocarina.sh -b
```
