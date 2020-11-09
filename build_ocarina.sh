#! /bin/bash

###############################################################################
# MIT License
#
# Copyright (c) 2016-2020 OpenAADL
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
###############################################################################

# This script performs various actions to checkout Ocarina sources,
# compile it, run regression testing, build source or binary package,
# install it, etc.

######################
# script configuration

root_script_dir="$(dirname "$0")"; cd "${root_script_dir}" || exit 1; root_script_dir=$(pwd)
the_date=$(date +"%Y%m%d")
tmp_dir="$HOME/tmp"; mkdir -p "$tmp_dir"
is_error=$tmp_dir/build_ocarina_ERROR; rm -f "$is_error"

LANG=C        # ensure there is no pollution from language-specific locales
GNU_MAKE=make # default make utility
IFS=' '

# Determine BUILDER_OS_NAME if not set
# From https://github.com/uclouvain/openjpeg/blob/master/tools/travis-ci/run.sh

if [ "${BUILDER_OS_NAME:-}" == "" ]; then
  # Let's guess OS for testing purposes
        echo "Guessing OS"
        if uname -s | grep -i Darwin &> /dev/null; then
                BUILDER_OS_NAME=osx
        elif uname -s | grep -i Linux &> /dev/null; then
                BUILDER_OS_NAME=linux
                if [ "${CC:-}" == "" ]; then
                        # default to gcc
                        export CC=gcc
                fi
        elif uname -s | grep -i CYGWIN &> /dev/null; then
                BUILDER_OS_NAME=windows
        elif uname -s | grep -i MINGW &> /dev/null; then
                BUILDER_OS_NAME=windows
        elif [ "${APPVEYOR:-}" == "True" ]; then
                BUILDER_OS_NAME=windows
        else
            echo "Failed to guess OS";
            echo $(uname -a)
        fi
        echo "${BUILDER_OS_NAME}"
fi

######################
# Target specific flags for configure go there
case "$(uname -s)" in

    Darwin)
        build_platform=darwin-$(uname -m)
        src_suffix=".tar.gz"
        bin_suffix=".tgz"
        ;;

    Linux)
        build_platform=linux-$(uname -m)
        src_suffix=".tar.gz"
        bin_suffix=".tgz"
        ;;

    CYGWIN*)
        # For Cygwin, we assume we "cross compile"
#        target_specific="--target=x86_64-w64-mingw32"
        build_platform=windows-x86
        src_suffix=".tar.gz"
        bin_suffix=".zip"
        ;;

    MINGW32*|MSYS*)
        build_platform=windows-$(uname -m)
        src_suffix=".tar.gz"
        bin_suffix=".zip"
        ;;
    esac

##################################
# Ocarina build-time configuration

include_runtimes="polyorb-hi-ada polyorb-hi-c aadlib" # Ocarina runtimes

# Note: check Ocarina configure script for details

ocarina_doc=""                        # --enable-doc to build documentation
ocarina_debug=""                      # --enable-debug to enable debug
ocarina_coverage=""                   # --enable-gcov to enable coverage
ocarina_python=""                     # --enable-python to build Python bindings
ocarina_flags=""                      # combination of the above

# Default installation prefix, can be overidden by the --prefix parameter
prefix_default=${root_script_dir}/ocarina_repos_install
install_dir_default=${root_script_dir}/tools
ocarina_dist_install=${root_script_dir}/ocarina_dist_install

# Defaut repository, can be overriden by the --remote parameter
repository_default="https://github.com/OpenAADL"
git_tag=""
release_tag=""
verbose=""
force_build=""
remote_args=""
remote_host=""

#############################
# build_ocarina configuration

build_info_default="no"                 # "yes" to print build info
debug_default="no"                      # "yes" to print debugging traces
self_update_default="no"                # "yes" to update the current script then exit
update_ocarina_default="no"             # "yes" to update the source directory
upload_ocarina_default="no"             # "yes" to upload Ocarina archives
build_ocarina_from_scratch_default="no" # "yes" to reload source directory
build_ocarina_default="no"              # "yes" to build Ocarina
configure_ocarina_default="no"          # "yes" to build Ocarina
remove_install_prefix="no"              # "yes" to remove install prefix
distclean_ocarina_default="no"          # "yes" to distclean Ocarina
package_ocarina_default="no"            # "yes" to package Ocarina
test_ocarina_default="no"               # "yes" to run make check

###############################################################################
# These two functions print log/error messages, with the FAILED/PASSED
# colored and right align.

log_msg() {
    MSG="$1"
    STATUS="[PASSED]"
    let COL=$(tput cols)-8-${#MSG}-${#STATUS}

    printf "%s\e[1;32m%${COL}s\e[0m\n" "" "${STATUS}"
}

error_msg() {
    MSG="$1"
    STATUS="[FAILED]"
    let COL=$(tput cols)-8-${#MSG}-${#STATUS}

    printf "%s\e[1;33m%${COL}s\e[0m\n" "${MSG}" "${STATUS}"
}

###############################################################################
# Small spinner wheel, from
# http://stackoverflow.com/questions/12498304/using-bash-to-display-a-progress-working-indicator
# this ensures continuous activity being on display, and prevent
# timeout, e.g. from Travis-CI

spinner() {
    local pid=$!
    # PID of the previous command launched in background

    local delay=.75
    local spinstr='|/-'\\
    while ps a | awk '{print $1}' | grep -q "$pid" ; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
    wait $pid
    return $?
}

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
    if [ -f "${is_error}" ]; then
        exit 0
    fi

    # Execute the command and get the result in a temporary file

    try_cmd_and_args="$1"
    try_msg="$2"
    try_report="${tmp_dir}/report.$$"

    printf "[$(date +"%Y-%m-%d-%H:%M")] %s" "${try_msg}"

    ( ${try_cmd_and_args} >> "${try_report}" 2>&1 ) & spinner
    return_code=$?

    # Print full log in case of verbose mode

    if test x"${verbose}" = x"yes"; then
        cat "${try_report}"
    fi

    # If the execution succeded, exit normally, else, returns the log

    if [ ${return_code} -eq 0 ] ; then
        log_msg "[$(date +"%Y-%m-%d-%H:%M")] ${try_msg}"
        rm -f "${try_report}"
        return 0
    fi

    error_msg "[$(date +"%Y-%m-%d-%H:%M")] ${try_msg}"

    # Set error

    touch "${is_error}"

    # Display the report message and abort
    tail -n 500 "${try_report}"

    exit 1
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

    echo "Preparing archive: format ${format}"

    case "${format}" in
        .tar.gz | .tgz )
            tar czf "${archive_name}" "${directory}"
            ;;

        .tar.bz2 | .tbz2 )
            tar cjf "${archive_name}" "${directory}"
            ;;

        .zip )
            echo $(which zip)
            zip -q -r "${archive_name}" "${directory}" || exit 1
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

        cd "${root_script_dir}" || exit 1

        # Fetch Ocarina sources

        rm -rf ocarina
        try "git clone ${repository}/ocarina.git" \
            "Checkout the Ocarina sources"

        cd ocarina || exit 1

        if test ! -z "${git_tag}"; then
            try "git checkout ${git_tag} -b ${git_tag}" "Fetching tag '${git_tag}'"
        fi;

        # Check out the requested runtimes

        if test ! -z "${include_runtimes}"; then
            tag_option=""
            if test ! -z "${git_tag}"; then
                tag_option="--tag=${git_tag}"
            fi;

            try "./support/get_runtimes.sh --root_url=${repository} ${tag_option} ${include_runtimes}" \
                "Fetching runtimes '${include_runtimes}'"
        fi;

    else
        cd "${root_script_dir}/ocarina" || exit 1
        try "git pull" "Updating Ocarina repository"

        # Update the requested runtimes

        if test ! -z "${include_runtimes}"; then
            cd resources/runtime || exit 1
            for r in ${include_runtimes}; do
                cd "${r}" || exit
                try "git pull" "Updating runtime '${r}'"
                cd ..
            done
            cd ../.. || exit 1
        fi
    fi
}

###############################################################################
# Configure Ocarina source directory

do_configure_ocarina() {
    cd "${root_script_dir}/ocarina" || exit 1

    # Bootstrap the build
    try "./support/reconfig" "Reconfiguring (Ocarina)"

    # Configuring
    try "./configure ${target_specific} ${ocarina_flags} --prefix=${prefix}" \
        "First configure (Ocarina)"

}

###############################################################################
# Test the Ocarina build from the repository

do_build_ocarina() {
    cd "${root_script_dir}/ocarina" || exit 1

    # Skip Ocarina building if tree is clean and version is identical

    HEAD="$(git log --oneline | head -1 | cut -d' ' -f1)"
    VERSION_INSTALLED="$(ocarina -v 2>&1 | grep ^Oca | awk '{print $NF}' | sed 's,),,;s,r,,')"

    git status >/dev/null
    TREE_CLEAN=$?

    if [ ${TREE_CLEAN} -eq 0 ] && [ "${HEAD}" == "${VERSION_INSTALLED}" ] && [ "${force_build}" == "" ] ; then
        echo Ocarina tree is clean and already installed. Skipping Ocarina build...
        exit 0
    fi

    # Bootstrap the build
    try "./support/reconfig" "Reconfiguring (Ocarina)"

    # Configuring
    try "./configure ${target_specific} ${ocarina_flags} --prefix=${prefix}" \
        "First configure (Ocarina)"

    # Building
    try "${GNU_MAKE}" "Doing '${GNU_MAKE}' (Ocarina)"

    # Installing
    if test x"${remove_install_prefix}" = x"yes"; then
        if test -d "${prefix}"; then
            try "rm -rf ${prefix}" "Removing old install dir"
        fi
    fi

    try "${GNU_MAKE} install" "Doing '${GNU_MAKE} install' (Ocarina)"

    echo "Ocarina installation is now complete !"
    echo "Note: you may want to add"
    echo " ${prefix}/bin to PATH"
    echo " ${prefix}/lib to LD_LIBRARY_PATH"
}

###############################################################################
# Testing repository version of Ocarina

do_test_ocarina() {
    cd "${root_script_dir}/ocarina" || exit 1

    try "${GNU_MAKE} check" "Testing (Ocarina)"

    if test x"${ocarina_coverage}" != x""; then
        try "./autotest.sh -l" "Generating coverage report"
    fi
}

###############################################################################
# Packaging Ocarina

do_packaging() {
    cd "${root_script_dir}/ocarina" || exit 1

    # Bootstrap the build
    try "./support/reconfig" "Reconfiguring (Ocarina)"

    # Clean up old archives and build tree
    old_archive="$(ls "ocarina-*${src_suffix}" 2> /dev/null)"
    rm -f "${old_archive}"

    try "./configure ${target_specific} ${ocarina_flags} --prefix=${prefix}" \
        "Configure for dist (Ocarina)"

    # Packaging and testing the package

    try "${GNU_MAKE} dist DISTCHECK_CONFIGURE_FLAGS='--disable-debug'" \
        "${GNU_MAKE} dist (Ocarina)"

    archive="$(ls ocarina-*${src_suffix})"
    echo "  => Archive ${archive} built in directory $(pwd)"

    # Source snapshot

    base_archive_name=$(basename "${archive}" "${src_suffix}")
    src_archive_name="${base_archive_name}-suite-src-${the_date}${src_suffix}"
    mv "${archive}" "${src_archive_name}"
    echo "  => Source archive ready:" "${src_archive_name}"
}

###############################################################################
# Build the binary package for the Ocarina suite

do_self_update() {
     try "git pull origin master" "Self updating"

}

###############################################################################
# Build the binary package for the Ocarina suite

do_build_from_tarball() {
    cd "${root_script_dir}/ocarina" || exit 1

    archive_dir=$(basename "${src_archive_name}" "${src_suffix}")
    rm -r  "${archive_dir}"
    mkdir -p "${archive_dir}"

    # Extract the archive
    try "tar xzvf ${src_archive_name} -C ${archive_dir} --strip-components=1" "extracting archive ${src_archive_name}"

    cd "${archive_dir}" || exit 1

    # Configuring
    try "./configure ${target_specific} --disable-debug --prefix=${ocarina_dist_install}" \
        "DIST: configure (Ocarina)"

    # Building
    try "${GNU_MAKE}" "DIST: ${GNU_MAKE} (Ocarina)"

    # Installing
    if test -d "${ocarina_dist_install}"; then
        try "rm -rf ${ocarina_dist_install}" "DIST: Removing old install dir"
    fi

    try "${GNU_MAKE} install-strip" "DIST: ${GNU_MAKE} install-strip (Ocarina)"

    # Clean up
    try "${GNU_MAKE} distclean" "DIST: ${GNU_MAKE} distclean (Ocarina)"
    cd ..

    # Binary snapshots (Runtime and Examples)
    bin_dir="${base_archive_name}-suite-${build_platform}-${the_date}"
    bin_archive="${bin_dir}${bin_suffix}"
    rm -rf "${bin_dir}"
    mkdir "${bin_dir}"
    cp -rf "${ocarina_dist_install}"/* "${bin_dir}/"

    # Remove any previous archive
    try "rm -rf ocarina-*${bin_suffix}" "DIST: remove old archives"

    # Create the archive
    do_archive "${bin_archive}" "${bin_suffix}" "${bin_dir}"

    rm -rf "${bin_dir}"

    archive="$(ls ocarina-*${bin_suffix})"
    echo "  => Archive ${archive} built in directory $(pwd)"

}

###############################################################################
# Run distclean in Ocarina build dir

do_distclean() {
    cd "${root_script_dir}/ocarina" || exit 1

    # Clean up
    try "${GNU_MAKE} distclean" "DIST: ${GNU_MAKE} distclean (Ocarina)"
    cd ..
}

###############################################################################
# Install crontab to run nightly-build scenario

do_install_crontab() {
    # See
    # http://stackoverflow.com/questions/878600/how-to-create-cronjob-using-bash
    # for details on this set of commands

    command="$root_script_dir/build_ocarina.sh --selfupdate && $root_script_dir/build_ocarina.sh --scenario=nightly-build"
    job="0 0 * * 0 $command"

    cat <(grep -F -i -v "$command" <(crontab -l)) <(echo "$job") | crontab -
}

###############################################################################
# Upload Ocarina archive

do_upload() {
    sftp "${USER}"@"${URI}":"${TARGET_DIR}" <<< $'put ./ocarina/ocarina-*.tar.gz'
    sftp "${USER}"@"${URI}":"${TARGET_DIR}" <<< $'put ./ocarina/ocarina-*.tgz'

}

###############################################################################
# Push a release
# Note: we use GitHub + Travis-CI for pushing a release archive to GitHub

do_release() {
    cd "${root_script_dir}/ocarina" || exit 1

    echo "Preparing release for $release_tag"

    git tag -d "v$release_tag"
    git push origin :refs/tags/"v$release_tag"
    git tag -a "v$release_tag" -m "Ocarina $release_tag"
    git push origin "v$release_tag"
    git push origin master
}

###############################################################################
# Do a remote execution of the build on host $remote_host

do_remote() {

    # We filter out the remote-build argument to avoid recursion
    ARGS=()
    for var in ${remote_args[@]}; do
        [[ "$var" != *"remote-build"* ]] && ARGS+=("$var")
    done

    script_name=`basename "$0"`

    echo Build on remote host $remote_host with $ARGS
    scp "${script_name}" ${remote_host}: || exit 1
    ssh "${remote_host}" "./${script_name} $ARGS"
}

###############################################################################
# Install GNAT (adapted from libadalang project)

do_install_gnat_ce() {
    : ${INSTALL_DIR=$install_dir_default}

    if ! [ -d $INSTALL_DIR ]
    then
        mkdir -p $INSTALL_DIR
    fi
    echo "Installing GNAT CE in $INSTALL_DIR"

    # Get and install GNAT
    if ! [ -d gnat_community_install_script ]
    then
        git clone https://github.com/AdaCore/gnat_community_install_script.git
    else
        (cd gnat_community_install_script && git pull)
    fi

    if ! [ -f $INSTALL_DIR/bin/gcc ]
    then
        if [ $BUILDER_OS_NAME = linux ]; then
            GNAT_INSTALLER=$PWD/gnat-community-2019-20190517-x86_64-linux-bin
            GNAT_INSTALLER_URL="https://community.download.adacore.com/v1/0cd3e2a668332613b522d9612ffa27ef3eb0815b?filename=gnat-community-2019-20190517-x86_64-linux-bin"
        else
            GNAT_INSTALLER=$PWD/gnat-community-2019-20190517-x86_64-darwin-bin.dmg
            GNAT_INSTALLER_URL="https://community.download.adacore.com/v1/5a7801fc686e86de838cfaf7071170152d81254d?filename=gnat-community-2019-20190517-x86_64-darwin-bin.dmg"
        fi

        wget -O $GNAT_INSTALLER $GNAT_INSTALLER_URL
        sh gnat_community_install_script/install_package.sh \
           "$GNAT_INSTALLER" "$INSTALL_DIR"
    fi
}

###############################################################################
# Print usage
usage() {
    echo "Usage: $0 [switches]"
    echo ""
    echo "General commands"
    echo " -h | --help        : print usage"
    echo " --version          : return script version, as a git hash"
    echo " --self-update      : update this script"
    echo " --install_crontab  : install crontab, then exit"
    echo " --purge            : delete source and build directories"
    echo " --verbose          : return full log of each action"
    echo ""
    echo "Script commands"
    echo " -c | --configure   : configure Ocarina source directory"
    echo " -u | --update      : update Ocarina source directory"
    echo " -b | --build       : configure, build and install Ocarina"
    echo " -t | --run-test    : run Ocarina testsuite, plus runtimes and AADLib"
    echo " -p | --package     : package ocarina distribution as tarball"
    echo " --upload           : upload archives, see source code for details"
    echo " --distclean        : distclean Ocarina build directory"
    echo " --remove-prefix    : remove prefix prior to installation"
    echo " --release          : release Ocarina on GitHub"
    echo " --force            : force build"
    echo " --install-gnat-ce  : install GNAT Community Edition in \$TOOLS_DIR"
    echo ""
    echo "Update-time options, options to be passed along with -u"
    echo " -s | --reset       : reset source directory prior to update"
    echo " --remote=<URL>     : Set URL of the Ocarina git repository"
    echo " --tag=<tag>        : Fetch a given tag"
    echo ""
    echo "Build-time options, options to be passed along with -b"
    echo " --prefix=<dir>     : install ocarina in <dir>"
    echo " --enable-doc       : enable building the documentation"
    echo " --enable-gcov      : enable coverage during ocarina build"
    echo " --enable-debug     : enable debug during ocarina build"
    echo " --enable-python    : enable Python bindings"
    echo " --build-info       : display information on build environment"
    echo ""
    echo "Scenarios, specific combination of parameters"
    echo " --scenario=<name>  : run a specific scenario"
    echo ""
    echo " Valid names are coverage fresh-install nightly-build taste github"
    echo " See source code for details on actual parameters"
    echo ""
    echo " Note: a default scenario can be passed using the OCARINA_SCENARIO"
    echo " environment variable"
    echo ""
    echo "Remote build:"
    echo " --remote-build=login@host : do a remote build on host through ssh"
}

###############################################################################
# Main function starts here

# 1) parse command line parameters

: "${scenario:=$OCARINA_SCENARIO}"

# Do a back-up of the arguments
initial_args=$@

while test $# -gt 0; do
  case "$1" in
      -*=*) arg="$1"
            optarg=${arg//[-_a-zA-Z0-9]*=/}
            ;;
      *) optarg="" ;;
  esac

  case $1 in
      --build | -b) build_ocarina="yes"  ;;
      --build-info) build_info="yes" ;;
      -c | --configure) configure_ocarina="yes" ;;
      -d) debug="yes" ;;
      --distclean) distclean_ocarina="yes";;
      --enable-doc) ocarina_debug="--enable-doc" ;;
      --enable-debug) ocarina_debug="--enable-debug" ;;
      --enable-gcov) ocarina_coverage="--enable-gcov" ;;
      --enable-python) ocarina_python="--enable-python --enable-shared";;
      --force) force_build="yes";;
      --help | -h) usage 1>&2 && exit 1 ;;
      --install_crontab) do_install_crontab && exit 1 ;;
      --install-gnat-ce) do_install_gnat_ce && exit 1 ;;
      --package | -p) package_ocarina="yes" ;;
      --prefix=*) prefix=${optarg};;
      --purge) rm -rf "${ocarina_dist_install}" ocarina && exit 1;;
      --remote=*) repository=${optarg};;
      --release=*) (release_tag=${optarg} ; do_release) && exit 1;;
      --remote-build=*) (remote_args=${initial_args} ; remote_host=${optarg}; do_remote) && exit 1;;
      --remove-prefix) remove_install_prefix="yes" ;;
      --reset | -s) build_ocarina_from_scratch="yes" ;;
      --run-test | -t) test_ocarina="yes" ;;
      --scenario=*) scenario=${optarg};;
      --self-update) self_update="yes" ;;
      --tag=*) git_tag=${optarg} ;;
      --update | -u) update_ocarina="yes" ;;
      --upload) upload_ocarina="yes";;
      --version) git log -1 --pretty=format:%h  && exit 1 ;;
      --verbose) verbose="yes";;
      *) echo "$1: invalid flag" && echo "" && usage 1>&2 && exit 1 ;;
  esac
  shift
done

if test -n "$scenario"; then
case $scenario in
    fresh-install)
        # In this scenario, we do a fresh install of Ocarina, the user
        # may override the installation prefix using --prefix
        build_info="yes"
        build_ocarina_from_scratch="yes"
        update_ocarina="yes"
        build_ocarina="yes"
        ;;

    github)
        # For GitHub, we build Ocarina, run all tests and package the
        # binary.
        ocarina_debug="--enable-debug"
        ocarina_coverage="--enable-gcov"
        build_info="yes"
        build_ocarina_from_scratch="yes"
        update_ocarina="yes"
        build_ocarina="yes"
        test_ocarina="yes"
        package_ocarina="yes"
        verbose="no"
        force_build="yes"
        ;;

    nightly-build)
        build_info="yes"
        update_ocarina="yes"
        build_ocarina="yes"
        test_ocarina="yes"
        package_ocarina="yes"
        ;;

    coverage)
        update_ocarina="yes"
        build_ocarina="yes"
        test_ocarina="yes"
        ocarina_debug="--enable-debug"
        ocarina_coverage="--enable-gcov"
        ;;

    taste)
        # In this scenario, we update and build Ocarina with Python
        # and debug enabled. Use TASTE specific installation prefix
        update_ocarina="yes"
        build_ocarina="yes"
        ocarina_debug="--enable-debug"
        #ocarina_python="--enable-python --enable-shared"
        prefix="$HOME/tool-inst"
        remove_install_prefix="no"
        ;;

    *) echo "Invalid scenario name $scenario" && exit 1;;
esac
fi

ocarina_flags="${ocarina_doc} ${ocarina_debug} ${ocarina_coverage} ${ocarina_python}"

# 2) consolidate configuration parameters

: ${build_info=$build_info_default}
: ${build_ocarina_from_scratch=$build_ocarina_from_scratch_default}
: ${update_ocarina=$update_ocarina_default}
: ${upload_ocarina=$upload_ocarina_default}
: ${configure_ocarina=$configure_ocarina_default}
: ${distclean_ocarina=$distclean_ocarina_default}
: ${self_update=$self_update_default}
: ${debug=$debug_default}
: ${build_ocarina=$build_ocarina_default}
: ${package_ocarina=$package_ocarina_default}
: ${test_ocarina=$test_ocarina_default}
: "${prefix="$prefix_default"}"
: ${repository=$repository_default}

if test x"${debug}" = x"yes"; then
    echo build_ocarina_from_scratch : "$build_ocarina_from_scratch"
    echo update_ocarina : "$update_ocarina"
    echo debug : "$debug"
    echo build_ocarina : "$build_ocarina"
    echo package_ocarina : "$package_ocarina"
    echo test_ocarina : "$test_ocarina"
    echo prefix : "$prefix"

    echo build ocarina with debug: "$ocarina_debug"
    echo build ocarina with coverage: "$ocarina_coverage"
    echo build ocarina with Python: "$ocarina_python"
fi

# 3) general execution scheme

if test x"${build_info}" = x"yes"; then
    if [ -f /etc/os-release ]
    then
        # For (recent) Linux platform, returns the name of the
        # distribution + CPU architecture
        . /etc/os-release
        echo "OS:       " "$PRETTY_NAME" "$(uname -m)"
    else
        # For other OS, return uname information
        echo "OS:       " "$(uname -msr)"
    fi

    echo "Compiler: " "$(gnatmake --version | head -n 1)"
    echo "autoconf: " "$(autoconf --version | head -n 1)"
    echo "automake: " "$(automake --version | head -n 1)"
    echo "sed:      " "$(which sed)"

fi

if test x"${self_update}" = x"yes"; then
    do_self_update
fi

if test x"${update_ocarina}" = x"yes"; then
    do_check_out
fi

if test x"${configure_ocarina}" = x"yes"; then
    do_configure_ocarina
fi

if test x"${distclean_ocarina}" = x"yes"; then
    do_distclean
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

if test x"${upload_ocarina}" = x"yes"; then
    do_upload
fi

exit 0
