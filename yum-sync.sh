#!/bin/bash
##############################################
# This script will sync repos for a target distro
#
# Authored by: Travis Sidelinger
# Version History
#  - 2022-02-04 - Initial release
#  - 2022-02-05 - Working out the bugs, adding features
#  - 2022-02-06 - Improved verbose and reporting output
#  - 2022-02-15 - Improved showhelp, dnf options fixes, fixed deleting duplicates
#  - 2022-02-17 - Added date override
#
##############################################

## Variables ##

# Import global variables
. "/pkgrepo/etc/yum-repo.conf"

VERBOSE=0
DATE=`date +%Y%m%d`
TIME=`date +%H%M%S`
DNFBIN='/usr/bin/dnf'
DNFOPTS="--downloadcomps --download-metadata --disableplugin=generate_completion_cache --noautoremove --config=${CONFIGDIR}/dnf.conf --setopt=reposdir=${DNFCONFDIR} --norepopath"
SHOWONLY=0
REPOMATCH='.'
LOGFILE="${LOGDIR}/sync-${DATE}-${TIME}.log"
NEWESTONLY=1

## Functions ##

showhelp()
{
    echo "This script will sync repos for a target distro"
    echo "  Repo is short for repository"
    echo "  Distro is short for a distribution or a collection of repos"
    echo ""
    echo "Usage: ${0} <distro> <distro> <distro>"
    echo "Options:"
    echo "  --help                Show help"
    echo "  -v --verbose          Show more details"
    echo "  --debug               Enable debugging"
    echo "  --repomatch <repo>    Patternmatch repo names"
    echo "  --show-only           Dryrun"
    echo "  --full                Do a full update"
    echo "  --newest              Newest only (default)"
    echo "  --date YYYYMMDD       Override the date"
    echo ""
    echo "Examples:"
    echo "  Normal usage:  ${0} -v"
    echo "  Target distro: ${0} -v ${DISTROLIST[0]} ${DISTROLIST[1]}"
    echo "  New repo:      ${0} -v --full <distro>"
    echo "  Date mode:     ${0} -v --date 20220216 ol7"

    echo ""
    echo "Available distros: ${DISTROLIST[@]}"
    }

## Input ##

while (( $# ))
do
   case "${1}" in
     '--help')         showhelp;               shift 1; exit ;;
     '-v'|'--verbose') VERBOSE=$((VERBOSE+1)); shift 1;;
     '-vv')            VERBOSE=$((VERBOSE+2)); shift 1;;
     '-vvv')           VERBOSE=$((VERBOSE+3)); shift 1;;
     '--debug')        set -vx;                shift 1;;
     '--repomatch')    REPOMATCH="${2}";       shift 2;;
     '--show-only')    SHOWONLY=1;             shift 1;;
     '--full')         NEWESTONLY=0;           shift 1;;
     '--date')         DATE=${2};              shift 2;;
     *)                DISTROS+=( "${1}" );    shift 1;;
   esac
done

# No distro's provided
if [ "${#DISTROS}" -eq 0 ]; then DISTROS=( "${DISTROLIST[@]}" ); fi

# Showonly
if [ ${SHOWONLY} -eq 1 ]; then DNFOPTS="${DNFOPTS} --urls"; fi

# Newest Only
if [ ${NEWESTONLY} -eq 1 ]; then DNFOPTS="${DNFOPTS} --newest-only"; fi

## Main ##

if [ ${VERBOSE} -gt 0 ]; then echo "Downloading the following distros: ${DISTROS[@]}"; fi

# Loop through each distro
for DISTRO in "${DISTROS[@]}"
do
    if [ ${VERBOSE} -gt 0 ]; then echo "Processing distro: ${DISTRO}"; fi
    # Get the list of repos
    REPOS=()   # blank the arrary
    for REPO in `${BINDIR}/read-yum-config.py "${DNFCONFDIR}/${DISTRO}.repo" enabled 1 | grep ${REPOMATCH}`; do REPOS+=( "${REPO}" ); done

    # Loop through each repo
    for REPO in "${REPOS[@]}"
    do
        if [ ${VERBOSE} -gt 0 ]; then echo "Processing distro/repo: ${DISTRO}/${REPO}"; fi
        SYNCDIR="${REPOSDIR}/${DISTRO}/sync/${DATE}/${REPO}"
        mkdir -p "${SYNCDIR}"

        if [ -d "${REPOSDIR}/${DISTRO}/pub/{$REPO}" ];
        then
            # Make sure repo files are not writable
            find "${REPOSDIR}/${DISTRO}/pub/{$REPO}" -type f -exec chmod 444 {} \;

            # link the current repo to the sync directory to prevent duplicate downloads
            cp -Rl "${REPOSDIR}/${DISTRO}/pub/{$REPO}" "${SYNCDIR}"
        fi

        # Do the reposync
        #export TMP="${TEMPDIR}"
        if [ ${VERBOSE} -lt 2 ]
        then
            ${DNFBIN} reposync -p "${SYNCDIR}" ${DNFOPTS} --repo ${REPO} > ${LOGFILE}
        elif [ ${VERBOSE} -eq 2 ]
        then
            ${DNFBIN} --verbose reposync -p "${SYNCDIR}" ${DNFOPTS} --repo ${REPO} 2>&1 | tee ${LOGFILE} | grep -Ev '(SKIPPED)|(listed more than once in the configuration)'
        elif [ ${VERBOSE} -gt 2 ]
        then
            ${DNFBIN} --verbose reposync -p "${SYNCDIR}" ${DNFOPTS} --repo ${REPO}
        fi

        # Remove all duplicate files, what remains should be the files we downloaded
        find "${SYNCDIR}" -type f -links +1 -delete
    done
done

## End ##

exit
