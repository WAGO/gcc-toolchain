#!/bin/bash
# 
#   Copyright (C) 2016 Linaro, Inc
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

# This file contains the logic which sequences the steps which are performed
# during a build

# build_steps is an associative array. The keys are the names of the enabled
# build steps
declare -A build_steps

# build_step_required indicates whether a step is required for the build to
# proceed further.
declare -A build_step_required

build_component_list=""
check_component_list=""

build_step_required[RETRIEVE]=1
build_step_RETRIEVE()
{
    retrieve_all "$build_component_list"
}


build_step_required[CHECKOUT]=1
build_step_CHECKOUT()
{
    checkout_all "$build_component_list"
}

build_step_required[MANIFEST]=1
build_step_MANIFEST()
{
    manifest="$(manifest)"
}

build_step_required[BUILD]=1
build_step_BUILD()
{
    build_all "$build_component_list"
}

build_step_HELLO_WORLD()
{
    if ! is_package_in_runtests "${build_component_list}" "stage2"; then
        notice "Hello World test skipped because stage2 was not built"
        return 0
    fi

    dryrun "(hello_world)"
    if test $? -eq 0; then
        notice "Hello World test succeeded"
        return 0
    fi

    error "Hello World test failed"
    return 1
}

build_step_CHECK()
{
    local check=""
    # Replace pseudo component names by the actual component name:
    # stage[12] -> gcc
    # libc -> newlib|glibc|eglibc
    local build_names="$(echo $build_component_list | sed -e 's/stage[12]/gcc/' -e s/\\blibc\\b/${clibrary}/)"
    local component
    for component in $check_component_list; do
        if is_package_in_runtests "${build_names}" "$component"; then
	    check="$check ${component}"
	fi
    done
    notice "Checking $check"
    check_all "$check"
}

build_step_INSTALL_SYSROOT()
{
    do_install_sysroot
}

build_step_TARSRC()
{
    do_tarsrc
}

build_step_TARBIN()
{
    do_tarbin
}

perform_build_steps()
{
    notice "enabled build steps (not in order): ${!build_steps[*]}"

    local step
    for step in RETRIEVE CHECKOUT MANIFEST BUILD CHECK INSTALL_SYSROOT HELLO_WORLD TARSRC TARBIN; do
        if [ ! -z "${build_steps[$step]}" ]; then
	    # this step is enabled
	    notice "Performing build step $step"
            eval "build_step_$step"
	    if test $? -ne 0; then
		error "Step $step failed"
		return 1
	    fi
	else
	    # this step is not enabled, so we finish here if it's a
	    # required step.
	    if [ ! -z "${build_step_required[$step]}" ]; then
		break
	    fi
	fi
    done
}

# convert high-level command line operations into the list of steps which
# must be performed.
#
# set_build_steps <checkout|build|tarsrc|tarbin|check>
#
set_build_steps()
{
    case "$1" in
	retrieve)
	    build_steps[RETRIEVE]=1
	    ;;
	checkout)
	    build_steps[RETRIEVE]=1
	    build_steps[CHECKOUT]=1
	    build_steps[MANIFEST]=1
	    ;;
	build)
	    build_steps[RETRIEVE]=1
	    build_steps[CHECKOUT]=1
	    build_steps[MANIFEST]=1
	    build_steps[BUILD]=1
	    build_steps[INSTALL_SYSROOT]=1
	    build_steps[HELLO_WORLD]=1
	    ;;
	tarsrc)
	    build_steps[TARSRC]=1
	    ;;
	tarbin)
	    build_steps[TARBIN]=1
	    ;;
	check)
	    build_steps[CHECK]=1
	    ;;
    esac
}

# set list of components to be checked out and built (if those steps are
# enabled in build_steps array)
set_build_component_list()
{
   build_component_list="$1"
}

get_build_component_list()
{
   echo "${build_component_list}"
}

# set list of components to be checked (make check) if CHECK build step is
# enabled in build_steps array)
set_check_component_list()
{
   check_component_list="$1"
}

get_check_component_list()
{
   echo "${check_component_list}"
}

