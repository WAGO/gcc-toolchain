#!/bin/bash
# 
#   Copyright (C) 2013, 2014, 2015, 2016 Linaro, Inc
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

# This performs all the steps to build a full cross toolchain
build_all()
{
#    trace "$*"
    
    local builds="$*"

    notice "build_all: Building components: ${builds}"

    local build_all_ret=

    # build each component
    for i in ${builds}; do
        local mingw_only="$(get_component_mingw_only $i)"
        if [ x"$mingw_only" = x"yes" ] && ! is_host_mingw ; then
            notice "Skipping component $i, which is only required for mingw hosts"
            continue
        fi
        local linuxhost_only="$(get_component_linuxhost_only $i)"
        if [ x"$linuxhost_only" = x"yes" ] && ! is_host_linux ; then
            notice "Skipping component $i, which is only required for Linux hosts"
            continue
        fi
        notice "Building all, current component $i"
        case $i in
            # Build stage 1 of GCC, which is a limited C compiler used to compile
            # the C library.
            libc)
                build ${clibrary}
                build_all_ret=$?
                ;;
            stage1)
                build gcc stage1
                build_all_ret=$?
                ;; 
            # Build stage 2 of GCC, which is the actual and fully functional compiler
            stage2)
		# FIXME: this is a seriously ugly hack required for building Canadian Crosses.
		# Basically the gcc/auto-host.h produced when configuring GCC stage2 has a
		# conflict as sys/types.h defines a typedef for caddr_t, and autoheader screws
		# up, and then tries to redefine caddr_t yet again. We modify the installed
		# types.h instead of the one in the source tree to be a tiny bit less ugly.
		# After libgcc is built with the modified file, it needs to be changed back.
		if is_host_mingw; then
		    sed -i -e 's/typedef __caddr_t caddr_t/\/\/ FIXME: typedef __caddr_t caddr_t/' ${sysroots}/libc/usr/include/sys/types.h
		fi

                build gcc stage2
                build_all_ret=$?
		# Reverse the ugly hack
		if is_host_mingw; then
		    sed -i -e 's/.*FIXME: //' ${sysroots}/libc/usr/include/sys/types.h
		fi
                ;;
            expat)
		# TODO: avoid hardcoding the version in the path here
		dryrun "rsync -av ${local_snapshots}/expat-2.1.0-1/include $prefix/usr/"
		if [ $? -ne 0 ]; then
		    error "rsync of expat include failed"
		    return 1
		fi
		dryrun "rsync -av ${local_snapshots}/expat-2.1.0-1/lib $prefix/usr/"
		if [ $? -ne 0 ]; then
		    error "rsync of expat lib failed"
		    return 1
		fi
		;;
            python)
		# The mingw package of python contains a script used by GDB to
		# configure itself, this is used to specify that path so we
		# don't have to modify the GDB configure script.
		# TODO: avoid hardcoding the version in the path here...
		export PYTHON_MINGW=${local_snapshots}/python-2.7.4-mingw32
		# The Python DLLS need to be in the bin dir where the
		# executables are.
		dryrun "rsync -av ${PYTHON_MINGW}/pylib ${PYTHON_MINGW}/dll ${PYTHON_MINGW}/libpython2.7.dll $prefix/bin/"
		if [ $? -ne 0 ]; then
		    error "rsync of python libs failed"
		    return 1
		fi
		;;
	    libiconv)
		# TODO: avoid hardcoding the version in the path here
		dryrun "rsync -av ${local_snapshots}/libiconv-1.14-3/include ${local_snapshots}/libiconv-1.14-3/lib $prefix/usr/"
		if [ $? -ne 0 ]; then
		    error "rsync of libiconv failed"
		    return 1
		fi
		;;
            *)
		build $i
                build_all_ret=$?
                ;;
        esac
        #if test $? -gt 0; then
        if test ${build_all_ret} -gt 0; then
            error "Failed building $i."
            return 1
        fi
    done

    # Notify that the build completed successfully
    build_success

    return 0
}

get_glibc_version()
{
    local src="`get_component_srcdir glibc`"
    local version=`grep VERSION $src/version.h | cut -d' ' -f3`
    if [ $? -ne 0 ]; then
	version="0.0"
    fi
    eval "echo $version"

    return 0
}

is_glibc_check_runable()
{
    local glibc_version=`get_glibc_version`
    local glibc_major=`echo $glibc_version | cut -d'.' -f1`
    local glibc_minor=`echo $glibc_version | cut -d'.' -f2`

    # Enable glibc make for non native build only for version 2.21
    # or higher. This is mostly because the check system on older glibc
    # do not work reliable with run-built-tests=no.
    if [[ ( $glibc_major -ge 3) ||
          (( $glibc_major -eq 2 && $glibc_minor -ge 21 )) ]]; then
      return 0
    fi

    return 1
}

check_all()
{
    local test_packages="${1}"

    # If we're building a full toolchain the binutils tests need to be built
    # with the stage 2 compiler, and therefore we shouldn't run unit-test
    # until the full toolchain is built.  Therefore we test all toolchain
    # packages after the full toolchain is built. 
    if test x"${test_packages}" != x; then
	notice "Testing components ${test_packages}..."
	local check_ret=0
	local check_failed=

	is_package_in_runtests "${test_packages}" newlib
	if test $? -eq 0; then
	    make_check newlib
	    if test $? -ne 0; then
		check_ret=1
		check_failed="${check_failed} newlib"
	    fi
	fi

	is_package_in_runtests "${test_packages}" binutils
	if test $? -eq 0; then
	    make_check binutils
	    if test $? -ne 0; then
		check_ret=1
		check_failed="${check_failed} binutils"
	    fi
	fi

	is_package_in_runtests "${test_packages}" gcc
	if test $? -eq 0; then
	    make_check gcc stage2
	    if test $? -ne 0; then
		check_ret=1
		check_failed="${check_failed} gcc-stage2"
	    fi
	fi

	is_package_in_runtests "${test_packages}" gdb
	if test $? -eq 0; then
	    make_check gdb
	    if test $? -ne 0; then
		check_ret=1
		check_failed="${check_failed} gdb"
	    fi
	fi

	is_package_in_runtests "${test_packages}" glibc
	if test $? -eq 0; then
	    is_glibc_check_runable
	    if test $? -eq 0; then
		make_check glibc
		if test $? -ne 0; then
		    check_ret=1
		    check_failed="${check_failed} glibc"
		fi
	    fi
	fi

	is_package_in_runtests "${test_packages}" eglibc
	if test $? -eq 0; then
	    #make_check ${eglibc_version}
	    #if test $? -ne 0; then
		#check_ret=1
	        #check_failed="${check_failed} eglibc"
	    #fi
	    notice "make check on native eglibc is not yet implemented."
	fi

	if test ${check_ret} -ne 0; then
	    error "Failed checking of ${check_failed}."
	    return 1
	fi
    fi

    # Notify that the test run completed successfully
    test_success

    return 0
}


do_tarsrc()
{
    # TODO: put the error handling in, or remove the tarsrc feature.
    # this isn't as bad as it looks, because we will catch errors from
    # dryrun'd commands at the end of the build.
    notice "do_tarsrc has no error handling"
    if test "$(echo ${with_packages} | grep -c toolchain)" -gt 0; then
	release_binutils_src
	release_gcc_src
    fi
    if test "$(echo ${with_packages} | grep -c gdb)" -gt 0; then
        release_gdb_src
    fi
}

do_tarbin()
{
    # TODO: put the error handling in
    # this isn't as bad as it looks, because we will catch errors from
    # dryrun'd commands at the end of the build.
    notice "do_tarbin has no error handling"
    # Delete any previous release files
    # First delete the symbolic links first, so we don't delete the
    # actual files
    dryrun "rm -fr ${local_builds}/linaro.*/*-tmp ${local_builds}/linaro.*/runtime*"
    dryrun "rm -f ${local_builds}/linaro.*/*"
    # delete temp files from making the release
    dryrun "rm -fr ${local_builds}/linaro.*"

    if test x"${clibrary}" != x"newlib"; then
	binary_runtime
    fi

    binary_toolchain
    binary_sysroot

#    if test "$(echo ${with_packages} | grep -c gdb)" -gt 0; then
#	binary_gdb
#    fi
    notice "Packaging took ${SECONDS} seconds"
    
    return 0
}

build()
{
#    trace "$*"

    local component=$1
 
    local url="$(get_component_url ${component})"
    local srcdir="$(get_component_srcdir ${component})"
    local builddir="$(get_component_builddir ${component} $2)"

    if [ x"${srcdir}" = x"" ]; then
	# Somehow this component hasn't been set up correctly.
	error "Component '${component}' has no srcdir defined."
        return 1
    fi

    local version="$(basename ${srcdir})"
    local stamp=
    stamp="$(get_stamp_name $component build ${version} ${2:+$2})"

    # The stamp is in the build dir's parent directory.
    local stampdir="$(dirname ${builddir})"

    notice "Building ${component} ${2:+$2}"

    # We don't need to build if the srcdir has not changed!  We check the
    # build stamp against the timestamp of the srcdir.
    local ret=
    check_stamp "${stampdir}" ${stamp} ${srcdir} build ${force}
    ret=$?
    if test $ret -eq 0; then
	return 0
    elif test $ret -eq 255; then
        # Don't proceed if the srcdir isn't present.  What's the point?
        error "no source dir for the stamp!"
        return 1
    fi

    if [ x"$building" = x"no" ]; then
	return 0
    fi

    # configure_build is allowed to alter environment, e.g., set $PATH,
    # for build of a particular component, so run configure and build
    # in a sub-shell.
    (
	notice "Configuring ${component} ${2:+$2}"
	configure_build ${component} ${2:+$2}
	if test $? -gt 0; then
            error "Configure of $1 failed!"
            return $?
	fi
	
	# Clean the build directories when forced
	if test x"${force}" = xyes; then
            make_clean ${component} ${2:+$2}
            if test $? -gt 0; then
		return 1
            fi
	fi
	
	# Finally compile and install the libaries
	make_all ${component} ${2:+$2}
	if test $? -gt 0; then
            return 1
	fi
	
	# Build the documentation, unless it has been disabled at the command line.
	if test x"${make_docs}" = xyes; then
            make_docs ${component} ${2:+$2}
            if test $? -gt 0; then
		return 1
            fi
	else
            notice "Skipping make docs as requested (check host.conf)."
	fi
	
	# Install, unless it has been disabled at the command line.
	if test x"${install}" = xyes; then
            make_install ${component} ${2:+$2}
            if test $? -gt 0; then
		return 1
            fi
	else
            notice "Skipping make install as requested (check host.conf)."
	fi
	
	create_stamp "${stampdir}" "${stamp}"
	
	local tag="$(create_release_tag ${component})"
	notice "Done building ${tag}${2:+ $2}, took ${SECONDS} seconds"
	
	# For cross testing, we need to build a C library with our freshly built
	# compiler, so any tests that get executed on the target can be fully linked.
    ) &
    ret=0 && wait $! || ret=$?

    return $ret
}

make_all()
{
#    trace "$*"

    local component=$1

    # Linux isn't a build project, we only need the headers via the existing
    # Makefile, so there is nothing to compile.
    if test x"${component}" = x"linux"; then
        return 0
    fi

    local builddir="$(get_component_builddir ${component} $2)"
    notice "Making all in ${builddir}"

    local make_flags
    if test x"${parallel}" = x"yes" -a "$(echo ${component} | grep -c glibc)" -eq 0; then
	make_flags="${make_flags} -j ${cpus}"
    fi

    # Enable an errata fix for aarch64 that effects the linker
    if test "$(echo ${component} | grep -c glibc)" -gt 0 -a $(echo ${target} | grep -c aarch64) -gt 0; then
	make_flags="${make_flags} LDFLAGS=\"-Wl,--fix-cortex-a53-843419\" "
    fi

    if test "$(echo ${target} | grep -c aarch64)" -gt 0; then
	make_flags="${make_flags} LDFLAGS_FOR_TARGET=\"-Wl,-fix-cortex-a53-843419\" "
    fi

    # Use pipes instead of /tmp for temporary files.
    if test x"${override_cflags}" != x -a x"${component}" != x"eglibc"; then
	make_flags="${make_flags} CFLAGS_FOR_BUILD=\"-pipe -g -O2\" CFLAGS=\"${override_cflags}\" CXXFLAGS=\"${override_cflags}\" CXXFLAGS_FOR_BUILD=\"-pipe -g -O2\""
    else
	make_flags="${make_flags} CFLAGS_FOR_BUILD=\"-pipe -g -O2\" CXXFLAGS_FOR_BUILD=\"-pipe -g -O2\""
    fi

    if test x"${override_ldflags}" != x; then
        make_flags="${make_flags} LDFLAGS=\"${override_ldflags}\""
    fi

    # All tarballs are statically linked
    make_flags="${make_flags} LDFLAGS_FOR_BUILD=\"-static-libgcc\""

    # Some components require extra flags to make: we put them at the
    # end so that config files can override
    local default_makeflags="$(get_component_makeflags ${component})"

    if test x"${default_makeflags}" !=  x; then
        make_flags="${make_flags} ${default_makeflags}"
    fi

    if test x"${CONFIG_SHELL}" = x; then
        export CONFIG_SHELL=${bash_shell}
    fi

    if test x"${make_docs}" != xyes; then
        make_flags="${make_flags} BUILD_INFO=\"\" MAKEINFO=echo"
    fi
    local makeret=
    # GDB and Binutils share the same top level files, so we have to explicitly build
    # one or the other, or we get duplicates.
    local logfile="${builddir}/make-${component}${2:+-$2}.log"
    record_artifact "log_make_${component}${2:+-$2}" "${logfile}"
    dryrun "make SHELL=${bash_shell} -w -C ${builddir} ${make_flags} 2>&1 | tee ${logfile}"
    local makeret=$?
    
#    local errors="$(dryrun \"egrep '[Ff]atal error:|configure: error:|Error' ${logfile}\")"
#    if test x"${errors}" != x -a ${makeret} -gt 0; then
#       if test "$(echo ${errors} | egrep -c "ignored")" -eq 0; then
#           error "Couldn't build ${tool}: ${errors}"
#           exit 1
#       fi
#    fi

    # Make sure the make.log file is in place before grepping or the -gt
    # statement is ill formed.  There is not make.log in a dryrun.
#    if test -e "${builddir}/make-${tool}.log"; then
#       if test $(grep -c "configure-target-libgcc.*ERROR" ${logfile}) -gt 0; then
#           error "libgcc wouldn't compile! Usually this means you don't have a sysroot installed!"
#       fi
#    fi
    if test ${makeret} -gt 0; then
        warning "Make had failures!"
        return 1
    fi

    return 0
}

# Print path to dynamic linker in sysroot
# $1 -- whether dynamic linker is expected to exist
find_dynamic_linker()
{
    local strict="$1"
    local dynamic_linker c_library_version

    # Programmatically determine the embedded glibc version number for
    # this version of the clibrary.
    if test -x "${sysroots}/libc/usr/bin/ldd"; then
	c_library_version="$(${sysroots}/libc/usr/bin/ldd --version | head -n 1 | sed -e "s/.* //")"
	dynamic_linker="$(find ${sysroots}/libc -type f -name ld-${c_library_version}.so)"
	if [ x"$dynamic_linker" = x"" ]; then
	    dynamic_linker=$(grep "^RTLDLIST=" "$sysroots/libc/usr/bin/ldd" \
				 | sed -e "s/^RTLDLIST=//")
	    dynamic_linker="$sysroots/libc/$dynamic_linker"
	fi
    fi
    if $strict && [ -z "$dynamic_linker" ]; then
        error "Couldn't find dynamic linker ld-${c_library_version}.so in ${sysroots}/libc"
        exit 1
    fi
    echo "$dynamic_linker"
}

make_install()
{
#    trace "$*"

    local component=$1

    # Do not use -j for 'make install' because several build systems
    # suffer from race conditions. For instance in GCC, several
    # multilibs can install header files in the same destination at
    # the same time, leading to conflicts at file creation time.
    if echo "$makeflags" | grep -q -e "-j"; then
	warning "Make install flags contain -j: this may fail because of a race condition!"
    fi

    if test x"${component}" = x"linux"; then
        local srcdir="$(get_component_srcdir ${component}) ${2:+$2}"
	local ARCH="${target%%-*}"
	case "$ARCH" in
	    aarch64*) ARCH=arm64 ;;
	    arm*) ARCH=arm ;;
	    i?86*) ARCH=i386 ;;
	    powerpc*) ARCH=powerpc ;;
	esac
        dryrun "make ${make_opts} -C ${srcdir} headers_install ARCH=${ARCH} INSTALL_HDR_PATH=${sysroots}/libc/usr"
        if test $? != "0"; then
            error "Make headers_install failed!"
            return 1
        fi
        return 0
    fi


    local builddir="$(get_component_builddir ${component} $2)"
    notice "Making install in ${builddir}"

    if test "$(echo ${component} | grep -c glibc)" -gt 0; then
        local make_flags=" install_root=${sysroots}/libc ${make_flags} LDFLAGS=-static-libgcc"
    fi

    if test x"${override_ldflags}" != x; then
        local make_flags="${make_flags} LDFLAGS=\"${override_ldflags}\""
    fi

    if test x"${make_docs}" != xyes; then
	export BUILD_INFO=""
    fi

    # Don't stop on CONFIG_SHELL if it's set in the environment.
    if test x"${CONFIG_SHELL}" = x; then
        export CONFIG_SHELL=${bash_shell}
    fi

    local default_makeflags= #"$(get_component_makeflags ${component})"
    local install_log="$(dirname ${builddir})/install-${component}${2:+-$2}.log"
    record_artifact "log_install_${component}${2:+-$2}" "${install_log}"
    if [ x"${component}" = x"gdb" -o x"${component}" = x"gdbserver" ]; then
        dryrun "make install-${component} ${make_flags} ${default_makeflags} -w -C ${builddir} 2>&1 | tee ${install_log}"
    else
	dryrun "make install ${make_flags} ${default_makeflags} -w -C ${builddir} 2>&1 | tee ${install_log}"
    fi
    if test $? != "0"; then
        warning "Make install failed!"
        return 1
    fi

    # Decide whether now is a good time to copy GCC libraries into
    # sysroot.
    local copy_gcc_libs=false
    if is_host_mingw; then
	# For mingw builds we copy sysroot from a linux-hosted toolchain.
	:
    elif get_component_list | grep -q "stage1"; then
	if [ x"${component}" = x"gcc" -a x"$2" = x"stage2" ]; then
	    # This is a two-stage build, so copy GCC libraries to sysroot after
	    # install of gcc stage2.
	    copy_gcc_libs=true
	fi
    else
	if [ x"$component" = x"$clibrary" ]; then
	    # This is a single-stage build (most likely native), so copy gcc
	    # libraries after libc install.
	    copy_gcc_libs=true
	fi
    fi

    if $copy_gcc_libs; then
	dryrun "copy_gcc_libs_to_sysroot"
	if test $? != "0"; then
            error "Copy of gcc libs to sysroot failed!"
            return 1
	fi
    fi

    return 0
}

# Copy sysroot to test container and print out ABE_TEST_* settings to pass
# to dejagnu.
# $1 -- test container
print_make_opts_and_copy_sysroot ()
{
    (set -e
     local test_container="$1"

     local user machine port
     user="$(echo $test_container | cut -s -d@ -f 1)"
     machine="$(echo $test_container | sed -e "s/.*@//g" -e "s/:.*//g")"
     port="$(echo $test_container | cut -s -d: -f 2)"

     if [ x"$port" = x"" ]; then
	 error "Wrong format of test_container: $test_container"
	 return 1
     fi

     if [ x"$user" = x"" ]; then
	 user=$(ssh -p$port $machine whoami)
     fi

     # The overall plan is to:
     # 1. rsync libs to /tmp/<new-sysroot>
     # 2. regenerate /etc/ld.so.cache to include /tmp/<new-sysroot>
     #    as preferred place for any libs that it has.
     # 3. we need to be careful to update ld.so.cache at the same time
     #    as we update symlink for /lib/ld-linux-*so*; otherwise we risk
     #    de-synchronizing ld.so and libc.so, which will break the system.
     
     local ldso_bin lib_path ldso_link
     ldso_bin=$(find_dynamic_linker true)
     lib_path=$(dirname "$ldso_bin")

     local -a ldso_links
     ldso_links=($(find "$lib_path" -type l -name "ld-linux*.so*"))

     if [ "${#ldso_links[@]}" != "1" ]; then
	 # FIXME: This part should be broken with glibc 2.34 and newer
	 # due to glibc providing only straight ld-linux-ARCH.so.N binaries
	 # with no symlinks.
	 # We'll fix this when (and if) we start to use this code again.
	 error "Exactly one ld.so symlink is expected: ${ldso_links[@]}"
	 return 1
     fi
     ldso_link="${ldso_links[@]}"

     local dest_ldso_bin dest_lib_path dest_ldso_link
     dest_lib_path=$(ssh -p$port $user@$machine mktemp -d)
     dest_ldso_bin="$dest_lib_path/$(basename $ldso_bin)"
     dest_ldso_link="/$(basename "$lib_path")/$(basename "$ldso_link")"

     # Rsync libs and ldconfig to the target
     if ! rsync -az --delete -e "ssh -p$port" "$lib_path/" "$lib_path/../sbin/" "$user@$machine:$dest_lib_path/"; then
	 error "Cannot rsync sysroot to $user@machine:$port:$dest_lib_path/"
	 return 1
     fi

     # Prepare new ld.so.conf
     local dest_ldsoconf
     dest_ldsoconf=$(ssh -p$port $user@$machine mktemp)
     echo "$dest_lib_path" | ssh -p$port $user@$machine tee "$dest_ldsoconf" > /dev/null
     ssh -p$port $user@$machine "cat /etc/ld.so.conf | tee -a $dest_ldsoconf" > /dev/null

     # The most tricky moment!  We need to replace ld.so and re-generate
     # /etc/ld.so.cache in a single command.  Otherwise ld.so and libc will
     # get de-synchronized, which will render container unoperational.
     #
     # Adding new, rather than replacing, ld.so link is rather mundane.
     # E.g., adding ld.so for new abi (ILP32) is extremely unlikely to break
     # LP64 system.
     if ! ssh -p$port $user@$machine sudo bash -c "\"ln -f -s $dest_ldso_bin $dest_ldso_link && $dest_lib_path/ldconfig -f $dest_ldsoconf\""; then
	 error "Could not install new sysroot"
	 return 1
     fi

     # Profiling tests attempt to create files on the target with the same
     # paths as on the host.  When local and remote users do not match, we
     # get "permission denied" on accessing /home/$USER/.  Workaround by
     # creating $(pwd) on the target that target user can write to.
     if [ x"$user" != x"$USER" ]; then
	 ssh -p$port $user@$machine sudo bash -c "\"mkdir -p $(pwd) && chown $user $(pwd)\""
     fi

     echo "ABE_TEST_CONTAINER_USER=$user ABE_TEST_CONTAINER_MACHINE=$machine SCHROOT_PORT=$port"
    )
}

# $1 - The component to test
# $2 - If set to anything, installed tools are used'
make_check()
{
#    trace "$*"

    local component=$1
    local builddir="$(get_component_builddir ${component} $2)"

    if [ x"${builddir}" = x"" ]; then
	# Somehow this component hasn't been set up correctly.
	error "Component '${component}' has no builddir defined."
        return 1
    fi

    # Some tests cause problems, so don't run them all unless
    # --enable alltests is specified at runtime.
    local ignore="dejagnu gmp mpc mpfr make eglibc linux gdbserver"
    for i in ${ignore}; do
        if test x"${component}" = x$i -a x"${alltests}" != xyes; then
            return 0
        fi
    done
    notice "Making check in ${builddir}"

    local make_flags=""
    # Use pipes instead of /tmp for temporary files.
    if test x"${override_cflags}" != x -a x"$2" != x"stage2"; then
        make_flags="${make_flags} CFLAGS_FOR_BUILD=\"${override_cflags}\" CXXFLAGS_FOR_BUILD=\"${override_cflags}\""
    else
        make_flags="${make_flags} CFLAGS_FOR_BUILD=\"-pipe\" CXXFLAGS_FOR_BUILD=\"-pipe\""
    fi

    if test x"${override_ldflags}" != x; then
        make_flags="${make_flags} LDFLAGS_FOR_BUILD=\"${override_ldflags}\""
    fi

    local -a runtestflags

    # ??? No idea about the difference (if any?) between $runtest_flags
    # ??? and $component_runtestflags.  Both seem to be empty all the time.
    if [ x"$runtest_flags" != x"" ]; then
        runtestflags+=("$runtest_flags")
    fi
    local component_runtestflags
    component_runtestflags=$(get_component_runtestflags $component)
    if [ x"$component_runtestflags" != x"" ]; then
	runtestflags+=("$component_runtestflags")
    fi
    if [ "$extra_runtestflags" != x"" ]; then
	runtestflags+=("$extra_runtestflags")
    fi
    if [ x"${runtestflags[*]}" != x"" ]; then
	make_flags="${make_flags} RUNTESTFLAGS=\"${runtestflags[*]}\""
    fi

    if test x"${parallel}" = x"yes"; then
	case "${target}" in
	    "$build"|*"-elf"*|armeb*) make_flags="${make_flags} -j ${cpus}" ;;
	    # Double parallelization when running tests on remote boards
	    # to avoid host idling when waiting for the board.
	    *) make_flags="${make_flags} -j $((2*${cpus}))" ;;
	esac
    fi

    # load the config file for Linaro build farms
    export DEJAGNU=${topdir}/config/linaro.exp

    # Run tests
    local checklog="${builddir}/check-${component}.log"
    record_artifact "log_check_${component}" "${checklog}"

    local dirs check_targets exec_tests
    dirs="/"
    check_targets="check"
    exec_tests=false
    case "$component" in
	binutils)
	    dirs="/binutils /ld /gas"
	    check_targets="check-DEJAGNU"
	    exec_tests=true
	    ;;
	gcc)
	    exec_tests=true
	    ;;
	gdb)
	    check_targets="check-gdb"
	    exec_tests=true
	    ;;
	glibc)
	    check_targets="check run-built-tests=no"
	    ;;
	newlib)
	    # We need a special case for newlib, to bypass its
	    # multi-do Makefile targets that do not properly
	    # propagate multilib flags. This means that we call
	    # runtest only once for newlib.
	    dirs="/${target}/newlib"
	    check_targets="check-DEJAGNU"
	    ;;
    esac

    local ldso_bin test_flags

    ldso_bin=$(find_dynamic_linker false)
    if [ x"$ldso_bin" != x"" ]; then
	# If we have ld.so, then we should have a sysroot for testing.
	# If we don't have ld.so, then we are testing native GCC against
	# system libraries.
	test_flags="$test_flags --sysroot=$sysroots/libc"
    fi

    local schroot_make_opts
    if $exec_tests && [ x"$test_container" != x"" ]; then
	schroot_make_opts=$(print_make_opts_and_copy_sysroot "$test_container")
	if [ $? -ne 0 ]; then
	    error "Cannot initialize sysroot on $test_container"
	    return 1
	fi
    elif [ x"${build}" = x"${target}" ]; then
	schroot_make_opts="ABE_TEST_CONTAINER=local"
	if [ x"$ldso_bin" != x"" ]; then
	    local lib_path
	    lib_path=$(dirname "$ldso_bin")
	    # For testing on the local machine we need to link tests against
	    # ldso and libraries in $sysroots/libc
	    test_flags="$test_flags -Wl,-dynamic-linker=$ldso_bin"
	    test_flags="$test_flags -Wl,-rpath=$lib_path"
	fi
    fi

    if [ x"$ldso_bin" != x"" ] && $exec_tests; then
        touch ${sysroots}/libc/etc/ld.so.cache
        chmod 700 ${sysroots}/libc/etc/ld.so.cache
    fi

    # Remove existing logs so that rerunning make check results
    # in a clean log.
    if test -e ${checklog}; then
	# This might or might not be called, depending on whether make_clean
	# is called before make_check.  None-the-less it's better to be safe.
	notice "Removing existing check-${component}.log: ${checklog}"
	rm ${checklog}
    fi

    notice "Redirecting output from the testsuite to $checklog"

    local i result=0
    for i in ${dirs}; do
	# Testsuites (I'm looking at you, GDB), can leave stray processes
	# that inherit stdout of below "make check".  Therefore, if we pipe
	# stdout to "tee", then "tee" will wait on output from these
	# processes for forever and ever.  We workaround this by redirecting
	# output to a file that can be "tail -f"'ed, if desired.
	# A proper fix would be to fix dejagnu to not pass parent stdout
	# to testcase processes.
	dryrun "make ${check_targets} FLAGS_UNDER_TEST=\"$test_flags\" PREFIX_UNDER_TEST=\"$prefix/bin/${target}-\" QEMU_CPU_UNDER_TEST=${qemu_cpu} ${schroot_make_opts} ${make_flags} -w -i -k -C ${builddir}$i >> $checklog 2>&1"
        if [ $? != 0 ]; then
	    warning "make ${check_targets} -C ${builddir}$i failed."
	    result=1
	fi
        record_test_results "${component}" $2
    done

    if [ x"$ldso_bin" != x"" ] && $exec_tests; then
        rm -rf ${sysroots}/libc/etc/ld.so.cache
    fi

    if [ $result != 0 ]; then
	error "Making check in ${builddir} failed"
	return 1
    fi

    if test x"${component}" = x"gcc"; then
	# If the user provided send_results_to, send the results
	# via email
	if [ x"$send_results_to" != x ]; then
	    local srcdir="$(get_component_srcdir ${component})"
	    # Hack: Remove single quotes (octal 047) in
	    # TOPLEVEL_CONFIGURE_ARGUMENTS line in config.status,
	    # to avoid confusing test_summary. Quotes are added by
	    # configure when srcdir contains special characters,
	    # including '~' which ABE uses.
	    dryrun "(cd ${builddir} && sed -i -e '/TOPLEVEL_CONFIGURE_ARGUMENTS/ s/\o047//g' config.status)"
	    dryrun "(cd ${builddir} && ${srcdir}/contrib/test_summary -t -m ${send_results_to} | sh)"
	fi
    fi

    return 0
}

make_clean()
{
#    trace "$*"

    local component=$1
    local builddir="$(get_component_builddir ${component} $2)"

    notice "Making clean in ${builddir}"
    dryrun "make clean ${make_flags} -w -C ${builddir}"
    if test $? != "0"; then
        warning "Make clean failed!"
    fi

    return 0
}

make_docs()
{
#    trace "$*"

    local component=$1
    local builddir="$(get_component_builddir ${component} $2)"

    notice "Making docs in ${builddir}"

    case $1 in
        *binutils*)
            # the diststuff target isn't supported by all the subdirectories,
            # so we build both all targets and ignore the error.
            record_artifact "log_makedoc_${component}${2:+-$2}" "${builddir}/makedoc.log"
	    for subdir in bfd gas gold gprof ld
	    do
		# Some configurations want to disable some of the
		# components (eg gold), so ${build}/${subdir} may not
		# exist. Skip them in this case.
		if [ -d ${builddir}/${subdir} ]; then
		    dryrun "make SHELL=${bash_shell} ${make_flags} -w -C ${builddir}/${subdir} diststuff install-man 2>&1 | tee -a ${builddir}/makedoc.log"
		    if test $? -ne 0; then
			error "make docs failed in ${subdir}"
			return 1;
		    fi
		fi
	    done
            dryrun "make SHELL=${bash_shell} ${make_flags} -w -C ${builddir} install-html install-info 2>&1 | tee -a ${builddir}/makedoc.log"
	    if test $? -ne 0; then
		error "make docs failed"
		return 1;
	    fi
            return 0
            ;;
        *gdbserver)
            return 0
            ;;
        *gdb)
	    record_artifact "log_makedoc_${component}${2:+-$2}" "${builddir}/makedoc.log"
            dryrun "make SHELL=${bash_shell} ${make_flags} -w -C ${builddir}/gdb diststuff install-html install-info 2>&1 | tee -a ${builddir}/makedoc.log"
            dryrun "make SHELL=${bash_shell} ${make_flags} -w -C ${builddir}/gdb/doc install-man 2>&1 | tee -a ${builddir}/makedoc.log"
            return $?
            ;;
        *gcc*)
	    record_artifact "log_makedoc_${component}${2:+-$2}" "${builddir}/makedoc.log"
            dryrun "make SHELL=${bash_shell} ${make_flags} -w -C ${builddir} install-html install-info 2>&1 | tee -a ${builddir}/makedoc.log"
            return $?
            ;;
        *linux*|*dejagnu*|*gmp*|*mpc*|*mpfr*|*newlib*|*make*)
            # the regular make install handles all the docs.
            ;;
        glibc|eglibc)
	    record_artifact "log_makedoc_${component}${2:+-$2}" "${builddir}/makedoc.log"
            dryrun "make SHELL=${bash_shell} ${make_flags} -w -C ${builddir} info html 2>&1 | tee -a ${builddir}/makedoc.log"
            return $?
            ;;
	qemu)
	    return 0
	    ;;
        *)
	    record_artifact "log_makedoc_${component}${2:+-$2}" "${builddir}/makedoc.log"
            dryrun "make SHELL=${bash_shell} ${make_flags} -w -C ${builddir} info man 2>&1 | tee -a ${builddir}/makedoc.log"
            return $?
            ;;
    esac

    return 0
}

# See if we can link a simple executable
hello_world()
{
#    trace "$*"

    if test ! -e /tmp/hello.cpp; then
    # Create the usual Hello World! test case
    cat <<EOF > /tmp/hello.cpp
#include <iostream>
int
main(int argc, char *argv[])
{
    std::cout << "Hello World!" << std::endl; 
}
EOF
    fi

    # Make sure we have C flags we need to link successfully
    local extra_cflags=
    case "${clibrary}/${target}/${multilib}" in
        newlib/arm*/rmprofile)
          extra_cflags="-mcpu=cortex-m3 --specs=rdimon.specs"
          ;;
        newlib/arm*/aprofile)
          extra_cflags="-mcpu=cortex-a8"
          ;;
        newlib/aarch64*)
          extra_cflags="--specs=rdimon.specs"
          ;;
        newlib/*)
          notice "Hello world test not supported for newlib on ${target}"
          return 0
          ;;
    esac

    # See if a test case compiles to a fully linked executable.
    if [ x"$build" = x"$host" ]; then
        dryrun "$prefix/bin/${target}-g++ ${extra_cflags} -o /tmp/hi /tmp/hello.cpp"
        if test -e /tmp/hi; then
            rm -f /tmp/hi
        else
            return 1
        fi
    fi

    return 0
}

# Copy compiler libraries to sysroot
copy_gcc_libs_to_sysroot()
{
    local ldso_must_exist=true
    local libgcc
    local ldso
    local gcc_lib_path
    local sysroot_lib_dir

    if [ x"$clibrary" = x"newlib" ]; then
	# Newlib is normally used for bare-metal builds, so no ld.so expected.
	# Still, one could use newlib for linux builds
	ldso_must_exist=false
    fi

    ldso=$(find_dynamic_linker $ldso_must_exist)

    if [ x"$ldso" != x"" ]; then
	libgcc="libgcc_s.so"
    elif $ldso_must_exist; then
	return 1
    else
	libgcc="libgcc.a"
    fi

    # Make sure the compiler built before trying to use it
    if test ! -e $prefix/bin/${target}-gcc; then
	error "${target}-gcc doesn't exist!"
	return 1
    fi
    libgcc="$($prefix/bin/${target}-gcc -print-file-name=${libgcc})"
    if [ x"$libgcc" = x"libgcc_s.so" -o x"$libgcc" = x"libgcc.a" ]; then
	error "Cannot find libgcc: $libgcc"
	return 1
    fi
    gcc_lib_path="$(dirname "${libgcc}")"
    if [ x"$ldso" != x"" ]; then
	sysroot_lib_dir="$(dirname ${ldso})"
    else
	sysroot_lib_dir="${sysroots}/lib"
    fi

    rsync -a ${gcc_lib_path}/ ${sysroot_lib_dir}/
}

# helper function for record_test_results(). Records .sum files as artifacts
# for components which use dejagnu for testing.
record_sum_files()
{
    local component=$1
    local builddir="$(get_component_builddir ${component} $2)"

    local findargs=
    case "${component}" in
       gdb)
           # skip partial .sum files in gdb results
           findargs="-name *.sum -not -path */gdb/testsuite/outputs/*"
           ;;
       *)
           findargs="-name *.sum"
           ;;
    esac
         

    local time=$SECONDS
    # files/directories could have any weird chars in, so take care to
    # escape them correctly
    local i
    for i in $(find "${builddir}" ${findargs} -exec bash -c 'printf "$@"' bash '%q\n' {} ';' ); do
	record_artifact "dj_sum_${component}${2:+-$2}" "${i}"
    done
    notice "Finding artifacts took $((SECONDS-time)) seconds"
}

# record_test_results() is used to record the artifacts generated by
# make check.
record_test_results()
{
    local component=$1
    local subcomponent=$2

    # no point in incurring the cost of $(find) if we don't need the
    # results.
    if [ "${list_artifacts:+set}" != "set" -o x"${dryrun}" = xyes ]; then
        notice "Skipping search for test results."
        return 0
    fi

    case "${component}" in
        binutils|gcc|gdb|newlib)
            # components which use dejagnu for testing, and generate .sum
            # files during make check. It is assumed that the location of .log
            # files can be derived by the consumer of the artifacts list.
            record_sum_files "${component}" ${subcomponent}
            ;;
        *)
            # this component doesn't have test results (yet?)
            return 0
            ;;
    esac
    return 0
}
