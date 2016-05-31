###############################################################################
#! /bin/bash

# This script does a checkout of the Ocarina sources and then
# builds Ocarina, runs regression tests, install and package it.

# Note: it may assumes the shell is actually bash

root_script_dir=`dirname $0`; cd ${root_script_dir}; root_script_dir=`pwd`
the_date=`date +"%Y%m%d"`
tmp_dir="$HOME/tmp"; mkdir -p $tmp_dir
is_error=$tmp_dir/build_ocarina_ERROR; rm -f $is_error

######################
# script configuration

LANG=C        # ensure there is no pollution from language-specific locales
GNU_MAKE=make # default make utility

###############################################################################

do_packaging="yes" # "yes" to do the packaging, any other value otherwise
upload_src="no"  # "yes" to upload, any other value otherwise
upload_bin="no"  # "yes" to upload, any other value otherwise
upload_xpl="no"  # "yes" to upload, any other value otherwise
src_suffix=".tar.gz"
bin_suffix=".tgz"

##################################
# Ocarina build-time configuration

include_runtimes="polyorb-hi-ada polyorb-hi-c aadlib" # Ocarina runtimes

# Note: check Ocarina configure script for details

ocarina_doc=""                          # --enable-doc to build documentation
ocarina_debug=""                        # --enable-debug to enable debug
ocarina_coverage=""                     # --enable-gcov to enable coverage

# We install Ocarina in a sub-directory of the current directory
ocarina_repos_install=${root_script_dir}/ocarina_repos_install
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
	    tar czvf ${archive_name} ${directory}
	    ;;

        .tar.bz2 | .tbz2 )
	    tar cjvf ${archive_name} ${directory}
	    ;;

        .zip )
	    zip -r ${archive_name} ${directory}
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
    try "./configure ${ocarina_debug} ${ocarina_coverage} --prefix=${ocarina_repos_install}" \
        "First configure (Ocarina)"

    # Building
    try "${GNU_MAKE}" "Doing '${GNU_MAKE}' (Ocarina)"

    # Installing
    if test -d ${ocarina_repos_install}; then
        try "rm -rf ${ocarina_repos_install}" "Removing old install dir"
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
    try "./configure ${ocarina_debug} ${ocarina_coverage} --prefix=${ocarina_repos_install}" \
        "First configure (Ocarina)"

    # Clean up old archives and build tree
    old_archive="`ls ocarina-*${src_suffix} 2> /dev/null`"
    rm -f ${old_archive}

    try "${GNU_MAKE} distclean" "${GNU_MAKE} distclean (Ocarina)"

    # Re configuring (since we've done 'make distclean')

    try "./configure ${ocarina_debug} ${ocarina_coverage} --prefix=${ocarina_repos_install}" \
        "Second configure (Ocarina)"

    # Packaging and testing the package

    try "${GNU_MAKE} distcheck DISTCHECK_CONFIGURE_FLAGS='--disable-debug'" \
        "${GNU_MAKE} distcheck (Ocarina)"

    archive="`ls ocarina-*${src_suffix}`"
    echo "  => Archive ${archive} built in directory `pwd`"

    # Source snapshot

    new_archive="`basename ${archive} ${src_suffix}`-suite-src-${the_date}${src_suffix}"
    mv ${archive} ${new_archive}
    echo "  => Source archive ready: ${new_archive}"
}

###############################################################################
# Build the binary package for the Ocarina suite

do_build_from_tarball() {
    archive="`ls ocarina-*${src_suffix}`"

    # Extract the archive
    try "tar xzvf ${archive}" "extracting archive (Ocarina)"

    archive_dir=`basename ${archive} ${src_suffix}`
    cd ${archive_dir}

    # Configuring
    try "./configure --disable-debug --prefix=${ocarina_dist_install}" \
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

    # Packaging is successful, create a snapshot and upload it

    if test x"${upload_src}" = x"yes"; then

    # Remove any previous source archive from the remote directory

        ssh ${remote_user}@${remote_host} rm -f "${local_ocarina_snapshot_dir}/${archive_dir}-suite-src*" >> ${final_report_body} 2>&1

        try "${upload} ${new_archive} ocarina" "DIST: uploading the nightly source snapshot"
    fi

    # Binary snapshots (Runtime and Examples)
    bin_dir="${archive_dir}-suite-${build_platform}-${the_date}"
    bin_archive="${bin_dir}${bin_suffix}"
    rm -rf ${bin_dir}
    mkdir ${bin_dir}
    cp -rf ${ocarina_dist_install}/* "${bin_dir}/"

    # Remove any previous archive
    rm -rf ocarina-*${bin_suffix} >> ${final_report_body} 2>&1

    # Create the archive
    do_archive ${bin_archive} ${bin_suffix} ${bin_dir}

    rm -rf ${bin_dir} >> ${final_report_body} 2>&1

    archive="`ls ocarina-*${bin_suffix}`"
    echo "  => Archive ${archive} built in directory `pwd`" >> ${final_report_body} 2>&1
}

###############################################################################
do_upload() {
    if test x"${upload_bin}" = x"yes"; then

    # Remove any previous binary archive of the same platform from the
    # remote directory.

        ssh ${remote_user}@${remote_host} rm -f "${local_ocarina_snapshot_dir}/${archive_dir}-suite-${build_platform}*" >> ${final_report_body} 2>&1

        try "${upload} ${bin_archive} ocarina" "DIST: uploading the nightly binary snapshot"
    fi
}

###############################################################################
usage() {
    echo "Usage: $0 [switches]"
    echo " -u : update source directory"
    echo " -s : reset source directory (needs -u)"
    echo " -h : print usage"
    echo " -d : debug traces"
    echo ""
    echo " -b : build Ocarina"
    echo " -c : build Ocarina with coverage on (needs -b or -t)"
    echo " -g : build Ocarina with debug on (needs -b)"
    echo " -p : package Ocarina"
    echo " -t : run tests"
}

###############################################################################
# Main function starts here

# 1) parse command line parameters

while getopts "shudgtbcp" OPTION; do
    case "$OPTION" in
        b) build_ocarina="yes" ;;
        c) ocarina_coverage="--enable-gcov" ;;
        d) debug="yes" ;;
        g) ocarina_debug="--enable-debug" ;;
        h) usage ; exit 0 ;;
        p) package_ocarina="yes" ;;
        s) build_ocarina_from_scratch="yes" ;;
        t) test_ocarina="yes" ;;
        u) update_ocarina="yes" ;;
        *) echo "unrecognized option" ; usage ;;
    esac
done

# 2) consolidate configuration parameters

: ${build_ocarina_from_scratch=$build_ocarina_from_scratch_default}
: ${update_ocarina=$update_ocarina_default}
: ${debug=$debug_default}
: ${build_ocarina=$build_ocarina_default}
: ${package_ocarina=$package_ocarina_default}
: ${test_ocarina=$test_ocarina_default}

if test x"${debug}" = x"yes"; then
    echo build_ocarina_from_scratch: $build_ocarina_from_scratch
    echo update_ocarina : $update_ocarina
    echo debug : $debug
    echo build_ocarina : $build_ocarina
    echo package_ocarina : $package_ocarina
    echo test_ocarina : $test_ocarina

    echo build ocarina with debug:    $ocarina_debug
    echo build ocarina with coverage: $ocarina_coverage
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
fi

exit 0
