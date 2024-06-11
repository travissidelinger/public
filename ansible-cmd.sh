#!/bin/bash
#################################################
# Run remote commands as root with Ansible
#
# Authored by: Travis Sidelinger
#
# Version History:
#  2022Apr06 - Initial release
#  2022Apr07 - Move module to a variable
#  2022May12 - Added --hosts and --groups options, limited output to stdout from ansible, increased timeout to 600
#  2022Jun30 - Updated verbose mode
#  2023Jun02 - Updated group method to use ansible-inventory --list
#              Updated hosts method to use ansible-inventory --list
#              Added --group mode
#              Added -T timeout
#  2024Apr17 - Added -i option for different inventory files
#
#################################################

## Variables ##

ANSIBLE_USER="ansible"
HOSTSFILE="/home/tsidelinger/ansible/hosts.yml"
MODE='PLAYBOOK'
PLAYBOOK_FILE='main.yml'
MODULE='shell'
CMD=''
WORKERS=30
BECOME=1
ASK_BECOME_PASS=0
ASK_APSS=''
CONNECTION_TIMEOUT=8
BACKGROUND_TIMEOUT=600
POLL=4

## Functions ##
showhelp()
{
    echo "Run remote commands as root with Ansible"
    echo ""
    echo "Usage: ${0} [options] <hostname> <hostname>"
    echo "Options:"
    echo "  --help                 Show help"
    echo "  --verbose              Show more details"
    echo "  --debug                Enable debugging"
    echo "  --user <name>          User account"
    echo "  --passauth             Use password login mode"
    echo "  --keyauth              Use sshkey login mode (default)"
    echo "  --become               Become the root user"
    echo "  --no-become            Do not become the root user"
    echo "  --ask-become-pass      Ask for the become passwrod"
    echo "  --no-ask-become-pass   Do not ask for the become passwrod"
    echo "  -c --command <cmd>     Remote command to run"
    echo "  --list-hosts           Outputs a list of matching hosts; does not execute anything else"
    echo "  --hosts                List all hosts"
    echo "  --group <GROUP>        List group members"
    echo "  --groups               List all groups"
    echo "  --ssh-key-add <GROUP>  Add ssh keys for group"
    echo "  --timeout ##           Command timeout in seconds"
    echo "  -i --inventory <fiile> Path to inventory file"
    echo "  -p --playbook <fiile>  Path to Playbook file"
    echo ""
    echo "Examples:"
    echo "  $0 -c 'uptime' <hostname>"
    echo "  $0 -c 'uptime' <groupname>"
    echo ""
    }

## Input ##

while (( $# ))
do
   case "${1}" in
     '--debug')              set -vx; ANSIBLE_OPTIONS="${ANSIBLE_OPTIONS} -vvv"; shift 1;;
     '--verbose')            VERBOSE=1; ANSIBLE_OPTIONS="${ANSIBLE_OPTIONS} -vvvv"; shift 1;;
     '--help')               showhelp;                     shift 1; exit ;;
     '--ask-pass')           ASK_PASS='--ask-pass';        shift 1;;
     '--key-auth')           ASK_PASS='';                  shift 1;;
     '--become')             BECOME=1;                     shift 1;;
     '--no-become')          BECOME=0;                     shift 1;;
     '--ask-become-pass')    ASK_BECOME_PASS=1;            shift 1;;
     '--no-ask-become-pass') ASK_BECOME_PASS=0;            shift 1;;
     '--list-hosts')         MODE='listhosts';             shift 1;;
     '-c'|'--command')       MODE='COMMAND'; CMD="${2}";   shift 2;;
     '-u'|'--user')          ANSIBLE_USER=="${2}";         shift 2;;
     '--timeout')            BACKGROUND_TIMEOUT="${2}";    shift 2;;
     '--hosts')              MODE='hosts';                 shift 1;;
     '--groups')             MODE='groups';                shift 1;;
     '--group')              MODE='group'; GROUP="${2}";   shift 2;;
     '--ssh-key-add')        MODE='ssh-key-add'; GROUP="${2}"; shift 2;;
     '-i'|'--inventory')     HOSTSFILE="${2}";             shift 2;;
     '-p'|'--playbook')      PLAYBOOK_FILE="${2}";         shift 2;;
     *)                      HOSTS+=( "${1}" );            shift 1;;
   esac
   if [ ${VERBOSE} ]; then echo "Input option: ${1}"; fi
done

if [ ${BECOME} -eq 1 ]
then
    if [ ${ASK_BECOME_PASS} -eq 1 ]
    then
        ANSIBLE_OPTIONS="--become --ask-become-pass --forks ${WORKERS} --timeout ${CONNECTION_TIMEOUT} ${ASK_PASS}"
    else
        ANSIBLE_OPTIONS="--become --forks ${WORKERS} --timeout ${CONNECTION_TIMEOUT} ${ASK_PASS}"
    fi
else
    ANSIBLE_OPTIONS="--forks ${WORKERS} --timeout ${CONNECTION_TIMEOUT} ${ASK_PASS}"
fi

## Main ##

if   [ "${MODE}" = "COMMAND" ]
then
    if [ "${CMD}" = '' ]; then echo "No command provided"; exit 1; fi
    if [ $VERBOSE ];
    then
        ANSIBLE_STDOUT_CALLBACK=actionable ansible ${ANSIBLE_OPTIONS} --poll ${POLL} --background ${BACKGROUND_TIMEOUT} --user ${ANSIBLE_USER} -i ${HOSTSFILE} -m ${MODULE} -a "${CMD}" ${HOSTS[*]}
    else
        ANSIBLE_STDOUT_CALLBACK=actionable ansible ${ANSIBLE_OPTIONS} --poll ${POLL} --background ${BACKGROUND_TIMEOUT} --user ${ANSIBLE_USER} -i ${HOSTSFILE} -m ${MODULE} -a "${CMD}" ${HOSTS[*]} | grep -E '^([a-z])|(        ")'
    fi
elif [ "${MODE}" = "PLAYBOOK" ]
then
    if [ "${PLAYBOOK_FILE}" = '' ]; then echo "No command provided"; exit 1; fi
    ansible-playbook ${ANSIBLE_OPTIONS} --user ${ANSIBLE_USER} -i ${HOSTSFILE} ${PLAYBOOK_FILE} --limit ${HOSTS[*]}
elif [ "${MODE}" = "listhosts" ]
then
    ansible ${ANSIBLE_OPTIONS} -i ${HOSTSFILE} --list-hosts ${HOSTS}
elif [ "${MODE}" = "hosts" ]
then
    #if [ -f 'main.yml' ]; then cat main.yml | grep -e '- hosts:'; fi
    ansible -i ${HOSTSFILE} all --list-hosts | grep -v '^  hosts' | sed 's/^\s*//' | sort
elif [ "${MODE}" = "group" ]
then
    ansible -i ${HOSTSFILE} ${GROUP} --list-hosts | grep -v '^  hosts' | sed 's/^\s*//' | sort
elif [ "${MODE}" = "groups" ]
then
    #cat ${HOSTSFILE} | grep -E '^\[' | awk '{print $1}' | tr -d '[]'
    #ANSIBLE_STDOUT_CALLBACK=json ansible-inventory group --list | jq -r '.children' | tr -d '"'
    ansible-inventory -i ${HOSTSFILE} group --list | jq -r '.all.children[]' | tr -d '", []' | sort -u | grep -vE '^$'
elif [ "${MODE}" = "ssh-key-add" ]
then
    for HOST in `ansible -i ${HOSTSFILE} ${GROUP} --list-hosts | grep -v '^  hosts' | sed 's/^\s*//'`
    do
        /usr/bin/ssh-keyscan -t rsa ${HOST}
    done
else
    echo "No valid mode selected";
    showhelp;
fi

## End ##

exit
