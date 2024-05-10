#!/usr/bin/python3
#################################################
# This script reads ansible json data and converts to
# different formats
#
# start with an Ansible inventory dump: ansible-inventory -i CPC/cpc_dev.yml -i CPC/cpc_qa.yml -i CPC/cpc_ops.yml --list > ansible.json
#
# Created by: Travis Sidelinger
# Version History:
#  2024May06 - Initial release
#
#################################################

## Modules ##
import yaml;
import json;
import pprint;
import os;
import re;
import sys;
import getopt;
from pathlib import Path;

# List modules
#help('modules')

## Variables ##

input_list = [ ];
conf = {
  'DEBUG':              0,
  'VERBOSE':            0,
  'ANSIBLE_DATA_FILE':  [],
  'INPUT_DATA_TYPE':    'json',
  'OUTPUT_DATA_TYPE':   'yaml',
  'MODE':               '',
  'HOST_VARS_DIR':      'host_vars/',
  'GROUP_VARS_DIR':     'group_vars/',
  }
ansible_hosts = [ ];
ansible_groups = { };
ansible_hostvars = { };
ansible_groupvars = { };

#################################################
## Functions ##

#######################
def showhelp( ):
    ## Main ##
    sys.stdout.write( "Usage: [options] <host|group> <host|group> <host|group>\n" )
    sys.stdout.write( "  -h --help Usage        Show help\n" )
    sys.stdout.write( "  -v --verbose           Enable verbose output\n" )
    sys.stdout.write( "  -d --debug             Enable debug output\n" )
    sys.stdout.write( "  -i --input=<file>      Input data file, multiple supported\n" )
    sys.stdout.write( "  -t --type=[json|yaml]  Input type\n" )
    sys.stdout.write( "  --hosts                Output mode hosts\n" )
    sys.stdout.write( "  --hostvars             Output mode hostvars\n" )
    sys.stdout.write( "  --groups               Output mode groups\n" )
    sys.stdout.write( "  --groupvars            Output mode groupvars\n" )
    sys.stdout.write( "\n" )

    ## Return ##
    exit( 1 )
    return( )

#######################
def parse_group( group_name, data_hash ):

    ## Main ##

    if( conf['DEBUG'] ): print( "Parsing: ", group_name );
    #print( "Items:   ", data_hash.items() );

    for item_type in data_hash:
        if( item_type == 'hosts' ):
            for host in data_hash[item_type]:
               if( conf['DEBUG'] ): print( 'Host: ', host );
               if( host not in ansible_hosts ): ansible_hosts.append( host );
               if( group_name in ansible_groups): ansible_groups[group_name].append( host );
               else: ansible_groups[group_name] = [];
        elif( item_type == 'children' ):
            for sub_group in data_hash[item_type]:
               if( conf['DEBUG'] ): print( 'Group: ', group_name, ' Child sub_group: ', sub_group );
               if( group_name not in ansible_groups ): ansible_groups[group_name] = [];
               ansible_groups[group_name].append( sub_group );
               try:
                   parse_group( sub_group, data_hash[item_type][sub_group] );
               except:
                   pass;
        elif( item_type == 'hostvars' ):
            for host in data_hash[item_type]:
               if( conf['DEBUG'] ): print( 'Host: ', host );
               for hostvar in data_hash[item_type][host]:
                   if( conf['DEBUG'] ): print( 'Host: ', host, 'Hostvar: ', hostvar );
                   if( host in ansible_hostvars ):
                       ansible_hostvars[host][hostvar] = data_hash[item_type][host][hostvar];
                   else:
                       ansible_hostvars[host] = {};
                       ansible_hostvars[host][hostvar] = data_hash[item_type][host][hostvar];
        elif( item_type == 'groupvars' ):
            for groupvar in data_hash[item_type]:
               if( conf['DEBUG'] ): print( 'Groupvar: ', groupvar );
               ansible_groupvar[group_name][groupvar] = data_hash[item_type][groupvar];
        elif( item_type == 'vars' ):
            for groupvar in data_hash[item_type]:
               if( conf['DEBUG'] ): print( 'Group: ', group_name, ' Groupvar: ', groupvar );
               if( group_name not in ansible_groupvars ): ansible_groupvars[group_name] = {};
               ansible_groupvars[group_name][groupvar] = data_hash[item_type][groupvar];
        else:
            if( conf['DEBUG'] ): print( 'Next item: ', item_type );
            parse_group( item_type, data_hash[item_type] );

    ## End ##
    return( );

#################################################
## Input Options ##

# Parsing argument
arglist = sys.argv[1:]
#arguments, values = getopt.getopt(argumentList, "hvdf:", [ "help", "verbose", "debug", "file=", "dev", "stg", "pre", "prd" ] )

# checking each argument
while( len( arglist ) > 0 ):
   if   arglist[0] in ["-h", "--help"]:      showhelp();
   elif arglist[0] in ["-v", "--verbose"]:   conf['VERBOSE']   += 1;                  arglist.pop(0);
   elif arglist[0] in ["-d", "--debug"]:     conf['DEBUG']     += 1;                  arglist.pop(0);
   elif arglist[0] in ["-i", "--input"]:     conf['ANSIBLE_DATA_FILE'].append( arglist[1] );  arglist.pop(0); arglist.pop(0);
   elif arglist[0] in ["-t", "--type"]:      conf['INPUT_DATA_TYPE']   = arglist[1];  arglist.pop(0); arglist.pop(0);
   elif arglist[0] in [      "--parse"]:     conf['MODE']       = 'PARSE';            arglist.pop(0);
   elif arglist[0] in [      "--hosts"]:     conf['MODE']       = 'HOSTS';            arglist.pop(0);
   elif arglist[0] in [      "--hostvars"]:  conf['MODE']       = 'HOSTVARS';         arglist.pop(0);
   elif arglist[0] in [      "--groups"]:    conf['MODE']       = 'GROUPS';           arglist.pop(0);
   elif arglist[0] in [      "--groupvars"]: conf['MODE']       = 'GROUPVARS';        arglist.pop(0);
   else:                                     input_list.append( arglist[0] );         arglist.pop(0);

#################################################
## Main ##

if conf['DEBUG']:
    print( 'DEBUG' );
    print( 'Input list: ', input_list );

# Foreach input data file, load the data
for input_file in conf['ANSIBLE_DATA_FILE']:
    
    # Load yaml file site data
    if( conf['INPUT_DATA_TYPE'] == 'json' ):
        ansible_data = json.load( open( input_file ) );
    elif( conf['INPUT_DATA_TYPE'] == 'yaml' ):
        ansible_data = yaml.safe_load( Path( input_file ).read_text() );
    else:
        print( 'Invalid input type selected: ', conf['INPUT_TYPE'] );
        exit(1);

    #if conf['DEBUG']: print( ansible_data );

    # Parse the inventory
    for data_item in ansible_data:
        parse_group( data_item, ansible_data[data_item] );

# show our data
if conf['DEBUG']: print( 'Groups: ',    ansible_groups );
if conf['DEBUG']: print( 'Hosts: ',     ansible_hosts );
if conf['DEBUG']: print( 'Hostvars: ',  ansible_hostvars );
if conf['DEBUG']: print( 'Groupvars: ', ansible_groupvars );

## Output modes ##

# Modes: print out hosts data
if( conf['MODE'] == 'HOSTS' ):
    if conf['DEBUG']: print( 'Hosts Mode' );
    for host in ansible_hosts:
        print( host );

# Mode: print out groups
if( conf['MODE'] == 'GROUPS' ):
    for group in ansible_groups:
       print( group );
       for member in ansible_groups[group]:
        print( " ", member );

# Mode: print out hostvars
if( conf['MODE'] == 'HOSTVARS' ):
    for host in ansible_hostvars:
        if( conf['DEBUG'] ):print( host );
        for hostvar in ansible_hostvars[host]:
            if( conf['DEBUG'] ): print( " ", hostvar, '=', ansible_hostvars[host][hostvar] );

        with open( conf['HOST_VARS_DIR'] + host + '.yml', 'w') as outfile:
            yaml.dump( ansible_hostvars[host], outfile, default_flow_style=False );

# Mode: print out groupvars
if( conf['MODE'] == 'GROUPVARS' ):
    for group in ansible_groupvars:
        if( conf['DEBUG'] ): print( group );
        for groupvar in ansible_groupvars[group]:
            if( conf['DEBUG'] ): print( " ", groupvar, '=', ansible_groupvars[group][groupvar] );

        with open( conf['GROUP_VARS_DIR'] + group + '.yml', 'w') as outfile:
            yaml.dump( ansible_groupvars[group], outfile, default_flow_style=False );

## End ##

exit();
