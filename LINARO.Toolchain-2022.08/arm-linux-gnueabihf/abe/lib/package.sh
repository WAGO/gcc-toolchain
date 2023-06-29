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

# This script contains functions for building binary packages.

build_deb()
{
#    trace "$*"

    warning "unimplemented"
}

# This removes files that don't go into a release, primarily stuff left
# over from development.
#
# $1 - the top level path to files to cleanup for a source release
sanitize()
{
#    trace "$*"

    # the files left from random file editors we don't want.
    local edits="$(find $1/ -name \*~ -o -name \.\#\* -o -name \*.bak -o -name x)"

    pushd ./ >/dev/null
    cd $1
    if test "$(git status | grep -c "nothing to commit, working directory clean")" -gt 0; then
	error "uncommitted files in $1! Commit files before releasing."
	#return 1
    fi
    popd >/dev/null

    if test x"${edits}" != x; then
	rm -fr ${edits}
    fi

    return 0
}

# Strip HOST binaries present inside a given DIRECTORY.
# Stripping policy is taken from Debian helpers (dh_strip).
#
# $1 = HOST
# $2 = DIRECTORY
# TODO: Handle mingw binaries.
strip_dir()
{
#    trace "$*"

    local destdir="$2"

    case "$1" in
	x86_64*)
	    local host="x86-64" ;;
	i686*)
	    local host="80386" ;;
	*)  note "Stripping host $1 is not supported."
	    return 1 ;;
    esac

    while read file ; do
	local file_type="$(file "$file")"
	local opts="--remove-section=.comment --remove-section=.note"
	case "$file_type" in
	    *\ ar\ archive)
		if readelf -h "$file" | grep Machine | grep -iq "$host" ; then
		    opts="$opts --strip-debug --enable-deterministic-archives "
		    dryrun "strip ${opts} ${file}"
		fi ;;
	    # Since file output contains BuildID sha1, checking for " $host,"
	    # to avoid the cases where this sha1 contains 80386 string!
	    *shared\ object*\ $host,*)
		opts="$opts --strip-unneeded "
		dryrun "strip ${opts} ${file}" ;;
	    *\ $host,*)
		dryrun "strip ${opts} ${file}" ;;
	esac
     done < <(find "$destdir" -type f)
}

# Try to use faster compression and fall-back to normal when can't.
tar_Jcf () {
    (
    set -euf -o pipefail

    if ! tar -I pxz -cf "$@" > /dev/null 2>&1; then
	# PXZ can [rarely] fail due to high RAM usage, so fallback to normal XZ.
	tar -caf "$@"
    fi
    )
}

# The runtime libraries are produced during dynamic builds of gcc, libgcc,
# listdc++, and gfortran.
binary_runtime()
{
#    trace "$*"

    local rtag="$(create_release_tag gcc)"
    local tag="runtime-${rtag}-${target}"

    local destdir="${local_builds}/tmp.$$/${tag}"

    dryrun "mkdir -p ${destdir}/lib/${target} ${destdir}/usr/lib/${target}"

    # Get the binary libraries.
    if test x"${build}" != x"${target}"; then
	dryrun "rsync -av $prefix/${target}/lib*/libgcc* ${destdir}/lib/${target}/"
	dryrun "rsync -av $prefix/${target}/lib*/libstdc++* ${destdir}/usr/lib/${target}/"
    else
	dryrun "rsync -av $prefix/lib*/libgcc* ${destdir}/lib/${target}/"
	dryrun "rsync -av $prefix/lib*/libstdc++* ${destdir}/usr/lib/${target}/"
    fi

    # make the tarball from the tree we just created.
    notice "Making binary tarball for runtime libraries, please wait..."
    local tarball=${local_snapshots}/${tag}.tar.xz
    dryrun "tar_Jcf ${tarball} --directory ${local_builds}/tmp.$$ ${tag}"
    record_artifact runtime "${tarball}"

    rm -f ${local_snapshots}/${tag}.tar.xz.asc
    dryrun "md5sum ${local_snapshots}/${tag}.tar.xz | sed -e 's:${local_snapshots}/::' > ${tarball}.asc"
    record_artifact runtime_asc "${tarball}.asc"

    rm -fr ${local_builds}/tmp.$$

    return 0
}

binary_gdb()
{
#    trace "$*"

    local version="$(${target}-gdb --version | head -1 | grep -o " [0-9\.][0-9].*\." | tr -d ')')"
    local tag="$(create_release_tag ${gdb_version} | sed -e 's:binutils-::')"
    local builddir="$(get_component_builddir gdb gdb)"
    local destdir="${local_builds}/tmp.$$/${tag}-tmp"

    rm ${builddir}/gdb/gdb

    local make_flags="${make_flags}"
    # install in alternate directory so it's easier to build the tarball
    dryrun "make all ${make_flags} DESTDIR=${destdir} -w -C ${builddir}"
    dryrun "make install ${make_flags} DESTDIR=${destdir} -w -C ${builddir}"
    # ??? This expands to ...
    # ln -sfnT ${local_builds}/tmp.$$/${tag}-tmp/$prefix
    #         /${local_builds}/tmp.$$/${tag}
    # ??? WHY?
    dryrun "ln -sfnT ${destdir}/${prefix} /${local_builds}/tmp.$$/${tag}"

    local abbrev="$(echo ${host}_${target} | sed -e 's:none-::' -e 's:unknown-::')"
 
   # make the tarball from the tree we just created.
    notice "Making binary tarball for GDB, please wait..."
    dryrun "tar_Jcf ${local_snapshots}/${tag}-${abbrev}.tar.xz -h --directory=${local_builds}/tmp.$$ ${tag}"

    rm -f ${local_snapshots}/${tag}.tar.xz.asc
    dryrun "md5sum ${local_snapshots}/${tag}-${abbrev}.tar.xz | sed -e 's:${local_snapshots}/::' > ${local_snapshots}/${tag}-${abbrev}.tar.xz.asc"

    return 0    
}

# Produce a binary toolchain tarball
# For daily builds produced by Jenkins, we use
# $(date --date="@${timestamp}" +%Y%m%d)-${BUILD_NUMBER}-${GIT_REVISION}
# e.g artifact_20130906-12-245f0869.tar.xz
binary_toolchain()
{
#    trace "$*"

    local rtag="$(create_release_tag gcc)"
    local symlinks=

    if test x"${host}" != x"${build}"; then
	local tag="${rtag}-i686-mingw32_${target}"
    else
	local tag="${rtag}-${build_arch}_${target}"
    fi

    local destdir="${local_builds}/tmp.$$/${tag}"
    dryrun "mkdir -p ${destdir}"

    # Some mingw packages have a runtime dependency on
    # libwinpthread-1.dll, so a copy is put in bin so executables will
    # work.
    # Another copy is needed in gcc's libexec for cc1.exe to work
    if is_host_mingw; then
	for dest in $prefix/bin/ $prefix/libexec/gcc/${target}/*/
	do
	    dryrun "cp /usr/${host}/lib/libwinpthread-1.dll ${dest}"
	    if test $? -gt 0; then
		error "libwinpthread-1.dll not found, win32 executables won't run without it."
		return 1
	    fi
	done
	# Windows does not support symlinks, and extractors do not
	# always handle them correctly: dereference them to avoid
	# problems.
	symlinks=L
    fi

    # The manifest file records the versions of all of the components used to
    # build toolchain.
    dryrun "cp ${manifest} $prefix/"
    dryrun "rsync -av${symlinks} $prefix/* ${destdir}/"

    # Strip host binaries when packaging releases.
    if test x"${release}" != x; then
	notice "Stripping host tools."
	if test x"${target}" != x"${build}" && ! is_host_mingw; then
	    strip_dir "$host" "$destdir"
	fi
    fi

    # Remove libtool *.la files
    notice "Removing .la files."
    find ${destdir} -name '*.la' -exec rm '{}' ';'



    # make the tarball from the tree we just created.
    notice "Making binary tarball for toolchain, please wait..."
    local tarball=${local_snapshots}/${tag}.tar.xz
    dryrun "tar_Jcf ${tarball} --directory=${local_builds}/tmp.$$ ${exclude} ${tag}"
    record_artifact toolchain "${tarball}"
	
    rm -f ${local_snapshots}/${tag}.tar.xz.asc
    dryrun "md5sum ${local_snapshots}/${tag}.tar.xz | sed -e 's:${local_snapshots}/::' > ${tarball}.asc"
    record_artifact toolchain_asc "${tarball}".asc
    
    rm -fr ${local_builds}/tmp.$$

    return 0
}

binary_sysroot()
{
#    trace "$*"

    local rtag="$(create_release_tag ${clibrary})"
    local tag="sysroot-${rtag}-${target}"

    local destdir="${local_builds}/tmp.$$/${tag}"
    dryrun "mkdir -p ${local_builds}/tmp.$$"
    dryrun "ln -sfnT ${sysroots} ${destdir}"

    local tarball=${local_snapshots}/${tag}.tar.xz

    notice "Making binary tarball for sysroot, please wait..."
    dryrun "tar_Jcf ${tarball} -h --directory=${local_builds}/tmp.$$ ${tag}"
    record_artifact sysroot "${tarball}"

    rm -fr ${local_snapshots}/${tag}.tar.xz.asc ${local_builds}/tmp.$$
    dryrun "md5sum ${local_snapshots}/${tag}.tar.xz > ${tarball}.asc"
    record_artifact sysroot_asc "${tarball}".asc

    return 0
}

do_install_sysroot()
{
    # There may be no sysroot to install, depending on which package
    # subset we built.
    if [ ! -d ${sysroots} ]; then
	return 0
    fi

    if is_host_mingw && [ x"${build}" != x"${target}" ]; then
	# Windows does not support symlinks, and extractors do not
	# always handle them correctly: dereference them to avoid
	# problems.
	local res=0
	local tmpdir
	tmpdir=$(mktemp -d)
	dryrun "rsync -aL ${prefix}/${target}/libc/ $tmpdir/"
	res=$(($res|$?))
	dryrun "rsync -aL ${sysroots}/* $tmpdir/"
	res=$(($res|$?))
	dryrun "rsync -a --del $tmpdir/ ${prefix}/${target}/libc/"
	res=$(($res|$?))

	rm -rf "$tmpdir"
        if [ $res -ne 0 ]; then
	    error "copy of sysroot failed"
            return 1
        fi
    fi
}

get_manifest_id()
{
    local file="$1"
    if [ ! -f "$file" ]; then
        error "get_manifest_id called for non-existent manifest"
        return 1;
    fi

    if grep -q 'Everything below this line' "${file}"; then
        error "get_manifest_id only works on partial manifest files during manifest creation."
        return 1;
    fi

    local manifest_id=
    manifest_id=$(
        (
          set -e
          # control the locale to get a fixed sort order below
          export LC_ALL=C
          # extract manifest version
          head -n 1 "${file}"
          # extract ${component}_${field}=value lines, in lexicographic order
          tail -n +2 "${file}" | grep '^[^#][^=]*_[^=]*=' | sort
          # extract ${parameter}=value lines, in lexicographic order
          tail -n +2 "${file}" | grep '^[^#][^=_]*=' | sort
        ) | sha1sum - | awk '{ print $1; }')

    if [ $? -ne 0 ]; then
        error "manifest id calculation failed!"
        return 1
    fi

    echo "$manifest_id"

    return 0
}

# rewrite path so that it is based on ABE path variables
normalize_manifest_path()
{
    sed -e "s:${local_builds}:\$\{local_builds\}:g" -e "s:${sysroots}:\$\{sysroots\}:g" -e "s:${local_snapshots}:\$\{local_snapshots\}:g" -e "s:${host}:\$\{host\}:g"
}

# Create a manifest file that lists all the versions of the other components
# used for this build.
manifest()
{
#    trace "$*"

    # This function relies too heavily on the built toolchain to do anything
    # in dryrun mode.
    if test x"${dryrun}" = xyes; then
	return 0;
    fi

    # Similarly, we need gcc to compute the filename of the manifest
    if ! echo "${build_component_list}" | grep -q stage ; then
	return 0
    fi

    if test x"$1" = x; then
	mtag="$(create_release_tag gcc)"
	mkdir -p ${local_builds}/${host}/${target}
	if is_host_mingw; then
	    local build="win32"
	else
	    local build="linux"
	fi
	local outfile=${local_builds}/${host}/${target}/${mtag}-${build}-manifest.txt
    else
	local outfile=$1
    fi

    if test -e ${outfile}; then
	mv -f ${outfile} ${outfile}.bak
    fi

    record_artifact manifest "${outfile}"

    echo "manifest_format=${manifest_version:-1.0}" > ${outfile}
    echo "" >> ${outfile}
    echo "# Note that for ABE, these parameters are not used" >> ${outfile}

    local seen=0
    local tmpfile="/tmp/mani$$.txt"
    for i in ${toolchain[*]}; do
	local component="$i"
	# ABE build data goes in the documentation section
	if test x"${component}" = x"abe"; then
	    echo "${component}_url=$(get_component_url ${component})" > ${tmpfile}
	    echo "${component}_branch=branch=$(get_component_branch ${component})" >> ${tmpfile}
	    echo "${component}_revision=$(get_component_revision ${component})" >> ${tmpfile}
	    echo "${component}_filespec=$(get_component_filespec ${component})" >> ${tmpfile}
	    local configure="$(get_component_configure ${component} | normalize_manifest_path)"
	    echo "${component}_configure=\"${configure}\"" >> ${tmpfile}
	    echo "" >> ${tmpfile}
	    continue
	fi
	if test ${seen} -eq 1 -a x"${component}" = x"gcc"; then
	    notice "Not writing GCC a second time, already done."
	    continue
	else
	    if test x"${component}" = x"gcc"; then
		local seen=1
	    fi
	fi

	echo "# Component data for ${component}" >> ${outfile}

	local url="$(get_component_url ${component})"
	echo "${component}_url=${url}" >> ${outfile}

	local branch="$(get_component_branch ${component})"
	if test x"${branch}" != x; then
	    echo "${component}_branch=${branch}" >> ${outfile}
	fi

	local revision="$(get_component_revision ${component})"
	if test x"${revision}" != x; then
	    echo "${component}_revision=${revision}" >> ${outfile}
	fi

	local filespec="$(get_component_filespec ${component})"
	if test x"${filespec}" != x; then
	    echo "${component}_filespec=${filespec}" >> ${outfile}
	fi

	local makeflags="$(get_component_makeflags ${component} | normalize_manifest_path )"
	if test x"${makeflags}" != x; then
	    echo "${component}_makeflags=\"${makeflags}\"" >> ${outfile}
	fi

	local md5sum="$(get_component_md5sum ${component})"
	if test x"${md5sum}" != x; then
	    echo "${component}_md5sum=${md5sum}" >> ${outfile}
	fi

	local mingw_only="$(get_component_mingw_only ${component})"
	if test x"${mingw_only}" != x; then
	    echo "${component}_mingw_only=\"${mingw_only}\"" >> ${outfile}
	fi

	local linuxhost_only="$(get_component_linuxhost_only ${component})"
	if test x"${linuxhost_only}" != x; then
	    echo "${component}_linuxhost_only=\"${linuxhost_only}\"" >> ${outfile}
	fi

	# Drop any local build paths and replaced with variables to be more portable.
	if test x"${component}" = x"gcc"; then
	    echo "${component}_configure=" >> ${outfile}
	else
	    local configure="$(get_component_configure ${component} | normalize_manifest_path )"
	    if test x"${configure}" != x; then
		echo "${component}_configure=\"${configure}\"" >> ${outfile}
	    fi
	fi

	local mingw_extraconf="$(get_component_mingw_extraconf ${component} | normalize_manifest_path )"
	if test x"${mingw_extraconf}" != x; then
	    echo "${component}_mingw_extraconf=\"${mingw_extraconf}\"" >> ${outfile}
	fi

	local static="$(get_component_staticlink ${component})"
	case "${component}" in
	    glibc|eglibc) ;;
	    *) echo "${component}_staticlink=\"${static}\"" >> ${outfile} ;;
	esac

	if test x"${component}" = x"gcc"; then
	    local stage1="$(get_component_configure gcc stage1 | normalize_manifest_path )"
	    echo "gcc_stage1_flags=\"${stage1}\"" >> ${outfile}
	    local stage2="$(get_component_configure gcc stage2 | normalize_manifest_path )"
	    echo "gcc_stage2_flags=\"${stage2}\"" >> ${outfile}
	fi

	echo "" >> ${outfile}
    done

    echo "" >> ${outfile}
    echo "clibrary=${clibrary}" >> ${outfile}
    echo "target=${target}" >> ${outfile}

    # generate SHA1 of the manifest
    local manifest_id
    local manifest_id=$(get_manifest_id "${outfile}")
    if [ $? -ne 0 ]; then
        error "Manifest ID calculation failed"
        return 1;
    fi
    echo "manifestid=$manifest_id" >> ${outfile}

    cat >> ${outfile} <<EOF

 ##############################################################################
 # Everything below this line is only for informational purposes for developers
 ##############################################################################

# Build machine data
build: ${build}
host: ${host}
kernel: ${kernel}
hostname: ${hostname}
distribution: ${distribution}
host_gcc: ${host_gcc_version}

# These aren't used in the repeat build. just a sanity check for developers
build directory: ${local_builds}
sysroot directory: ${sysroots}
snapshots directory: ${local_snapshots}
git reference directory: ${git_reference_dir}

EOF

    # Add the section for ABE.
    if test -e ${tmpfile}; then
	cat "${tmpfile}" >> ${outfile}
	rm "${tmpfile}"
    fi

    for i in gcc binutils ${clibrary} abe; do
	if test "$(component_is_tar ${i})" = no; then
	    echo "--------------------- $i ----------------------" >> ${outfile}
	    local srcdir="$(get_component_srcdir $i)"
	    # Invoke in a subshell in order to prevent state-change of the current
	    # working directory after manifest is called.
	    git -C ${srcdir} log -n 1 >> ${outfile}
	    echo "" >> ${outfile}
	fi
    done
 
    if test x"${manifest}" != x; then
	if ! diff --brief ${manifest} ${outfile} > /dev/null; then
	    warning "Manifest files are different!"
	else
	    notice "Manifest files match"
	fi
    fi

    echo ${outfile}

    return 0
}

# Build a source tarball
# $1 - the version to use, usually something like 2013.07-2
binutils_src_tarball()
{
#    trace "$*"

    local version="$(${target}-ld --version | head -1 | cut -d ' ' -f 5 | cut -d '.' -f 1-3)"

    # See if specific component versions were specified at runtime
    if test x"${binutils_version}" = x; then
	local binutils_version="binutils-$(grep ^latest= ${topdir}/config/binutils.conf | cut -d '\"' -f 2)"
    fi

    local srcdir="$(get_component_srcdir ${binutils_version})"
    local branch="$(echo ${binutils_version} | cut -d '/' -f 2)"

    # clean up files that don't go into a release, often left over from development
    if test -d ${srcdir}; then
	sanitize ${srcdir}
    fi

    # from /linaro/snapshots/binutils.git/src-release: do-proto-toplev target
    # Take out texinfo from a few places.
    local dirs="$(find ${srcdir} -name Makefile.in)"
    for d in ${dirs}; do
	sed -i -e '/^all\.normal: /s/\all-texinfo //' -e '/^install-texinfo /d' $d
    done

    # Create .gmo files from .po files.
    for f in $(find . -name '*.po' -type f -print); do
        dryrun "msgfmt -o $(echo $f | sed -e 's/\.po$/.gmo/') $f"
    done
 
    if test x"${release}" != x; then
	local date="$(date --date="@${timestamp}" +%Y%m%d)"
	if test "$(echo $1 | grep -c '@')" -gt 0; then
	    local revision="$(echo $1 | cut -d '@' -f 2)"
	fi
	if test -d ${srcdir}/.git; then
	    local binutils_version="${dir}-${date}"
	    local revision="-$(git -C ${srcdir} log --oneline | head -1 | cut -d ' ' -f 1)"
	    local exclude="--exclude .git"
	else
	    local binutils_version="$(echo ${binutils_version} | sed -e "s:-2.*:-${date}:")"
	fi
	local date="$(date --date="@${timestamp}" +%Y%m%d)"
	local tag="${binutils_version}-linaro${revision}-${date}"
    else
	local tag="binutils-linaro-${version}-${release}"
    fi

    dryrun "ln -s ${srcdir} ${local_builds}/${tag}"

# from /linaro/snapshots/binutils-2.23.2/src-release
#
# NOTE: No double quotes in the below.  It is used within shell script
# as VER="$(VER)"

    if grep 'AM_INIT_AUTOMAKE.*BFD_VERSION' binutils/configure.in >/dev/null 2>&1; then
	sed < bfd/configure.in -n 's/AM_INIT_AUTOMAKE[^,]*, *\([^)]*\))/\1/p';
    elif grep AM_INIT_AUTOMAKE binutils/configure.in >/dev/null 2>&1; then
	sed < binutils/configure.in -n 's/AM_INIT_AUTOMAKE[^,]*, *\([^)]*\))/\1/p';
    elif test -f binutils/version.in; then
	head -1 binutils/version.in;
    elif grep VERSION binutils/Makefile.in > /dev/null 2>&1; then
	sed < binutils/Makefile.in -n 's/^VERSION *= *//p';
    else
	echo VERSION;
    fi

    # Cleanup any temp files.
    #find ${srcdir} -name \*~ -o -name .\#\* -exec rm {} \;

    notice "Making source tarball for GCC, please wait..."
    dryrun "tar_Jcf ${local_snapshots}/${tag}.tar.xz -h ${exclude} --directory=${local_builds}/tmp.$$ ${tag}/)"

    rm -f ${local_snapshots}/${tag}.tar.xz.asc
    dryrun "md5sum ${local_snapshots}/${tag}.tar.xz > ${local_snapshots}/${tag}.tar.xz.asc"
    # We don't need the symbolic link anymore.
    dryrun "rm -f ${local_builds}/tmp.$$"

    return 0
}
