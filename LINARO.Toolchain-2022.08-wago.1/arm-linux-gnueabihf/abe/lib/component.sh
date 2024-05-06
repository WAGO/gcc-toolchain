#!/bin/bash
# 
#   Copyright (C) 2015, 2016 Linaro, Inc
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
# 

declare -ag toolchain

# This file attempts to turn an associative array into a semblance of a
# data structure. Note that this will only work with the bash shell.
#
# The default fields are calculated at runtime
# TOOL
# URL
# REVISION
# SRCDIR
# BUILDDIR
# FILESPEC
# MD5SUMS
# These values are extracted from the config/[component].conf files
# BRANCH
# MAKEFLAGS
# STATICLINK
# CONFIGURE
# RUNTESTFLAGS
# MINGWEXTRACONF
# MINGWONLY

# Initialize the associative array
# parameters:
#	$ - Any parameter without a '=' sign becomes the name of the the array.
#           Any embedded spaces in the value have been converted to a '%'
#           character.
component_init ()
{
    #trace "$*"

    local component="$1"

    local index=
    for index in $*; do
	if test "$(echo ${index} | grep -c '=')" -gt 0; then
	    name="$(echo ${index} | cut -d '=' -f 1)"
	    value="$(echo ${index} | cut -d '=' -f2-20 | sed -e 's:^[a-zA-Z]*=::' | tr '%' ' ')"
	    eval "local ifset=\${${component}[${name}]:-notset}"
	    if test x"${ifset}" = x"notset"; then
		# $value is supposed to be safe for bare shell expansion
		# typically it is surrounded by double quotes
		eval "${component}[${name}]="${value}
		if test $? -gt 0; then
		    return 1
		fi
	    fi
	else
	    component="$(echo ${index} | sed -e 's:-[0-9a-z\.\-]*::')"
	    declare -Ag ${component}
	    eval ${component}[TOOL]="${component}"
	    if test $? -gt 0; then
		return 1
	    fi
	fi
	name=
	value=
    done

    toolchain=(${toolchain[@]} ${component})
    return 0
}

# Accessor functions for the data structure to set "private" data. This is a
# crude approximation of an object oriented API for this data structure. Each
# of the setters takes two arguments, which are:
#
# $1 - The name of the data structure, which is based on the toolname, ie...
# gcc, gdb, etc...  $2 - The value to assign the data field.
#
# Returns 0 on success, 1 on error
#
set_component_url ()
{
    __set_component_GENERIC URL "$@"
}

set_component_revision ()
{
    __set_component_GENERIC REVISION "$@"
}

set_component_srcdir ()
{
    __set_component_GENERIC SRCDIR "$@"
}

set_component_builddir ()
{
    __set_component_GENERIC BUILDDIR "$@"
}

set_component_filespec ()
{
    __set_component_GENERIC FILESPEC "$@"
}

set_component_branch ()
{
    __set_component_GENERIC BRANCH "$@"
}

set_component_makeflags ()
{
    __set_component_GENERIC MAKEFLAGS "$@"
}

set_component_configure ()
{
    __set_component_GENERIC CONFIGURE "$@"
}

set_component_md5sum ()
{
    __set_component_GENERIC MD5SUMS "$@"
}

set_component_mingw_extraconf ()
{
    __set_component_GENERIC MINGWEXTRACONF "$@"
}

set_component_mingw_only ()
{
    __set_component_GENERIC MINGWONLY "$@"
}

set_component_linuxhost_only ()
{
    __set_component_GENERIC LINUXHOSTONLY "$@"
}

# BRANCH is parsed from the config file for each component, but can be
# redefined on the command line at runtime.
#
# These next few fields are also from the config file for each component, but
# as defaults, they aren't changed from the command line, so don't have
# set_component_* functions.
#
# MAKEFLAGS
# STATICLINK
# CONFIGURE
# RUNTESTFLAGS

# Accessor functions for the data structure to get "private" data. This is a
# crude approximation of an object oriented API for this data structure. All of
# the getters take only one argument, which is the toolname, ie... gcc, gdb,
# etc...
#
# $1 - The name of the data structure, which is based on the toolname, ie...
# gcc, gdb, etc...
#
# Returns 0 on success, 1 on error, and the value is returned as a string.
#
get_component_url ()
{
    __get_component_GENERIC URL "$@"
}

get_component_revision ()
{
    __get_component_GENERIC REVISION "$@"
}

get_component_srcdir ()
{
    __get_component_GENERIC SRCDIR "$@"
}

get_component_builddir ()
{
    echo "$(__get_component_GENERIC BUILDDIR "$1")${2:+-$2}"
}

get_component_filespec ()
{
    __get_component_GENERIC FILESPEC "$@"
}

get_component_branch ()
{
    __get_component_GENERIC BRANCH "$@"
}

get_component_makeflags ()
{
    __get_component_GENERIC MAKEFLAGS "$@"
}

get_component_configure ()
{
#    trace "$*"

    local sopts=""
    local component=$1

    # Only GCC has parameters for two stages.
    if test x"${component}" = x"gcc"; then
	if test x"$2" != x; then
	    local stage="$(echo $2 | tr "[:lower:]" "[:upper:]")"
	    local sopts="${gcc[${stage}]}"
	fi
    fi

    if test "${component:+set}" != "set"; then
	warning "${component} does not exist!"
	return 1
    else
	eval "echo \${${component}[CONFIGURE]} ${sopts}"
    fi

    return 0
}

get_component_md5sum ()
{
    __get_component_GENERIC MD5SUMS "$@"
}

get_component_mingw_extraconf ()
{
    __get_component_GENERIC MINGWEXTRACONF "$@"
}

get_component_mingw_only ()
{
    __get_component_GENERIC MINGWONLY "$@"
}

get_component_linuxhost_only ()
{
    __get_component_GENERIC LINUXHOSTONLY "$@"
}


get_component_staticlink ()
{
    __get_component_GENERIC STATICLINK "$@"
}

get_component_runtestflags ()
{
    __get_component_GENERIC RUNTESTFLAGS "$@"
}

# Note that this function is GCC specific.
get_component_stage ()
{
#    trace "$*"

    local stage="$(echo $1 | tr "[:lower:]" "[:upper:]")"
    local component="gcc"

    if test "${component:+set}" != "set"; then
	warning "${component} does not exist!"
	return 1
    else
	eval "echo \${${component}[${stage}]}"
    fi

    return 0
}

# Determine if the component is a tarfile, or git repository.
# $1 - The component name.
component_is_tar ()
{
#    trace "$*"

    local component=$1
    if test "${component:+set}" != "set"; then
	warning "${component} does not exist!"
	return 1
    else
	if test "$(get_component_filespec ${component} | grep -c \.tar\.)" -gt 0; then
	    echo "yes"
	    return 0
	else
	    echo "no"
	    return 1
	fi
    fi
}

get_component_subdir ()
{
#    trace "$*"

    local component=$1
    if test "${component:+set}" != "set"; then
	warning "${component} does not exist!"
	return 1
    else
	if test "$(get_component_filespec ${component} | grep -c \.tar\.)" -gt 0; then
	    echo "yes"
	    return 0
	fi
    fi
}

# declare -p does print the same data from the array, but this is an easier to
# read version of the same data.
component_dump()
{
#    trace "$*"

    local flag="$(set -o | grep xtrace| tr -s ' ' | tr -d '\t' | cut -d ' ' -f 2)"
    set +x

    local component=$1
    if test "${component:+set}" != "set"; then
	warning "${component} does not exist!"
	return 1
    fi

    local data="$(declare -p ${component} | sed -e 's:^.*(::' -e 's:).*$::')"

    echo "Data dump of component \"${component}\""
    for i in ${data}; do
	echo "	$i"
    done

    if test x"${flag}" = x"on"; then
        set -x
    fi

    return 0
}

# read_conf_files () sources all scripts provided as arguments in a subshell
# then outputs resulting variables on stdout. This prevents conf files from
# making surprising changes to the environment or abe's internal variables.
read_conf_files ()
{
    local conf
    (
        set -eu
	# Set default values for host-related components, to avoid
	# repeating them in every .conf file.
	mingw_only=no
	linuxhost_only=no

        for conf in "$@"; do
	    if ! test -f "${conf}"; then
	        error "Warning: config file does not exist: ${conf}"
	        exit 1
	    fi
	    notice "Sourcing config file: ${conf}"

            . "$conf"
        done
        local var
	# configs also have the following unused vars:
	#    benchcmd benchcount benchlog configure
	# configs set these as temporary local variables, we ignore those:
	#    aarch64_errata languages tag
	# set in a special conf file which is parsed separately in abe.sh:
	#    preferred_libc
        for var in default_configure_flags default_makeflags latest mingw_extraconf mingw_only linuxhost_only runtest_flags stage1_flags stage2_flags static_link; do

            if [ "${!var:+set}" = "set" ]; then
                echo "local conf_$var=\"${!var}\""
            fi
        done
    )
}

collect_data_abe ()
{
    local component="abe"
    pushd ${abe_path}
    local revision="$(git log --format=format:%H -n 1)"
    local branch="$(git branch | grep "^\*" | cut -d ' ' -f 2)"
    if test "$(echo ${branch} | egrep -c "detached|^\(no|^\(HEAD")" -gt -0; then
        local branch=
    fi
    local url="$(git config --get remote.origin.url)"
    local url="$(dirname ${url})"
    local filespec="abe.git"
    local srcdir="${abe_path}"
    local configure=\""$(grep ${srcdir}/configure ${abe_top}/config.log | tr -s ' ' | cut -d ' ' -f 4-10| tr ' ' '%')"\"
    popd
    component_init ${component} TOOL=${component} ${branch:+BRANCH=${branch}} ${revision:+REVISION=${revision}} ${url:+URL=${url}} ${filespec:+FILESPEC=${filespec}} ${srcdir:+SRCDIR=${srcdir}} ${configure:+CONFIGURE=${configure}}
    if [ $? -ne 0 ]; then
	error "component_init failed"
	return 1
    fi
    return 0
}

collect_data ()
{
#    trace "$*"

    local component=$1

    if test x"${manifest:-}" != x; then
	notice "Reading data from Manifest file."
	return 0
    fi

    # ABE's data is extracted differently than the rest.
    if test x"${component}" = x"abe"; then
	collect_data_abe
	return $?
    fi

    if test -d ${local_builds}/${host}/${target}; then
	if find ${local_builds}/${host}/${target} -name ${component}.conf | grep -q ^; then
	    error "Local ${component}.conf files are no longer supported"
	    return 1
        fi
    fi

    local conf_list="${topdir}/config/${component}.conf"

    local default_conf="${topdir}/config/default/${component}.conf"
    if test -f "$default_conf"; then
	if grep -qv "^latest=\|^#" "$default_conf" \
		|| ! grep -q "^latest=" "$default_conf"; then
	    error "$default_conf should have only \"latest=\" and nothing else"
	    exit 1
	fi
        conf_list="${conf_list} ${default_conf}"
    fi

    conf_list="${conf_list} ${extraconfig[${component}]}"

    # import variables from conf files as local variables
    eval "$(read_conf_files $conf_list)"

    # This accesses the component version which was specified on the command
    # line, if any. The variable use_version will contain the version of the
    # component we are going to use for the build. If a component version was
    # specified on the command line, we use that, otherwise we use the latest
    # variable from the .conf files.
    local version_var="${component}_version"
    local current_component_version="${!version_var}"
    local use_version=
    if test x"${current_component_version}" = x; then
        use_version=${conf_latest}
    else
        use_version=${current_component_version}
    fi
    # TODO: dump() uses this, but this should be cleaned up so we can
    # remove this line.
    eval "${version_var}=${use_version}"

    if test $(echo ${use_version} | grep -c "\.tar") -gt 0; then
	# TODO: update conf files to include component name in name
	# of tarball, and remove this hack.
	if test "$(echo ${use_version} | grep -c ${component})" -eq 0; then
	    use_version="${component}-${use_version}"
	fi
	# Set up variables for component with tarball URL
	if test "$(echo ${use_version} | grep -c 'http.*://.*\.tar\.')" -eq 0; then
	    local url="$(grep "^${component} " ${sources_conf} | tr -s ' ' | cut -d ' ' -f 2)"
	    local filespec="${use_version}"
	else
	    local url="$(dirname ${use_version})"
	    local filespec="$(basename ${use_version})"
	fi

	local dir="$(echo ${filespec} | sed -e 's:\.tar.*::'| tr '@' '_')"
    else
	# Set up variables for component with git URL
	local branch="$(get_git_branch ${use_version})"
	if test x"${branch}" = x; then
	    branch="master"
	fi
	local revision="$(get_git_revision ${use_version})"
	local repo="$(get_git_url ${use_version})"
	local url=

	case "${repo}" in
	    *://*)
		# user specified a full URL
		url="${repo}" ;;
	    *)
		# look up full URL in sources.conf
		url="$(grep "^${repo}[[:space:]]" ${sources_conf} | head -n 1 | tr -s ' ' | cut -d ' ' -f 2)"
	esac
	if test x"{$url}" = x; then
	    warning "${repo} not found in ${sources_conf}"
	    return 1
	fi
	local filespec="$(basename ${url})"
	local url="$(dirname ${url})"
	# Builds will fail if there is an @ in the build directory path.
	# This is unfortunately, as @ is used to deliminate the revision
	# string.
	local fixbranch="$(echo ${branch} | tr '/' '~' | tr '@' '_')"
	local dir=${filespec}${branch:+~${fixbranch}}${revision:+_rev_${revision}}
    fi

    # configured and built as a separate way.
    local builddir="${local_builds}/${host}/${target}/${component}-${dir}"
    local srcdir=${local_snapshots}/${dir}

    # Extract a few other data variables from the conf file and store them so
    # the conf file only needs to be sourced once.
    local confvars="${conf_static_link:+STATICLINK=${conf_static_link}}"
    confvars="${confvars} ${conf_default_makeflags:+MAKEFLAGS=\"$(echo ${conf_default_makeflags} | tr ' ' '%')\"}"
    confvars="${confvars} ${conf_default_configure_flags:+CONFIGURE=\"$(echo ${conf_default_configure_flags} | tr ' ' '%')\"}"
    if test x"${component}" = "xgcc"; then
	confvars="${confvars} ${conf_stage1_flags:+STAGE1=\"$(echo ${conf_stage1_flags} | tr ' ' '%')\"}"
	confvars="${confvars} ${conf_stage2_flags:+STAGE2=\"$(echo ${conf_stage2_flags} | tr ' ' '%')\"}"
    fi
    confvars="${confvars} ${conf_runtest_flags:+RUNTESTFLAGS=\"$(echo ${conf_runtest_flags} | tr ' ' '%')\"}"
    confvars="${confvars} ${conf_mingw_only:+MINGWONLY=\"$(echo ${conf_mingw_only} | tr ' ' '%')\"}"
    confvars="${confvars} ${conf_mingw_extraconf:+MINGWEXTRACONF=\"$(echo ${conf_mingw_extraconf} | tr ' ' '%')\"}"
    confvars="${confvars} ${conf_linuxhost_only:+LINUXHOSTONLY=\"$(echo ${conf_linuxhost_only} | tr ' ' '%')\"}"
    component_init ${component} TOOL=${component} ${branch:+BRANCH=${branch}} ${revision:+REVISION=${revision}} ${srcdir:+SRCDIR=${srcdir}} ${builddir:+BUILDDIR=${builddir}} ${filespec:+FILESPEC=${filespec}} ${url:+URL=${url}} ${confvars}
    if [ $? -ne 0 ]; then
        error "component_init failed"
        return 1
    fi

    return 0
}

# internal function to implement set_component_*
__set_component_GENERIC ()
{
    local field=$1
    local component=$2
    local value=$3
    declare -p ${component} 2>&1 >/dev/null
    if [ "${component:+set}" = "set" ]; then
	eval ${component}[${field}]="$value"
    else
	warning "${component} does not exist"
	return 1
    fi

    return 0
}

# internal function to implement get_component_*
__get_component_GENERIC ()
{
#    trace "$*"

    local field=$1
    local component=$2
    if [ "${component:+set}" = "set" ]; then
	eval "echo \${${component}[${field}]}"
    else
	warning "${component} does not exist"
	return 1
    fi

    return 0
}
