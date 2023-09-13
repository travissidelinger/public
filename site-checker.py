#!/usr/bin/python3
#################################################
# This script reads the sites.yml file and performs
# a series of checks for each site
#
# Created by: Travis Sidelinger
#
# Version History:
#  2023Jul11 - Initial release
#  2023Aug01 - Added --public
#  2023Aug11 - Added --list and --list-all
#  2023Sep07 - Added per server requests
#
#################################################

## Modules ##
import yaml
import pprint
import os
import re
import sys
import getopt
from pathlib import Path

#import dns.resolver
import dns.name
import dns.message
import dns.query
import dns.flags

# List modules
#help('modules')

## Variables ##

site_input_list = [ ]
conf = {
  'DEBUG':              0,
  'VERBOSE':            0,
  'username':           'test',
  'password':           'xxxxxxxxxxxx',
  'AUTH':               '',
  'WARN':               '3',
  'CRIT':               '4',
  'TIMEOUT':            '5',
  'STRING':             'PAGE_LOAD_STRING',
  'SSL_OPTS':           ' --ssl=1.2 --verify-host --sni',
  'SSL_OPTS2':          ' --ssl=1.2 --verify-host --sni --certificate=30 --continue-after-certificate',
  'CHECK_HTTP_BIN':     os.environ.get('HOME') + '/bin/check_http',
  'WGET_BIN':           '/usr/bin/wget',
  'SITES_FILE':         'sites.yml',
  'DEVONLY':            0,
  'TSTONLY':            0,
  'STGONLY':            0,
  'PREONLY':            0,
  'PRDONLY':            0,
  'PUBONLY':            0,
  'INTONLY':            0,
  'DNS_SERVER':         '8.8.8.8',
  'MODE':               'CHECK',
  }

conf['AUTH'] = ' --authorization=' + '"' + conf['username'] + ':' + conf['password'] + '"';

#################################################
## Functions ##

#######################
def showhelp( ):
    ## Main ##
    sys.stdout.write( "Usage: [options] <site> <site> <site>\n" )
    sys.stdout.write( "  -h --help Usage     Show help\n" )
    sys.stdout.write( "  -v --verbose        Enable verbose output\n" )
    sys.stdout.write( "  -d --debug          Enable debug output\n" )
    sys.stdout.write( "  -f --file=<file>    Site data file\n" )
    sys.stdout.write( "     --dev            Only dev instances\n" )
    sys.stdout.write( "     --tst            Only tst instances\n" )
    sys.stdout.write( "     --stg            Only stg instances\n" )
    sys.stdout.write( "     --pre            Only pre instances\n" )
    sys.stdout.write( "     --prd            Only prd instances\n" )
    sys.stdout.write( "     --public         Only public instances\n" )
    sys.stdout.write( "     --internal       Only internal instances\n" )
    sys.stdout.write( "     --noauth         No authentication\n" )
    sys.stdout.write( "     --list           List sites\n" )
    sys.stdout.write( "     --list-all       List all sites instances\n" )
    sys.stdout.write( "\n" )

    ## Return ##
    exit( 1 )
    return( )

#######################
def check_http_str( host, ipaddr, port, path, string ):
    ## Variables ##

    url = 'https://' + host + ':' + port + path
    status = ''
    code   = ''

    ## Main ##
    if( port == '443' ):
        command = conf['CHECK_HTTP_BIN'] \
                + conf['SSL_OPTS'] \
                + conf['AUTH'] \
                + ' --hostname='   + host \
                + ' --IP-address=' + ipaddr \
                + ' --port='       + port \
                + ' --warning='    + conf['WARN'] \
                + ' --critical='   + conf['CRIT'] \
                + ' --timeout='    + conf['TIMEOUT'] \
                + ' --uri='        + path \
                + ' --string="'    + string + '"' \
                + ' --onredirect=warning'
    else:
        command = conf['CHECK_HTTP_BIN'] \
                + conf['AUTH'] \
                + ' --hostname='   + host \
                + ' --IP-address=' + ipaddr \
                + ' --port='       + port \
                + ' --warning='    + conf['WARN'] \
                + ' --critical='   + conf['CRIT'] \
                + ' --timeout='    + conf['TIMEOUT'] \
                + ' --uri='        + path \
                + ' --string='     + string \
                + ' --onredirect=warning'

    if( conf['VERBOSE'] ): command = command + ' --show-url'

    # Run Command #
    if conf['DEBUG']: print( 'Command: ', command )
    stream = os.popen( command )
    output = stream.read().strip( "\n" );

    if( conf['DEBUG'] ): print( "Debug: ", output );

    # Return status
    if( re.match('^HTTP OK:',output ) ):
        output_split = re.split( '\|| - ', output )
        # Item number 3 should be the http status code
        if( len( re.split( ' ', output_split[0] ) ) >= 4 ): code = ( re.split( ' ', output_split[0] ) )[3];
        else: code = output;
        if( re.match( '^2', code ) ):
            if( conf['VERBOSE'] ): status = 'PASS ' + code + ', ' + output_split[1]
            else:                  status = 'PASS ' + code;
        else:
            if( conf['VERBOSE'] ): status = 'FAIL ' + code + ', ' + output_split[1]
            else:                  status = 'FAIL ' + code;
    elif( re.match('^HTTP WARN:', output ) ):
        output_split = re.split( '\|| - ', output )
        # Item number 3 should be the http status code
        if( len( re.split( ' ', output_split[0] ) ) >= 4 ): code = ( re.split( ' ', output_split[0] ) )[3];
        else: code = output;
        if( re.match( '^2', code ) ):
            if( conf['VERBOSE'] ): status = 'PASS ' + code + ', ' + output_split[1]
            else:                  status = 'PASS ' + code;
        else:
            if( conf['VERBOSE'] ): status = 'FAIL ' + code + ', ' + output_split[1]
            else:                  status = 'FAIL ' + code;
    elif( re.match('CRITICAL', output ) ):
        if( conf['VERBOSE'] ):
            output_split = re.split( '\|', output )
            status = 'FAIL ' + output_split[0];
        else:
            output_split = re.split( '\|| - ', output )
            status = 'FAIL ' + output_split[0]
    else:
        output_split = re.split( '\|| - ', output )
        if( conf['VERBOSE'] ): status = 'FAIL ' + output
        else:                  status = 'FAIL ' + output_split[0]

    ## Return ##
    return( status )

#######################
def check_http_redirect( host, ipaddr, port, path ):
    ## Variables ##

    url    = 'https://' + host + ':' + port + path
    code   = ''
    status = ''

    ## Main ##
    if( port == '443' ):
        command = conf['CHECK_HTTP_BIN'] \
                + conf['SSL_OPTS'] \
                + conf['AUTH'] \
                + ' --hostname='   + host \
                + ' --IP-address=' + ipaddr \
                + ' --port='       + port \
                + ' --warning='    + conf['WARN'] \
                + ' --critical='   + conf['CRIT'] \
                + ' --timeout='    + conf['TIMEOUT'] \
                + ' --uri='        + path \
                + ' --onredirect=ok'
    else:
        command = conf['CHECK_HTTP_BIN'] \
                + conf['AUTH'] \
                + ' --hostname='   + host \
                + ' --IP-address=' + ipaddr \
                + ' --port='       + port \
                + ' --warning='    + conf['WARN'] \
                + ' --critical='   + conf['CRIT'] \
                + ' --timeout='    + conf['TIMEOUT'] \
                + ' --uri='        + path \
                + ' --onredirect=ok'

    if( conf['VERBOSE'] ): command = command + ' --show-url'

    # Run Command #
    if conf['DEBUG']: print( 'Command: ', command )
    stream = os.popen( command )
    output = stream.read().strip( "\n" );

    # Return status
    if( re.match( '^HTTP OK:',output ) ):
        output_split = re.split( '\|| - ', output )
        # Item number 3 should be the http status code
        if( len( re.split( ' ', output_split[0] ) ) >= 4 ): code = ( re.split( ' ', output_split[0] ) )[3];
        else: code = output;
        if( re.match( '^3', code ) ):
            if( conf['VERBOSE'] ): status = 'PASS ' + code + ', ' + output_split[1]
            else:                  status = 'PASS ' + code;
        else:
            if( conf['VERBOSE'] ): status = 'FAIL ' + code + ', ' + output_split[1]
            else:                  status = 'FAIL ' + code;
    elif( re.match('^HTTP WARN:', output ) ):
        output_split = re.split( '\|| - ', output )
        # Item number 3 should be the http status code
        if( len( re.split( ' ', output_split[0] ) ) >= 4 ): code = ( re.split( ' ', output_split[0] ) )[3];
        else: code = output;
        if( re.match( '^3', code ) ):
            if( conf['VERBOSE'] ): status = 'PASS ' + code + ', ' + output_split[1]
            else:                  status = 'PASS ' + code;
        else:
            if( conf['VERBOSE'] ): status = 'FAIL ' + code + ', ' + output_split[1]
            else:                  status = 'FAIL ' + code;
    elif( re.match('CRITICAL', output ) ):
        if( conf['VERBOSE'] ):
            output_split = re.split( '\|', output )
            status = 'FAIL ' + output_split[0];
        else:
            output_split = re.split( '\|| - ', output )
            status = 'FAIL ' + output_split[0]
    else:
        output_split = re.split( '\|| - ', output )
        if( conf['VERBOSE'] ): status = 'FAIL ' + output
        else:                  status = 'FAIL ' + output_split[0]

    ## Return ##
    return( status )

#######################
def check_http_cmd( host, ipaddr, port, path ):
    ## Variables ##

    code   = ''
    status = ''

    ## Main ##
    if( port == '443' ):
        url = 'https://' + host + ':' + port + path
        command = conf['CHECK_HTTP_BIN'] \
                + conf['SSL_OPTS'] \
                + conf['AUTH'] \
                + ' --hostname='   + host \
                + ' --IP-address=' + ipaddr \
                + ' --port='       + port \
                + ' --warning='    + conf['WARN'] \
                + ' --critical='   + conf['CRIT'] \
                + ' --timeout='    + conf['TIMEOUT'] \
                + ' --uri='        + path \
                + ' --onredirect=critical'
    else:
        url = 'http://' + host + ':' + port + path
        command = conf['CHECK_HTTP_BIN'] \
                + conf['AUTH'] \
                + ' --hostname='   + host \
                + ' --IP-address=' + ipaddr \
                + ' --port='       + port \
                + ' --warning='    + conf['WARN'] \
                + ' --critical='   + conf['CRIT'] \
                + ' --timeout='    + conf['TIMEOUT'] \
                + ' --uri='        + path \
                + ' --onredirect=critical'

    if( conf['VERBOSE'] ): command = command + ' --show-url'

    # Run Command #
    if conf['DEBUG']: print( 'Command: ', command )
    stream = os.popen( command )
    output = stream.read().strip( "\n" );

    # Return status
    if( re.match('^HTTP OK:',output ) ):
        output_split = re.split( '\|| - ', output )
        # Item number 3 should be the http status code
        if( len( re.split( ' ', output_split[0] ) ) >= 4 ): code = ( re.split( ' ', output_split[0] ) )[3];
        else: code = output;
        if( conf['VERBOSE'] ): status = 'PASS ' + code + ', ' + output_split[1]
        else:                  status = 'PASS ' + code;
    elif( re.match('^HTTP WARN:', output ) ):
        output_split = re.split( '\|| - ', output )
        # Item number 3 should be the http status code
        if( len( re.split( ' ', output_split[0] ) ) >= 4 ): code = ( re.split( ' ', output_split[0] ) )[3];
        else: code = output;
        if( conf['VERBOSE'] ): status = 'PASS ' + code + ', ' + output_split[1]
        else:                  status = 'PASS ' + code;
    elif( re.match('CRITICAL', output ) ):
        if( conf['VERBOSE'] ): status = 'FAIL ' + output;
        else:
            output_split = re.split( '\|| - ', output )
            status = 'FAIL ' + output_split[0] + ' ' + output_split[1]
    else:
        if( conf['VERBOSE'] ): status = 'FAIL ' + output
        else:
            output_split = re.split( '\|', output );
            status = 'FAIL ' + output;

    ## Return ##
    return( status )

#######################
def wget_match_str( host, port, path, pattern ):
    ## Variables ##

    url = ''
    output = ''

    ## Main ##
    if( port == '443' ): url = 'https://' + host + path
    else: url = 'http://' + host + path

    command = conf['WGET_BIN'] + ' -q ' + ' --http-user=' + conf['username'] + ' --http-password=' + conf['password'] + ' ' + url + ' -O - | grep "' + pattern + '"'

    # Run Command #
    if conf['DEBUG']: print( 'Command: ', command )
    stream = os.popen( command )
    output = stream.read()
    output = output.strip( "\n" );

    ## Return ##
    return( output )

#######################
def dns_lookup( domain ):
    ## Variables ##

    value = ''

    ## Main ##

    #command = 'host -r ' + host + ' | head -1'
    #if conf['DEBUG']: print( 'Command: ', command )
    #stream = os.popen( command )
    #value = dns.query( host )
    #value = dns.query.udp = udp( host, '8.8.8.8', timeout=4, port=53, source=None, source_port=0, ignore_unexpected=False, one_rr_per_rrset=False, ignore_trailing=False, raise_on_truncation=False, sock=None)

    name_server = '65.175.128.181'
    ADDITIONAL_RDCLASS = 65535

    domain = dns.name.from_text( domain )
    if not domain.is_absolute():
        domain = domain.concatenate(dns.name.root)

    request = dns.message.make_query(domain, dns.rdatatype.ANY)
    request.flags |= dns.flags.AD
    request.flags ^= dns.flags.RD
    request.find_rrset(request.additional, dns.name.root, ADDITIONAL_RDCLASS, dns.rdatatype.OPT, create=True, force_unique=True)
    response = dns.query.udp(request, name_server)

    #pprint.pprint( response.answer )
    #print response.answer
    #print( 'Answer: ', response.answer )
    #print( response.additional )
    #print( response.authority )
    #print( 'List0:   ', response.answer[0] )
    #print( 'List00   ', response.answer[0][0] )
    #print( 'Type:    ', type( response.answer ) )
    #print( 'Type:    ', type( response.answer[0] ) )
    #print( 'to_text: ', response.answer[0].to_text )
    #print( 'get_rrset: ' , response.get_rrset ( response.answer, domain ) )
    #print( response.answer.to_text )

    ## Return ##

    return( response.answer[0] )

#################################################
## Input Options ##

# Parsing argument
arglist = sys.argv[1:]
#arguments, values = getopt.getopt(argumentList, "hvdf:", [ "help", "verbose", "debug", "file=", "dev", "stg", "pre", "prd" ] )

# checking each argument
while( len( arglist ) > 0 ):
   if   arglist[0] in ["-h", "--help"]:     showhelp();
   elif arglist[0] in ["-v", "--verbose"]:  conf['VERBOSE']   += 1;          arglist.pop(0);
   elif arglist[0] in ["-d", "--debug"]:    conf['DEBUG']     += 1;          arglist.pop(0);
   elif arglist[0] in ["-f", "--file"]:     conf['SITES_FILE'] = arglist[1]; arglist.pop(0); arglist.pop(0);
   elif arglist[0] in [      "--dev"]:      conf['DEVONLY']   += 1;          arglist.pop(0);
   elif arglist[0] in [      "--tst"]:      conf['TSTONLY']   += 1;          arglist.pop(0);
   elif arglist[0] in [      "--stg"]:      conf['STGONLY']   += 1;          arglist.pop(0);
   elif arglist[0] in [      "--pre"]:      conf['PREONLY']   += 1;          arglist.pop(0);
   elif arglist[0] in [      "--prd"]:      conf['PRDONLY']   += 1;          arglist.pop(0);
   elif arglist[0] in [      "--public"]:   conf['PUBONLY']   += 1;          arglist.pop(0);
   elif arglist[0] in [      "--internal"]: conf['INTONLY']   += 1;          arglist.pop(0);
   elif arglist[0] in [      "--noauth"]:   conf['AUTH']       = '';         arglist.pop(0);
   elif arglist[0] in [      "--list"]:     conf['MODE']       = 'LIST';     arglist.pop(0);
   elif arglist[0] in [      "--list-all"]: conf['MODE']       = 'LISTALL';  arglist.pop(0);
   else:                                    site_input_list.append( arglist[0] ); arglist.pop(0);

#################################################
## Main ##

if conf['DEBUG']: print( 'Input list: ', site_input_list, len(site_input_list) )

# Load yaml file site data
sites_data = yaml.safe_load(Path( conf['SITES_FILE'] ).read_text())

if( conf['DEBUG'] > 1 ):
    print( "Site data dump:\n" )
    pprint.pprint( sites_data )
    print( "\n" )

if( conf['DEBUG'] ):
    print( "Config data dump:\n" )
    pprint.pprint( conf )
    print( "\n" )

# List mode
if( conf['MODE'] == 'LIST' ):
    for site in sites_data["sites"]:
       print( site, sep='', end='\n' );

# List mode
if( conf['MODE'] == 'LISTALL' ):
    for site in sites_data["sites"]:
        for prod_status in sites_data["sites"][site].keys():
            print( site, '-', prod_status, sep='', end='\n' );

# Check mode, Parse all sites
if( conf['MODE'] == 'CHECK' ):
  for site in sites_data["sites"]:
    # Are we picking from a list of sites, or doing all the sites?
    do_check_this_site = 0
    if( len( site_input_list ) > 0 ):
      if( site in site_input_list ):
        do_check_this_site = 1
    else: do_check_this_site = 1

    if( do_check_this_site == 1 ):
        print( '################################' );
        print( 'App: ' + site )
        for prod_status in sites_data["sites"][site].keys():
            do_check_this_prod_status = 0
            if( ( conf['DEVONLY'] == 1 ) and ( prod_status == 'dev'    ) ): do_check_this_prod_status = 1
            if( ( conf['TSTONLY'] == 1 ) and ( prod_status == 'tst'    ) ): do_check_this_prod_status = 1
            if( ( conf['STGONLY'] == 1 ) and ( prod_status == 'stg'    ) ): do_check_this_prod_status = 1
            if( ( conf['PREONLY'] == 1 ) and ( prod_status == 'pre'    ) ): do_check_this_prod_status = 1
            if( ( conf['PRDONLY'] == 1 ) and ( prod_status == 'prd'    ) ): do_check_this_prod_status = 1
            if( ( conf['PUBONLY'] == 1 ) and ( prod_status == 'public' ) ): do_check_this_prod_status = 1
            if( ( conf['INTONLY'] == 1 ) and ( prod_status == 'internal' ) ): do_check_this_prod_status = 1

            # If none are set, do them all
            if( ( conf['DEVONLY'] or conf['TSTONLY'] or conf['STGONLY'] or conf['PREONLY'] or conf['PRDONLY'] or conf['PUBONLY'] or conf['INTONLY'] ) != 1 ): do_check_this_prod_status = 1

            if( do_check_this_prod_status == 1 ):
                # Start a new prod_statusance
                sys.stdout.write( ' ' + prod_status + ":\n" )
                #if( prod_status == 'public' ): prod_status = 'prd';

                # Build the hostname
                if( 'host' in sites_data['sites'][site][prod_status] ):
                    if( sites_data['sites'][site][prod_status]['host'] == '' ):
                        hostname       = sites_data['sites'][site][prod_status]['domain'];
                        short_hostname = sites_data['sites'][site][prod_status]['domain'];
                    else:
                        hostname       = sites_data['sites'][site][prod_status]['host'] + '.' + sites_data['sites'][site][prod_status]['domain'];
                        short_hostname = sites_data['sites'][site][prod_status]['host'];
                else:
                    hostname       = site + '-' + prod_status + '.' + sites_data['sites'][site][prod_status]['domain'];
                    short_hostname = site + '-' + prod_status;

                sys.stdout.write( '  Host:            ' + hostname + "\n" );

                # DNS Lookup
                ADDITIONAL_RDCLASS = 65535
                dns_domain = dns.name.from_text( hostname )
                if( not dns_domain.is_absolute() ): dns_domain = dns_domain.concatenate( dns.name.root );
                dns_request = dns.message.make_query( dns_domain, dns.rdatatype.ANY )
                dns_response = dns.query.udp( dns_request, conf['DNS_SERVER'] )
                if( dns_response.answer ):
                    for dns_answer in dns_response.answer:
                        dns_record_type = re.split( ' ', str( dns_answer ) )[3];
                        dns_record_dest = re.split( ' ', str( dns_answer ) )[4];
                        if( dns_record_type == 'CNAME' or dns_record_type == 'A' or dns_record_type == 'AAAA' ):
                            if( conf['DEBUG'] ): print( '  DNS:             ', dns_answer, sep='', end='\n', file=sys.stdout, flush=False )
                            else:                print( '  DNS:             ', dns_record_type, ' ', dns_record_dest, sep='', end='\n', file=sys.stdout, flush=False )
                        else:
                            if( conf['DEBUG'] ): print( '  DNS:             ', dns_response, sep='', end='\n', file=sys.stdout, flush=False )

                else:
                    if( conf['DEBUG'] ): print( '  DNS: FAIL               ' , dns_response, sep='', end='\n', file=sys.stdout, flush=False )
                    else: print( '  DNS: FAIL', sep='', end='\n', file=sys.stdout, flush=False )

                # Check page loaded string
                if( sites_data['sites'][site][prod_status]['check-string'] == True ):
                    if( 'path' in sites_data['sites'][site][prod_status].keys() ):
                        sys.stdout.write( '  URL:             https://' + hostname + ':443' + sites_data['sites'][site][prod_status]['path'] + "\n" )
                        sys.stdout.write( '  Page-String:     '  + check_http_str( hostname, hostname, '443', sites_data['sites'][site][prod_status]['path'], conf['STRING'] ) + ' (' + conf['STRING'] + ")\n" )

                # Check site redirect
                if( sites_data['sites'][site][prod_status]['check-redirect'] == True ):
                   if( 'redirect' in sites_data['sites'][site][prod_status].keys() ):
                        sys.stdout.write( '  URL:             https://' + hostname + ':443' + "\n" )
                        sys.stdout.write( '  Redirect:        '  + check_http_redirect( hostname, hostname, '443', '/' ) + "\n" )

                # Check http redirect to https
                if( sites_data['sites'][site][prod_status]['check-http-redir'] == True ):
                    sys.stdout.write( '  HTTP-Redirect:   '  + check_http_redirect( hostname, hostname, '80',  '/' ) + "\n" )

                # Check /check, both http and https
                if( sites_data['sites'][site][prod_status]['check-http'] == True ):
                    sys.stdout.write( '  Check-HTTP:      '  + check_http_str(      hostname, hostname, '80', '/check', conf['STRING'] ) + "\n" )
                if( sites_data['sites'][site][prod_status]['check-https'] == True ):
                    sys.stdout.write( '  Check-HTTPS:     '  + check_http_str(      hostname, hostname, '443', '/check', conf['STRING'] ) + "\n" )

                # Check /server-status
                if( sites_data['sites'][site][prod_status]['check-status'] == True ):
                    server_status_check = check_http_cmd( hostname, hostname, '443', '/server-status' );
                    if( re.match( '^PASS', server_status_check ) ):
                        server_status_requests =  wget_match_str( hostname, '80', '/server-status', 'requests currently being processed'  )
                        server_status_requests = server_status_requests.strip( '<dt>' );
                        server_status_requests = server_status_requests.strip( '</dt>' );
                        server_status_requests = re.sub( 'requests currently being processed', 'current', server_status_requests );
                        sys.stdout.write( '  Server-Status:   ' + server_status_check + ' (' + server_status_requests + ")\n" )
                    else:
                        sys.stdout.write( '  Server-Status:   ' + server_status_check + "\n" )

                # Check /server-info
                if( sites_data['sites'][site][prod_status]['check-info'] == True ):
                  sys.stdout.write( '  Server-Info:     '  + check_http_cmd( hostname, hostname, '443', '/server-info' ) + "\n" )

                # Check /php-info
                if( sites_data['sites'][site][prod_status]['check-php'] == True ):
                    php_info_check = check_http_str( hostname, hostname, '443', '/php-info', 'PHP Version' );
                    if( re.match( '^PASS', php_info_check ) ):
                        php_info_version = wget_match_str( hostname, '80', '/php-info', 'PHP Version <' )
                        php_info_version = re.sub( '<.*?>' , '', php_info_version )
                        php_info_version = re.sub( 'PHP Version ' , '', php_info_version )
                        php_info_version = re.sub( ' ' , '', php_info_version )
                        sys.stdout.write( '  PHP-Info:        '  + php_info_check + ' (' + php_info_version + ")\n" )
                    else:
                        sys.stdout.write( '  PHP-Info:        '  + php_info_check + "\n" )

                # Check LoadBalancer
                if( sites_data['sites'][site][prod_status]['check-lb'] == True ):
                    if( 'lb' in sites_data['sites'][site][prod_status].keys() ):
                        sys.stdout.write( '  LB-Check:        ' + check_http_cmd( hostname, sites_data['sites'][site][prod_status]['lb'], '443', '/check' ) + "\n" )

                # Check each server
                if( sites_data['sites'][site][prod_status]['check-servers'] == True ):
                    if( 'servers' in sites_data['sites'][site][prod_status].keys() ):
                        for number in sites_data['sites'][site][prod_status]['servers']:
                            server_name = short_hostname + number + '.' + sites_data['sites'][site][prod_status]['domain'];
                            sys.stdout.write( '  Server ' + prod_status + number + ':    ' + check_http_str( server_name, server_name, '80',  '/check', conf['STRING'] ) )
                            server_status_check = check_http_cmd( server_name, server_name, '80', '/server-status' );
                            if( re.match( '^PASS', server_status_check ) ):
                                server_status_requests = wget_match_str( hostname, '80', '/server-status', 'requests currently being processed'  )
                                server_status_requests = server_status_requests.strip( '<dt>' );
                                server_status_requests = server_status_requests.strip( '</dt>' );
                                server_status_requests = re.sub( 'requests currently being processed', 'current', server_status_requests );
                                sys.stdout.write( ' (' + server_status_requests + ")\n" )
                            else:
                                sys.stdout.write( " (FAIL)\n" )

                # Check application health
                if( sites_data['sites'][site][prod_status]['check-health'] == True ):
                    if( 'health' in sites_data['sites'][site][prod_status].keys() ):
                        sys.stdout.write( '  Health:          ' + check_http_cmd( hostname, hostname, '443', sites_data['sites'][site][prod_status]['health'] ) + ' ' + sites_data['sites'][site][prod_status]['health'] + "\n" )

## End ##
exit()
