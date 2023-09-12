#!/bin/bash
##############################################
# This script will publish repos that have been sync'ed
#
# Authored by: Travis Sidelinger
# Version History
#  - 2022-02-06 - Initial release
#  - 2022-02-15 - Improved showhelp
#  - 2022-02-17 - Added examples
#
##############################################

## Variables ##

# Import global variables
. "/pkgrepo/etc/yum-repo.conf"

VERBOSE=0
DATE=`date +%Y%m%d`
TIME=`date +%H%M%S`
DNFBIN='/usr/bin/dnf'
DNF_OPT=''
DNF_OPTS='--norepopath --newest-only --downloadcomps --gpgcheck --download-metadata'
DRYRUN=0
REPOMATCH='.'
LOGFILE="${LOGDIR}/publish-${DATE}-${TIME}.log"
CREATEREPOOPTS='--database --workers 2'
LATEST=1
FULL=0

## Functions ##

showhelp()
{
    echo "This script will publish repos that have been sync'ed"
    echo "  Repo is short for repository"
    echo "  Distro is short for a distribution or a collection of repos"
    echo ""
    echo "Usage: ${0} <distro> <distro> <distro>"
    echo "Options:"
    echo "  --help                Show help"
    echo "  -v --verbose          Show more details"
    echo "  --debug               Enable debugging"
    echo "  --repomatch <repo>    Patternmatch repo names"
    echo "  --dryrun              Dryrun"
    echo "  --date YYYYMMDD       Date"
    echo "  --latest              Use the latest sync(s)"
    echo "  --full                Do a full update"
    echo ""
    echo "Examples:"
    echo "  Normal usage:    ${0} -v"
    echo "  Target distro:   ${0} -v ${DISTROLIST[0]} ${DISTROLIST[1]}"
    echo "  Full createrepo: ${0} -v --full <distro>"
    echo "  Date mode:       ${0} -v --date 20220216 ol7"
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
     '--debug')        set -vx;                shift 1;;
     '--repomatch')    REPOMATCH="${2}";       shift 2;;
     '--dryrun')       DRYRUN=1;               shift 1;;
     '--date')         LATEST=0; DATE="${2}";  shift 2;;
     '--latest')       LATEST=1;               shift 1;;
     '--full')         FULL=1;                 shift 1;;
     *)                DISTROS+=( "${1}" );    shift 1;;
   esac
done

# No distro's provided
if [ "${#DISTROS}" -eq 0 ];
then
    # Get distro from current distro directories
    cd "${REPOSDIR}"
    for DIR in `ls -1`;
    do
        DISTROS+=( "${DIR}" );
    done
fi

## Main ##

if [ ${VERBOSE} -gt 0 ]; then echo "Publishing the following distros: ${DISTROS[@]}"; fi

# Loop through each distro
for DISTRO in "${DISTROS[@]}"
do
    if [ ${VERBOSE} -gt 0 ]; then echo "Processing distro: ${DISTRO}"; fi

    # Are we doing lastest mode or date mode?
    if [ ${LATEST} -eq 1 ]
    then
        mkdir -p "${REPOSDIR}/${DISTRO}/sync"
        cd "${REPOSDIR}/${DISTRO}/sync"
        DATE=`ls -1 | grep -E "^[0-9]*$" | tail -1`
    fi

    # Make sure the DATE sync exists
    if [ ! -d "${REPOSDIR}/${DISTRO}/sync/${DATE}" ]
    then
        echo "Skipping sync does not exist: ${REPOSDIR}/${DISTRO}/sync/${DATE}"
    else
        cd "${REPOSDIR}/${DISTRO}/sync/${DATE}"

        # Loop through each repo
        for REPO in `ls -1`
        do
            if [ "`echo ${REPO} | grep ${REPOMATCH}`" ]
            then
                if [ ${VERBOSE} -gt 0 ]; then echo "Processing distro/repo: ${DISTRO}/${REPO}"; fi
                SYNCDIR="${REPOSDIR}/${DISTRO}/sync/${DATE}/${REPO}"
                PUBDIR="${REPOSDIR}/${DISTRO}/pub/${REPO}"
                mkdir -p "${PUBDIR}"

                # Do the publish
                if [ ${VERBOSE} -gt 1 ];
                then
                    if [ $DRYRUN -eq 1 ];
                    then
                        echo "Dryrun: cp -Rl --no-clobber --verbose ${SYNCDIR}/. ${PUBDIR}/"
                    else
                        cp -Rl --no-clobber --verbose "${SYNCDIR}"/. "${PUBDIR}/"
                    fi
                else
                    if [ $DRYRUN -eq 1 ];
                    then
                        echo "Dryrun: cp -Rl --no-clobber --verbose ${SYNCDIR}/. ${PUBDIR}/"
                    else
                        cp -Rl --no-clobber "${SYNCDIR}"/. "${PUBDIR}/"
                    fi
                fi

                # Do the createrepo
                cd "${PUBDIR}"
                if [ ${VERBOSE} -gt 0 ]; then echo "Createrepo on: ${PUBDIR}"; fi
                if [ ${VERBOSE} -gt 1 ]; then CREATEREPOOPTS="${CREATEREPOOPTS} --verbose"
                else CREATEREPOOPTS="${CREATEREPOOPTS} --quiet"
                fi


                if [ ${FULL} -eq 1 ]
                then
                    ${CREATEREPOBIN} ${CREATEREPOOPTS} .
                else
                    ${CREATEREPOBIN} ${CREATEREPOOPTS} --update .
                fi

                # Make sure repo files are not writable
                find "${REPOSDIR}/${DISTRO}/pub/${REPO}" -type f -exec chmod 444 {} \;
                # Make sure directories are excessable
                find "${REPOSDIR}/${DISTRO}/pub/${REPO}" -type d -exec chmod 755 {} \;
            else
                if [ ${VERBOSE} -gt 0 ]; then echo "Skipping distro/repo: ${DISTRO}/${REPO}"; fi
            fi
        done
    fi
done

## End ##

exit

