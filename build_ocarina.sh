###############################################################################
#! /bin/bash

# This script does a checkout of the Ocarina sources and then
# builds Ocarina, runs regression tests, install and package it.

# Note: it may assumes the shell is actually bash

######################
# script configuration

root_script_dir=`dirname $0`; cd ${root_script_dir}; root_script_dir=`pwd`
the_date=`date +"%Y%m%d"`
tmp_dir="$HOME/tmp"; mkdir -p $tmp_dir
is_error=$tmp_dir/build_ocarina_ERROR; rm -f $is_error

LANG=C        # ensure there is no pollution from language-specific locales
GNU_MAKE=make # default make utility

######################
# Target specific flags for configure go there
case "$(uname -s)" in

    Darwin)
	build_platform=darwin-`uname -m`
	src_suffix=".tar.gz"
	bin_suffix=".tgz"
	;;

    Linux)
	build_platform=linux-`uname -m`
	src_suffix=".tar.gz"
	bin_suffix=".tgz"
	;;

    CYGWIN*)
	# For Cygwin, we assume we "cross compile"
	target_specific="--target=x86_64-w64-mingw32"
	build_platform=windows-x86
	src_suffix=".tar.gz"
	bin_suffix=".zip"
	;;

    MINGW32*|MSYS*)
	echo "Unsupported build configuration"
	exit -1
	;;
    esac

##################################
# Ocarina build-time configuration

include_runtimes="polyorb-hi-ada polyorb-hi-c aadlib" # Ocarina runtimes

# Note: check Ocarina configure script for details

ocarina_doc=""                          # --enable-doc to build documentation
ocarina_debug=""                        # --enable-debug to enable debug
ocarina_coverage=""                     # --enable-gcov to enable coverage
ocarina_python=""                       # --enable-python to build Python bindings

# Default installation prefix, can be overidden by the --prefix parameter
prefix_default=${root_script_dir}/ocarina_repos_install
ocarina_dist_install=${root_script_dir}/ocarina_dist_install

#############################
# build_ocarina configuration

debug_default="no"                      # "yes" to print debugging traces
update_ocarina_default="no"             # "yes" to update the source directory
build_ocarina_from_scratch_default="no" # "yes" to reload source directory
build_ocarina_default="no"              # "yes" to build Ocarina
package_ocarina_default="no"            # "yes" to package Ocarina
test_ocarina_default="no"               # "yes" to run make check

###############################################################################
# This function tries to do an action, if the action fails; it complains
# by sending a report. It uses the following variables

# 1 - ${tmp_dir}: which designates the temp directory.
# 2 - ${report_mail}: which designates the e-mail adress to contact in
#     case of failure.
# 3 - ${report_sender}: which designates the sender of the report mail.
# 4 - ${is_error} that points to a previous detected error

try() {
    # If previous errors are detected do not cause an error cascade.
    if [ -f ${is_error} ]; then
        exit 0
    fi

    # Execute the command and get the result in a temporary file

    try_cmd_and_args=$1
    try_msg="$2"
    try_report="${tmp_dir}/report.$$"

    ${try_cmd_and_args} >> ${try_report} 2>&1

    return_code=$?

    # If the execution succeded, exit normally, else, returns the log

    if [ ${return_code} -eq 0 ] ; then
        echo "[`date +"%Y-%m-%d-%H:%M"`] ${try_msg}: PASSED" | tee -a ${final_report_body}
        rm -f ${try_report}
        return 0
    fi

    echo "[`date +"%Y-%m-%d-%H:%M"`] ${try_msg}: FAILED" | tee -a ${final_report_body}

    # Set error

    touch ${is_error}

    # Display the report message

    cat ${try_report}
    return 1
}

###############################################################################
# This function archives the given directory depending on the given
# archive format. Arguments:
# $1 - Archive name
# $2 - Archive kind (.tar.gz, .tgz, .tar.bz2, tbz2, .zip)
# $3 - Dircetory

do_archive() {
    archive_name=$1
    format=$2
    directory=$3

    case "${format}" in
        .tar.gz | .tgz )
	    tar czf ${archive_name} ${directory}
	    ;;

        .tar.bz2 | .tbz2 )
	    tar cjf ${archive_name} ${directory}
	    ;;

        .zip )
	    zip -q -r ${archive_name} ${directory}
	    ;;

        * )
	    echo "Unknown archive format: ${format}"
	    exit 1
	    ;;
    esac

    return 0
}

###############################################################################
# Fetch Ocarina sources

do_check_out() {
    if test x"${build_ocarina_from_scratch}" = x"yes"; then
    # Go to the temporary directory

        cd ${root_script_dir}

        # Fetch Ocarina sources

        rm -rf ocarina
        try "git clone https://github.com/yoogx/ocarina.git" \
	    "Checkout the Ocarina sources"

        cd ocarina

        # Check out the requested runtimes

        if test ! -z "${include_runtimes}"; then
	    try "./support/get_runtimes.sh ${include_runtimes}" \
	        "Fetching runtimes '${include_runtimes}'"
        fi;

    else
        cd ${root_script_dir}/ocarina
        try "git pull" "Updating Ocarina repository"

        # Update the requested runtimes

        if test ! -z "${include_runtimes}"; then
	    cd resources/runtime
	    for r in ${include_runtimes}; do
	        cd ${r}
	        try "git pull" "Updating runtime '${r}'"
	        cd ..
	    done
	    cd ../..
        fi
    fi
}

###############################################################################
# Test the Ocarina build from the repository

do_build_ocarina() {
    cd ${root_script_dir}/ocarina

    # Bootstrap the build
    try "./support/reconfig" "Reconfiguring (Ocarina)"

    # Configuring
    try "./configure ${target_specific} ${ocarina_debug} ${ocarina_coverage} ${ocarina_python} --prefix=${prefix}" \
        "First configure (Ocarina)"

    # Building
    try "${GNU_MAKE}" "Doing '${GNU_MAKE}' (Ocarina)"

    # Installing
    if test -d ${prefix}; then
        try "rm -rf ${prefix}" "Removing old install dir"
    fi

    try "${GNU_MAKE} install" "Doing '${GNU_MAKE} install' (Ocarina)"
}

###############################################################################
# Testing repository version of Ocarina

do_test_ocarina() {
    cd ${root_script_dir}/ocarina

    try "${GNU_MAKE} check" "Testing (Ocarina)"

    if test x"${ocarina_coverage}" != x""; then
        try "./autotest.sh -l" "Generating coverage report"
    fi
}

###############################################################################
# Packaging Ocarina

do_packaging() {
    cd ${root_script_dir}/ocarina

    # Bootstrap the build
    try "./support/reconfig" "Reconfiguring (Ocarina)"

    # Configuring
    try "./configure ${target_specific} ${ocarina_debug} ${ocarina_coverage} ${ocarina_python} --prefix=${prefix}" \
        "First configure (Ocarina)"

    # Clean up old archives and build tree
    old_archive="`ls ocarina-*${src_suffix} 2> /dev/null`"
    rm -f ${old_archive}

    try "${GNU_MAKE} distclean" "${GNU_MAKE} distclean (Ocarina)"

    # Re configuring (since we've done 'make distclean')

    try "./configure ${target_specific} ${ocarina_debug} ${ocarina_coverage} ${ocarina_python} --prefix=${prefix}" \
        "Second configure (Ocarina)"

    # Packaging and testing the package

    try "${GNU_MAKE} dist DISTCHECK_CONFIGURE_FLAGS='--disable-debug'" \
        "${GNU_MAKE} dist (Ocarina)"

    archive="`ls ocarina-*${src_suffix}`"
    echo "  => Archive ${archive} built in directory `pwd`"

    # Source snapshot

    base_archive_name="`basename ${archive} ${src_suffix}`"
    src_archive_name="${base_archive_name}-suite-src-${the_date}${src_suffix}"
    mv ${archive} ${src_archive_name}
    echo "  => Source archive ready: ${src_archive_name}"
}

###############################################################################
# Build the binary package for the Ocarina suite

do_build_from_tarball() {
    cd ${root_script_dir}/ocarina

    archive_dir=`basename ${src_archive_name} ${src_suffix}`
    rm -r  ${archive_dir}
    mkdir -p ${archive_dir}

    # Extract the archive
    try "tar xzvf ${src_archive_name} -C ${archive_dir} --strip-components=1" "extracting archive ${src_archive_name}"

    cd ${archive_dir}

    # Configuring
    try "./configure ${target_specific} --disable-debug --prefix=${ocarina_dist_install}" \
        "DIST: configure (Ocarina)"

    # Building
    try "${GNU_MAKE}" "DIST: ${GNU_MAKE} (Ocarina)"

    # Installing
    if test -d ${ocarina_dist_install}; then
        try "rm -rf ${ocarina_dist_install}" "DIST: Removing old install dir"
    fi

    try "${GNU_MAKE} install-strip" "DIST: ${GNU_MAKE} install-strip (Ocarina)"

    # Clean up
    try "${GNU_MAKE} distclean" "DIST: ${GNU_MAKE} distclean (Ocarina)"
    cd ..

    # Binary snapshots (Runtime and Examples)
    bin_dir="${base_archive_name}-suite-${build_platform}-${the_date}"
    bin_archive="${bin_dir}${bin_suffix}"
    rm -rf ${bin_dir}
    mkdir ${bin_dir}
    cp -rf ${ocarina_dist_install}/* "${bin_dir}/"

    # Remove any previous archive
    try "rm -rf ocarina-*${bin_suffix}" "DIST: remove old archives"

    # Create the archive
    do_archive ${bin_archive} ${bin_suffix} ${bin_dir}

    rm -rf ${bin_dir}

    archive="`ls ocarina-*${bin_suffix}`"
    echo "  => Archive ${archive} built in directory `pwd`"
}

###############################################################################
usage() {
    echo "Usage: $0 [switches]"
    echo ""
    echo "General commands"
    echo " -h | --help        : print usage"
    echo " -u | --update      : update Ocarina source directory"
    echo " -b | --build       : configure, build and install Ocarina"
    echo " -t | --run-test    : run Ocarina testsuite, plus runtimes and AADLib"
    echo " -p | --package     : package ocarina distribution as tarball"
    echo ""
    echo "Update-time options, options to be passed along with -u"
    echo " -s | --reset       : reset source directory prior to update"
    echo ""
    echo "Build-time options, options to be passed along with -b"
    echo " --prefix=<dir>     : install ocarina in <dir>"
    echo " --enable-gcov      : enable coverage during ocarina build"
    echo " --enable-debug     : enable debug during ocarina build"
    echo " --enable-python    : enable Python bindings"
    echo ""
    echo "Scenarios, specific combination of parameters"
    echo " --scenarion=<name> : run a specific scenario"
    echo ""
    echo " Valid names are fresh-install nightly-build taste "
    echo " See source code for details on actual parameters"
}

###############################################################################
# Main function starts here

# 1) parse command line parameters

while test $# -gt 0; do
  case "$1" in
  -*=*) optarg=`echo "$1" | sed 's/[-_a-zA-Z0-9]*=//'` ;;
  *) optarg= ;;
  esac

  case $1 in
      --build | -b) build_ocarina="yes"  ;;
      -d) debug="yes" ;;
      --enable-debug) ocarina_debug="--enable-debug" ;;
      --enable-gcov) ocarina_coverage="--enable-gcov" ;;
      --enable-python) ocarina_python="--enable-python --enable-shared";;
      --help | -h) usage 1>&2 && exit 1 ;;
      --package | -p) package_ocarina="yes" ;;
      --reset | -s) build_ocarina_from_scratch="yes" ;;
      --runt-test | -t) test_ocarina="yes" ;;
      --update | -u) update_ocarina="yes" ;;
      --prefix=*) prefix=${optarg};;
      --scenario=*) scenario=${optarg};;
      *) echo "$1: invalid flag" && echo "" && usage 1>&2 && exit 1 ;;
  esac
  shift
done

case $scenario in
    fresh-install)
        # In this scenario, we do a fresh install of Ocarina, the user
        # may override the installation prefix using --prefix
        build_ocarina_from_scratch="yes"
        update_ocarina="yes"
        build_ocarina="yes"
        ;;

    nightly-build)
        update_ocarina="yes"
        build_ocarina="yes"
        test_ocarina="yes"
        package_ocarina="yes"
        ;;

    taste)
        # In this scenario, we update and build Ocarina with Python
        # and debug enabled. Use TASTE specific installation prefix
        update_ocarina="yes"
        build_ocarina="yes"
        ocarina_debug="--enable-debug"
        ocarina_python="--enable-python --enable-shared"
        prefix="$HOME/tool-inst"
        ;;

    *) echo "Invalid scenario name $scenario" && exit 1;;
esac

# 2) consolidate configuration parameters

: ${build_ocarina_from_scratch=$build_ocarina_from_scratch_default}
: ${update_ocarina=$update_ocarina_default}
: ${debug=$debug_default}
: ${build_ocarina=$build_ocarina_default}
: ${package_ocarina=$package_ocarina_default}
: ${test_ocarina=$test_ocarina_default}
: ${prefix=$prefix_default}

if test x"${debug}" = x"yes"; then
    echo build_ocarina_from_scratch : $build_ocarina_from_scratch
    echo update_ocarina : $update_ocarina
    echo debug : $debug
    echo build_ocarina : $build_ocarina
    echo package_ocarina : $package_ocarina
    echo test_ocarina : $test_ocarina
    echo prefix : $prefix

    echo build ocarina with debug:    $ocarina_debug
    echo build ocarina with coverage: $ocarina_coverage
    echo build ocarina with Python: $ocarina_python
fi

# 3) general execution scheme

if test x"${update_ocarina}" = x"yes"; then
    do_check_out
fi

if test x"${build_ocarina}" = x"yes"; then
    do_build_ocarina
fi

if test x"${test_ocarina}" = x"yes"; then
    do_test_ocarina
fi

if test x"${package_ocarina}" = x"yes"; then
    do_packaging
    do_build_from_tarball
fi

exit 0