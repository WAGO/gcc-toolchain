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

#
# This does a checkout from a source code repository
#

# It's optional to use git-bzr-ng or git-svn to work on the remote sources,
# but we also want to work with the native source code control system.
usegit=no

# This is similar to make_all except it _just_ gathers sources trees and does
# nothing else.
checkout_all()
{
#    trace "$*"

    local packages="$*"

    notice "checkout_all called for packages: ${packages}"

    for i in ${packages}; do
	local package=$i
	if test x"$i" = x"libc"; then
	    package="${clibrary}"
	fi
	if test x"${package}" = x"stage1" -o x"${package}" = x"stage2"; then
	    package="gcc"
	fi

	local filespec="$(get_component_filespec ${package})"
	# don't skip mingw_only components so we get md5sums and/or
        # git revisions
	if test "$(component_is_tar ${package})" = no; then
 	    local checkout_ret=
	    checkout ${package}
	    checkout_ret=$?
	    if test ${checkout_ret} -gt 0; then
		error "Failed checkout out of ${package}."
		return 1
	    fi
	else
	    extract ${package}
	    if test $? -gt 0; then
		error "Couldn't extract tarball for ${package}"
		return 1
	    fi
	fi

    done

    notice "Checkout all took ${SECONDS} seconds"

    # Set this to no, since all the sources are now checked out
    supdate=no

    return 0
}

# merge changes from remote repo
update_checkout_branch()
{
    local component="$1"
    local srcdir=
    srcdir="$(get_component_srcdir ${component})" || return 1
    local branch=
    branch="$(get_component_branch ${component})" || return 1

    notice "Updating sources for ${component} in ${srcdir} on ${branch}"

    dryrun "git -C ${srcdir} merge --ff-only origin/${branch}"
    if test $? -gt 0; then
        error "Can't merge changes from ${branch}"
        return 1
    fi
}

# make sure the tag checkout is up to date
update_checkout_tag()
{
    local component="$1"
    local srcdir=
    srcdir="$(get_component_srcdir ${component})" || return 1
    local branch=
    branch="$(get_component_branch ${component})" || return 1

    local currev="$(git -C ${srcdir} rev-parse HEAD)"
    local tagrev="$(git -C ${srcdir} rev-parse ${branch})"
    if test x${currev} != x${tagrev}; then
	dryrun "git -C ${srcdir} stash && git -C ${srcdir} reset --hard ${branch}"
        if test $? -gt 0; then
	    error "Can't reset to ${branch}"
	    return 1
        fi
    fi
    return 0
}
# This gets the source tree from a remote host
# $1 - This should be a service:// qualified URL.  If you just
#       have a git identifier call get_URL first.
checkout()
{
#    trace "$*"

    local component="$1"

    # None of the following should be able to fail with the code as it is
    # written today (and failures are therefore untestable) but propagate
    # errors anyway, in case that situation changes.
    local url=
    url="$(get_component_url ${component})" || return 1
    local branch=
    branch="$(get_component_branch ${component})" || return 1
    local revision=
    revision="$(get_component_revision ${component})" || return 1
    local srcdir=
    srcdir="$(get_component_srcdir ${component})" || return 1
    local repo=
    repo="$(get_component_filespec ${component})" || return 1
    local protocol="$(echo ${url} | cut -d ':' -f 1)"
    local repodir="${url}/${repo}"
    local new_srcdir=false

    # gdbserver is already checked out in the GDB source tree.
    if test x"${component}" = x"gdbserver"; then
	local gdbrevision="$(get_component_revision gdb)"
        if [ x"${gdbrevision}" = x"" ]; then
            error "no gdb revision found"
            return 1
        fi
	set_component_revision gdbserver ${gdbrevision}
        return 0
    fi

    if ! validate_url "${repodir}"; then
	error "proper URL required"
	return 1
    fi

    case ${protocol} in
	git*|http*|ssh*)
	    if test ! -d ${srcdir}; then
		# By definition a git commit resides on a branch.  Therefore
		# specifying a branch AND a commit is redundant and potentially
		# contradictory.  For this reason we only consider the commit
		# if both are present.
		if test x"${revision}" != x""; then
		    notice "Checking out revision ${revision} for ${component} in ${srcdir}"
		    dryrun "${NEWWORKDIR} ${local_snapshots}/${repo} ${srcdir} ${revision}"
		    if test $? -gt 0; then
			error "Failed to create workdir for ${revision}"
			return 1
		    fi
	        else
		    notice "Checking out branch ${branch} for ${component} in ${srcdir}"
		    dryrun "${NEWWORKDIR} ${local_snapshots}/${repo} ${srcdir} ${branch}"
		    if test $? -gt 0; then
			error "Failed to create workdir for ${branch}"
			return 1
		    fi
		    # If the user mistakenly used ~revision instead of
		    # @revision, exit with an error, to avoid branch
		    # update failures on subsequent runs.
		    # ~revision can also point to a tag.
		    if test x"${dryrun}" != xyes; then
			if test $(git -C ${srcdir} reflog ${branch} | wc -l) -eq 0 -a \
			        $(git -C ${srcdir} tag -l ${branch} | wc -l) -eq 0; then
			    error "${branch} is not a branch or tag, use @{revision} to specify a revision"
			    return 1
			fi
		    fi
		fi
		new_srcdir=true
	    elif test x"${supdate}" = xyes; then
		# if we're building a particular revision, then make sure it
		# is checked out.
                if test x"${revision}" != x""; then
		    notice "Building explicit revision for ${component}."
		    # No need to pull.  A commit is a single moment in time
		    # and doesn't change.
		    dryrun "git -C ${srcdir} checkout ${revision}"
		    if test $? -gt 0; then
			error "Can't checkout ${revision}"
			return 1
		    fi
		elif git -C ${srcdir} rev-parse -q --verify refs/tags/${branch}; then
		    notice "Found tag ${branch}, updating in case tag has moved."
		    update_checkout_tag "${component}"
		    if test $? -gt 0; then
			error "Error during update_checkout_tag."
			return 1
		    fi
		else
		    # Some packages allow the build to modify the source
		    # directory and that might screw up abe's state so we
		    # restore a pristine branch.
		    if test x"${branch}" = x; then
			error "No branch name specified!"
			return 1
		    fi
		    update_checkout_branch ${component}
		    if test $? -gt 0; then
			error "Error during update_checkout_branch."
			return 1
		    fi
		fi
		new_srcdir=true
	    fi

	    if test x"${dryrun}" != xyes; then
		local newrev="$(git -C ${srcdir} log --format=format:%H -n 1)"
	    else
		local newrev="unknown/dryrun"
	    fi
	    set_component_revision ${component} ${newrev}
	    ;;
	*)
	    error "proper URL required"
	    return 1
	    ;;
    esac

    if $new_srcdir; then
	case "${component}" in
	    gcc)
		# Touch GCC's auto-generated files to avoid non-deterministic
		# build behavior.
		dryrun "(cd ${srcdir} && ./contrib/gcc_update --touch)"
		# LAST_UPDATED and gcc/REVISION are used when sending
		# results summaries
		# Report svn revision, if present
		local svnrev="$(git -C ${srcdir} log -n 1 | grep git-svn-id: | awk '{print $2;}' | cut -d@ -f2)"
		local revstring="${newrev}"
		[ x"${svnrev}" != x ] && revstring="${svnrev}"
		dryrun "echo $(TZ=UTC date) '(revision' ${revstring}')' | tee ${srcdir}/LAST_UPDATED"
		dryrun "echo \[${branch} revision ${revstring}\] | tee ${srcdir}/gcc/REVISION"

		if test x"${gcc_patch_file}" != x""; then
		    dryrun "git -C ${srcdir} apply --check ${gcc_patch_file}"
		    if test $? != 0; then
			error "Patch ${gcc_patch_file} does not apply."
			return 1
		    fi
		    git -C ${srcdir} apply ${gcc_patch_file}
		fi
		;;
	    *)
		# Avoid rebuilding of auto-generated C files. Rather than
		# try to determine which are auto-generated, touch all of them.
		# If a C file is not autogenerated, it does no harm to update
		# its timestamp.
		dryrun "cd ${srcdir} && git ls-files -z '*.c' | xargs -0 touch"
	esac
    fi

    # Show the most recent commit, useful when debugging (to check
    # that what we are building actually contains what we expect).
    dryrun "git --no-pager -C ${srcdir} show -s"

    return 0
}
