#!/usr/bin/perl
###################################################################################################
#
# Description:
#   This tool parses a web log stream and displays useful information.
#   Designed for realtime monitoring at the command prompt.
#
# Copyright: Travis Sidelinger
# License: GPL2

my $version = '2023-09-02';

# Version History:
#  - 2007Dec13 : TLS : Added string length items
#  - 2007Dec11 : TLS : Initial release
#  - 2023Feb17 : TLS : New version
#  - 2023Feb27 : TLS : Updated report_min
#  - 2023Feb28 : TLS : Updated report_hour, Add report_stat
#  - 2023Mar08 : TLS : Added bytesin accounting, added auto format updates, added multi sorting, options cleanup
#  - 2023Mar13 : TLS : Fixed BAESLINE count
#  - 2023Mar15 : TLS : Added more items to the summary report
#  - 2023Mar17 : TLS : Major update: merged the INDEX and REPORT variables
#                      Added allowing multiping reports at the same type
#                      Now using separate index variables
#                      Added filter limits for IP and Hour
#  - 2023Mar20 : TLS : Updated sort controls to prevent deplicate reports
#                      Added ignore ip list
#                      Added most common line to the summary report
#  - 2023Mar22 : TLS : Verbose line printf added byte_size and time_size
#                      summary_report format fixes
#  - 2023Mar27 : TLS : Added report_urlcodesors
#  - 2023Apr11 : TLS : Added new report report_codes, changed COUNT to TOTAL for sorting and collumns
#  - 2023Apr12 : TLS : Cleaning up some reports
#  - 2023Apr18 : TLS : Added default reporting mode
#                      Added shortening for ipv6 addresses
#                      Re-wrote how the log lines are split apart to resolve UserAgent capture, we were hitting the limits of perl for $1 - 9$ variables
#                      Added new logging format
#  - 2023Apr21 : TLS   Added version number
#                      Fixed new log format parsing
#  - 2023Jun01 : TLS : Added new --ipv6 option so we can display the full ipv6 address
#  - 2023Jun06 : TLS : version date updated
#  - 2023Aug02 : TLS : Added more known ip addresses
#
###################################################################################################

## Modules ##

use warnings;
use strict;
use Getopt::Long;   # standard library for handling input options
use Data::Dumper;
use POSIX qw(strftime);
use Time::Local;
use Carp;
use JSON::XS;
#use JSON::PP;
#use IO::Handle;
#STDOUT->autoflush(1);
#STDERR->autoflush(1);

## Variables ##

my %conf = (
                'DEBUG'          => 0,
                'VERBOSE'        => 0,
                'ALLOW_CSSJS'    => 0,
                'ALLOW_IMAGES'   => 0,
                'SYSLOG'         => 1,
                'FORMAT'         => 'apache-json',
                'REPORT_SUM'     => 0,
                'REPORT_DAY'     => 0,
                'REPORT_HOUR'    => 0,
                'REPORT_MIN'     => 0,
                'REPORT_IP'      => 0,
                'REPORT_URL'     => 0,
                'REPORT_STAT'    => 0,
                'REPORT_CODES'     => 0,
                'URLWIDTH'       => 80,
                'LIMIT'          => 10,
                'IMAGES'         => [ 'png','jpg','jpeg','tiff','tif','svg','webm','webp','ico','gif'],
                'WEBFILES'       => [ 'css','js','txt','xml' ],
                'REPORTDONE'     => 0,
                'SORT'           => 'DEFAULT',
                'KNOWN_IP_LIST'  => [ '10.0.0.10', '10.0.0.11' ],
                'SHOW_KNOWN_IPS' => 1,
                'LIMITHOUR'      => 0,
                'LIMITIP'        => '',
                'IPV6'           => 0,
                'IP_WIDTH'       => 16,
                );
my %data_sum;
my %data_day;
my %data_hour;
my %data_min;
my %data_ip;
my %data_url;
my %data_stat;
my %data_codes;
my @invalid_lines;
my $temp;

my %months = (
               'Jan' => 1,
               'Feb' => 2,
               'Mar' => 3,
               'Apr' => 4,
               'May' => 5,
               'Jun' => 6,
               'Jul' => 7,
               'Aug' => 8,
               'Sep' => 9,
               'Oct' => 10,
               'Nov' => 11,
               'Dec' => 12,
               'UNK' => 13,
               );

###################################################################################################
# Input argument processing

Getopt::Long::Configure("bundling", "pass_through", "ignore_case", "permute");
GetOptions
(
    'help|?|h'     => \&showhelp,
    'version'      => sub{ print( "version: ${version}\n" ); exit 0; },
    'debug|d'      => sub{ $conf{DEBUG}++ ;            },
    'verbose|v'    => sub{ $conf{VERBOSE}++;           },
    'files|f'      => sub{ $conf{ALLOW_CSSJS}  = 1;    },
    'images|i'     => sub{ $conf{ALLOW_IMAGES} = 1;    },
    'ignore-ips'   => sub{ $conf{SHOW_KNOWN_IPS} = 0;  },
    'sort|s:s'     => \$conf{SORT},
    'limit|l:i'    => \$conf{LIMIT},
    'width|w:i'    => \$conf{URLWIDTH},
    'sum|summary'  => sub{ $conf{REPORT_SUM}++;   },
    'nosum'        => sub{ $conf{REPORT_SUM} = 0; },
    'day|daily'    => sub{ $conf{REPORT_DAY}++;   },
    'hour'         => sub{ $conf{REPORT_HOUR}++;  },
    'min|minute'   => sub{ $conf{REPORT_MIN}++;   },
    'ipaddr|ip'    => sub{ $conf{REPORT_IP}++;    },
    'stat|status'  => sub{ $conf{REPORT_STAT}++;  },
    'url'          => sub{ $conf{REPORT_URL}++;   },
    'codes'        => sub{ $conf{REPORT_CODES}++; },
    'limit-hour:i' => \$conf{LIMITHOUR},
    'limit-ip:s'   => \$conf{LIMITIP},
    'ipv6'         => sub{ $conf{IPV6}++; $conf{IP_WIDTH} = 40 },
    );

# Setup the corret break report mode.  We can only have one of these
if(    $conf{REPORT_SUM}   )  { $SIG{INT} = \&report_sum;    $SIG{TERM} = \&report_sum;   }
elsif( $conf{REPORT_IP}    )  { $SIG{INT} = \&report_ip;     $SIG{TERM} = \&report_ip;    }
elsif( $conf{REPORT_URL}   )  { $SIG{INT} = \&report_url;    $SIG{TERM} = \&report_url;   }
elsif( $conf{REPORT_MIN}   )  { $SIG{INT} = \&report_min;    $SIG{TERM} = \&report_min;   }
elsif( $conf{REPORT_DAY}   )  { $SIG{INT} = \&report_day;    $SIG{TERM} = \&report_day;   }
elsif( $conf{REPORT_HOUR}  )  { $SIG{INT} = \&report_hour;   $SIG{TERM} = \&report_hour;  }
elsif( $conf{REPORT_STAT}  )  { $SIG{INT} = \&report_stat;   $SIG{TERM} = \&report_stat;  }
elsif( $conf{REPORT_CODES} )  { $SIG{INT} = \&report_codes;  $SIG{TERM} = \&report_codes; }
else { $conf{REPORT_SUM} = 1;   $SIG{INT} = \&report_sum;    $SIG{TERM} = \&report_sum;   }  # Set a default reporting mode

###################################################################################################
# Main

# Diplay the line
if( $conf{VERBOSE} )
{
    printf( "Line: %-10s %-8s %-$conf{IP_WIDTH}s %-4s %-6s %-6s %-8s %-7s %-.$conf{URLWIDTH}s\n", 'Date', 'Time', 'IPAddr', 'Stat', 'B-In', 'B-Out', 'ExecT', 'Method', 'URL' );
    }

while( <> )
{
    my $line = $_;
    my %linedata;
    chomp( $line );
    if( $conf{DEBUG} > 1 ) { print( "Input: ",$line, "\n" ); }

    if( $conf{SYSLOG} ) { $line =~ s/^.+?:\s//; }  # remove the syslog entry part

    # Auto pick the correct line format
    if( $line =~ m/^\{/ ) { $conf{FORMAT} = 'apache-json'; }
    if( $line =~ m/^\[/ ) { $conf{FORMAT} = 'apache-url';  }

    # Apache URL log data
    if( ( $conf{FORMAT} eq 'apache-url' ) | ( $conf{FORMAT} eq 'url' ) )
    {
        %linedata = (
                      'DATE_TIME' => '',
                      'IPADDR'    => '',
                      'METHOD'    => '',
                      'URL'       => '',
                      'STATUS'    => '',
                      'PROTO'     => '',
                      'HTTPHOST'  => '',
                      'PORT'      => '',
                      'PATH'      => '',
                      'OPTIONS'   => '',
                      'BYTESIN'   => 0,
                      'BYTESOUT'  => 0,
                      'EXECTIME'  => 0,
                      '2xx'       => 0,
                      '3xx'       => 0,
                      '4xx'       => 0,
                      '5xx'       => 0,
                      'FILETYPE'  => '',
                      );

        if( $line =~ m|^\[(.+?)\] ([0-9a-f\.:]+) ([a-zA-Z0-9\-]+) ([A-Z\-]+) (.+?) s=([0-9]+) b=([0-9]+) t=([0-9]+) ref=".*?" [au]{2}="(.*?)"| )
        {
            ( $linedata{DATE_TIME}, $linedata{IPADDR}, $linedata{USER}, $linedata{METHOD}, $linedata{URL}, $linedata{STATUS}, $linedata{BYTESOUT}, $linedata{EXECTIME}, $linedata{USERAGENT} ) = ( $line =~ m|^\[(.+?)\] ([0-9a-f\.:]+) ([a-zA-Z0-9\-]+) ([A-Z\-]+) (.+?) s=([0-9]+) b=([0-9]+) t=([0-9]+) ref=".*?" [au]{2}="(.*?)"| );
            }
        # [17/Apr/2023:03:19:07 +0000] 65.175.142.38 - GET http://-:80/ s=403 bi=12 bo=202 t=186 ref="-" ua="-"
        # new format as of mid march, fixed au= to ua=, added bytes-in
        elsif( $line =~ m|^\[(.+?)\] ([0-9a-f\.:]+) ([a-zA-Z0-9\-]+) ([A-Z\-]+) (.+?) s=([0-9]+) bi=([0-9]+) bo=([0-9]+) t=([0-9]+) ref=".*?" ua="(.*?)"| )
        {
           ( $linedata{DATE_TIME}, $linedata{IPADDR}, $linedata{USER}, $linedata{METHOD}, $linedata{URL}, $linedata{STATUS}, $linedata{BYTESIN}, $linedata{BYTESOUT}, $linedata{EXECTIME}, $linedata{USERAGENT} ) = ( $line =~ m|^\[(.+?)\] ([0-9a-f\.:]+) ([a-zA-Z0-9\-]+) ([A-Z\-]+) (.+?) s=([0-9]+) bi=([0-9]+) bo=([0-9]+) t=([0-9]+) ref=".*?" ua="(.*?)"| );
           }
        # new format as of 2023Apr18, removed the referenece value, put quotes around the URL because they can contain spaces and other charactors
        # [21/Apr/2023:16:34:16 +0000] 10.223.224.103 - GET url="http://app.mysite.com:443/images/frontend/shortcuts-icon.png" s=304 bi=2049 bo=- t=467 ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36"
        # [21/Apr/2023:03:31:42 +0000] 172.21.16.108 - GET url="http://app.mysite.com:443/images/frontend/logo-app.png" s=304 bi=2559 bo=- t=1107 ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36"
        elsif( $line =~ m|^\[(.+?)\] ([0-9a-f\.:]+) ([a-zA-Z0-9\-]+) ([A-Z\-]+) url="(.+?)" s=([0-9]+) bi=([0-9\-]+) bo=([0-9\-]+) t=([0-9\-]+) ua="(.*?)"| )
        {
           ( $linedata{DATE_TIME}, $linedata{IPADDR}, $linedata{USER}, $linedata{METHOD}, $linedata{URL}, $linedata{STATUS}, $linedata{BYTESIN}, $linedata{BYTESOUT}, $linedata{EXECTIME}, $linedata{USERAGENT} ) = ( $line =~ m|^\[(.+?)\] ([0-9a-f\.:]+) ([a-zA-Z0-9\-]+) ([A-Z\-]+) url="(.+?)" s=([0-9]+) bi=([0-9\-]+) bo=([0-9\-]+) t=([0-9\-]+) ua="(.*?)"| );
           }
        else
        {
            push( @invalid_lines, $line );
            if( $conf{VERBOSE} ) { print( "Invalid Line: ${line}\n" ); }
            next;
            }

        # Split the date/time info
        if( $linedata{DATE_TIME} =~ m|^([0-9]+)/([A-Za-z]+)/([0-9]+):([0-9][0-9]):([0-9][0-9]):([0-9][0-9]) | )
        {
            $linedata{DAY}  = $1;
            $linedata{MON}  = $2;
            $linedata{YEAR} = $3;
            $linedata{HOUR} = $4;
            $linedata{MIN}  = $5;
            $linedata{SEC}  = $6;
            }
        else
        {
            push( @invalid_lines, $line );
            if( $conf{VERBOSE} ) { print( "Invalid Date/Time: $linedata{DATE_TIME}\n" ); }
            if( $conf{DEBUG}   ) { print( "Line Data: ", Dumper( \%linedata ), "\n" );    }
            next;
            }

        # ipv6 cleanup
        # We can't fit the whole ipv6 address on screen, trimming to the last 4 octets, or less
        if( $linedata{IPADDR} =~ m/:/ )
        {
            if( ! $conf{IPV6} )
            {
                # Example: 2600:3c02::f03c:92ff:feb4:914b
                $linedata{IPADDR} =~ s/::/:0000:/g;
                ( my @ipv6_split ) = ( split( ':', $linedata{IPADDR} ) );
                $linedata{IPADDR} = $ipv6_split[0] . '..' . $ipv6_split[ $#ipv6_split - 1 ] . ':' . $ipv6_split[ $#ipv6_split - 0 ];
                }
            }

        # Split up the URL info
        if( $linedata{URL} =~ m|^(.+?)://([a-zA-Z0-9\.\-]+):([0-9]+)(.*)$| )
        {
            $linedata{PROTO}    = $1;
            $linedata{HTTPHOST} = $2;
            $linedata{PORT}     = $3;
            $linedata{PATHOPTS} = $4;
            }
        else
        {
            push( @invalid_lines, $line );
            if( $conf{VERBOSE} ) { print( "Invalid URL: $linedata{URL}\n" ); }
            next;
            }

        # Path / options cleanup
        if( exists( $linedata{PATHOPTS} ) and ( defined( $linedata{PATHOPTS} ) ) )
        {
            if( $linedata{PATHOPTS} =~ m/\?/ )
            {
                ( $linedata{PATH}, $linedata{OPTIONS} ) = split( m/\?/, $linedata{PATHOPTS} );
                }
            else
            {
                $linedata{PATH} = $linedata{PATHOPTS};
                $linedata{OPTIONS} = '';
                }
            }
        else
        {
            { $linedata{PATH} = ''; }
            }

        # More data cleanup
        if( ! exists( $linedata{OPTIONS} ) ) { $linedata{OPTIONS} = ''; }
        $linedata{URL}       =~ s/\?.*$//;   # remove the options from URL
        $linedata{STATUS}    =~ s/^s=//;     # remove the s=
        $linedata{BYTESOUT}  =~ s/^b=//;     # remove the b=
        $linedata{BYTESOUT}  =~ s/^bo=//;    # remove the bo=
        $linedata{BYTESIN}   =~ s/^bi=//;    # remove the bi=
        $linedata{EXECTIME}  =~ s/^t=//;     # remove the t=
        $linedata{USERAGENT} =~ s/ua=//;     # remove the ua=
        if( $linedata{BYTESOUT} eq '-' ) { $linedata{BYTESOUT}  = 0; }
        if( $linedata{BYTESIN}  eq '-' ) { $linedata{BYTESIN}   = 0; }
        if( $linedata{EXECTIME} eq '-' ) { $linedata{EXECTIME}  = 0; }

        #print( "DateTime: ", Dumper( ( localtime(time())) ), "\n" );
        #localtime(time) = ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
        $linedata{EPOCH} = timelocal( $linedata{SEC}, $linedata{MIN}, $linedata{HOUR}, $linedata{DAY}, $linedata{MON}, $linedata{YEAR}, undef, undef, undef );

        # Basic request
        $linedata{REQUEST} = $linedata{IPADDR} . ' ' . $linedata{METHOD} . ' ' . $linedata{URL};

        # File extention type
        if( $linedata{PATH} =~ m/\.([a-zA-Z]+)$/ ) { $linedata{FILETYPE} = $1; }
        }

    # JSON Data
    elsif( $conf{FORMAT} eq 'apache-json' )
    {
        $line =~ s|"time":"\\|"time":"|;  # Remove the extra \
        $line =~ s|\\x|\\\\x|g;           # utf16 encodings will error in the JSON parser

        #use Encode qw/encode decode/;
        #$line = decode( 'utf8', $line );
        #print( "Line: ", $line, "\n" );

        # Convert the json data to a hash
        my $json = new JSON::XS;
        $json->utf8;
        $json->relaxed;
        #$json->loose;
        $json->allow_unknown;
        $json->max_depth( 4 );
        $json->max_size( 9000 );

        $temp = undef;
        eval { $temp = $json->decode( $line ) };
        if( $@ )
        {
            $data_sum{BADLINE}++;
            print( STDERR "json-decode error!! ", $@, "\n" );
            print( STDERR "Bad Line: ", $line, "\n" );
            next;
            }
        else
        {
            $linedata{BADLINE} = 0;
            }

        # Retreve our data from the decoded hash
        %linedata = (
                      'DATE_TIME' => '',
                      'EPOCH'     => $temp->{time},
                      'IPADDR'    => $temp->{client},
                      'METHOD'    => $temp->{http_method},
                      'URL'       => '',
                      'STATUS'    => $temp->{status},
                      'PROTO'     => '',
                      'HTTPHOST'  => $temp->{server},
                      'PORT'      => $temp->{dest_port},
                      'PATH'      => $temp->{uri_path},
                      'OPTIONS'   => $temp->{uri_query},
                      'BYTESIN'   => $temp->{bytes_in},
                      'BYTESOUT'  => $temp->{bytes_out},
                      'EXECTIME'  => $temp->{response_time_microseconds},
                      '2xx'       => 0,
                      '3xx'       => 0,
                      '4xx'       => 0,
                      '5xx'       => 0,
                      'USERAGENT' => $temp->{http_user_agent},
                      'IDENT'     => $temp->{ident},
                      'COOKIE'    => $temp->{cookie},
                      'REFERER'   => $temp->{http_referrer},
                      'BADLINE'   => 0,
                      'FILETYPE'  => '',
                      );

        # ipv6 cleanup
        # We can't fit the whole ipv6 address on screen, trimming to the last 4 octets, or less
        if( $linedata{IPADDR} =~ m/:/ )
        {
            # Example: 2600:3c02::f03c:92ff:feb4:914b
            #if(     $linedata{IPADDR} =~ m/([0-9a-f]{4}:[0-9a-f]{4}:[0-9a-f]{4}:[0-9a-f]{4})$/ ) { $linedata{IPADDR} = $1; }
            if(     $linedata{IPADDR} =~             m/([0-9a-f]{4}:[0-9a-f]{4}:[0-9a-f]{4})$/ ) { $linedata{IPADDR} = $1; }
            elsif(  $linedata{IPADDR} =~                         m/([0-9a-f]{4}:[0-9a-f]{4})$/ ) { $linedata{IPADDR} = $1; }
            elsif(  $linedata{IPADDR} =~                                     m/([0-9a-f]{4})$/ ) { $linedata{IPADDR} = $1; }
            }

        # Fix up some of the data
        if(    $linedata{PORT} eq '80'  ) { $linedata{PROTO} = 'http';  }
        elsif( $linedata{PORT} eq '443' ) { $linedata{PROTO} = 'https'; }
        #$linedata{URL} = $linedata{PROTO} . '://' . $linedata{HTTPHOST} . ':' . $linedata{PORT} . $linedata{PATH} . $linedata{OPTIONS};
        $linedata{URL} = $linedata{PROTO} . '://' . $linedata{HTTPHOST} . ':' . $linedata{PORT} . $linedata{PATH};
        # my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
        ( $linedata{SEC}, $linedata{MIN}, $linedata{HOUR}, $linedata{DAY}, $linedata{MON}, $linedata{YEAR} ) = ( localtime( $linedata{EPOCH} ) )[0,1,2,3,4,5];
        $linedata{YEAR} += 1900;
        $linedata{MON}  += 1;
        $linedata{COOKIE_SIZE} = length( $linedata{COOKIE} );

        # File extention type
        if( $linedata{PATH} =~ m/\.([a-zA-Z]+)$/ ) { $linedata{FILETYPE} = $1; }

        # Basic request
        $linedata{REQUEST} = $linedata{IPADDR} . ' ' . $linedata{METHOD} . ' ' . $linedata{URL};
        }

    # Convert log time to epoch time
    if( defined( $months{"$linedata{MON}"} ) ) { $linedata{MON} = $months{"$linedata{MON}"}; }
    else { $linedata{MON} = 12; }

    # Some Debugging
    if( $conf{DEBUG} > 1 ) { print( "Line Data: ", Dumper( \%linedata ),"\n" ); }

    # Discard unwanted data
    if( $linedata{HTTPHOST} eq '-' ) { next; } # F5 website up checks

    # Remove these file types
    if( ! $conf{ALLOW_CSSJS} and ( $linedata{FILETYPE} ne '' ) )
    {
        if( grep { m/^$linedata{FILETYPE}$/ } @{$conf{WEBFILES}} ) { next; }
        }
    if( ! $conf{ALLOW_IMAGES} and ( $linedata{FILETYPE} ne '' ) )
    {
        if( grep { m/^$linedata{FILETYPE}$/ } @{$conf{IMAGES}} ) { next; }
        }

    # Limit data
    if( $conf{LIMITIP}   ) { if( $linedata{IPADDR} ne $conf{LIMITIP}   ) { next; } }
    if( $conf{LIMITHOUR} ) { if( $linedata{HOUR}   != $conf{LIMITHOUR} ) { next; } }

    # Ignore these IPs
    if( ! $conf{SHOW_KNOWN_IPS} ) { if( grep { m/^$linedata{IPADDR}$/ } @{$conf{KNOWN_IP_LIST}} ) { next; } }

    # Diplay the line
    if( $conf{VERBOSE} )
    {
        printf( "Line: %4u-%02u-%02u %02u:%02u:%02u %-$conf{IP_WIDTH}s %-4u %-6s %-6s %-8s %-7s %-.$conf{URLWIDTH}s\n",
               $linedata{YEAR},
               $linedata{MON},
               $linedata{DAY},
               $linedata{HOUR},
               $linedata{MIN},
               $linedata{SEC},
               $linedata{IPADDR},
               $linedata{STATUS},
               byte_size( $linedata{BYTESIN} ),
               byte_size($linedata{BYTESOUT} ),
               time_size( $linedata{EXECTIME} ),
               $linedata{METHOD},
               $linedata{URL}
               );
        }

    # Index our data
    if ( $conf{REPORT_SUM} )
    {
        # Summarize the data by date/time down to the minute
        $data_sum{TOTAL}++;
        $data_sum{URLS}->{$linedata{URL}}++;
        $data_sum{STATUS}->{$linedata{STATUS}}++;
        $data_sum{IPADDR}->{$linedata{IPADDR}}++;
        $data_sum{USERAGENT}->{$linedata{USERAGENT}}++;
        $data_sum{BYTESIN}  += $linedata{BYTESIN};
        $data_sum{BYTESOUT} += $linedata{BYTESOUT};
        $data_sum{EXECTIME} += $linedata{EXECTIME};
        $data_sum{REQUESTS}->{$linedata{REQUEST}}++;

        # Get exectime high
        if( ! exists( $data_sum{EXECTIMEHIGH} ) )              { $data_sum{EXECTIMEHIGH} = $linedata{EXECTIME}; }
        elsif( $linedata{EXECTIME} > $data_sum{EXECTIMEHIGH} ) { $data_sum{EXECTIMEHIGH} = $linedata{EXECTIME}; }

        # Get bytes in high
        if( ! exists( $data_sum{BYTESINHIGH} ) )               { $data_sum{BYTESINHIGH} = $linedata{BYTESIN}; }
        elsif( $linedata{BYTESIN} > $data_sum{BYTESINHIGH} )   { $data_sum{BYTESINHIGH} = $linedata{BYTESIN}; }

        # Get bytes out high
        if( ! exists( $data_sum{BYTESOUTHIGH} ) )              { $data_sum{BYTESOUTHIGH} = $linedata{BYTESOUT}; }
        elsif( $linedata{BYTESOUT} > $data_sum{BYTESOUTHIGH} ) { $data_sum{BYTESOUTHIGH} = $linedata{BYTESOUT}; }
        }

    if( $conf{REPORT_DAY} )
    {
        # Summarize the data by date
        $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{TOTAL}++;
        $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{URLS}->{$linedata{URL}}++;
        $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{STATUS}->{$linedata{STATUS}}++;
        $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{IPADDR}->{$linedata{IPADDR}}++;
        $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{EXECTIME} += $linedata{EXECTIME};
        $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{BYTESIN}  += $linedata{BYTESIN};
        $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{BYTESOUT} += $linedata{BYTESOUT};

        if    ( $linedata{STATUS} =~ m/^2/ ) { $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{'2xx'}++; }
        elsif ( $linedata{STATUS} =~ m/^3/ ) { $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{'3xx'}++; }
        elsif ( $linedata{STATUS} =~ m/^4/ ) { $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{'4xx'}++; }
        elsif ( $linedata{STATUS} =~ m/^5/ ) { $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{'5xx'}++; }

        # Get exectime count high
        if( ! exists( $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{EXECTIMEHIGH} ) )
        {
            $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{EXECTIMEHIGH} = $linedata{EXECTIME};
            }
        elsif( $linedata{EXECTIME} > $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{EXECTIMEHIGH} )
        {
            $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{EXECTIMEHIGH} = $linedata{EXECTIME};
            }

        # Get bytes-in count high
        if( ! exists( $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{BYTESINHIGH} ) )
        {
            $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{BYTESINHIGH} = $linedata{BYTESIN};
            }
        elsif( $linedata{BYTESIN} < $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{BYTESINHIGH} )
        {
            $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{BYTESINHIGH} = $linedata{BYTESIN};
            }

        # Get bytes-out count high
        if( ! exists( $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{BYTESOUTHIGH} ) )
        {
            $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{BYTESOUTHIGH} = $linedata{BYTESOUT};
            }
        elsif( $linedata{BYTESOUT} > $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{BYTESOUTHIGH} )
        {
            $data_day{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{BYTESOUTHIGH} = $linedata{BYTESOUT};
            }
        }

    if( $conf{REPORT_HOUR} )
    {
        # Summarize the data by date/time down to the minute
        $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{TOTAL}++;
        $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{URLS}->{$linedata{URL}}++;
        $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{STATUS}->{$linedata{STATUS}}++;
        $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{IPADDR}->{$linedata{IPADDR}}++;
        $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{BYTESIN}  += $linedata{BYTESIN};
        $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{BYTESOUT} += $linedata{BYTESOUT};
        $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{EXECTIME} += $linedata{EXECTIME};

        if    ( $linedata{STATUS} =~ m/^2/ ) { $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{'2xx'}++; }
        elsif ( $linedata{STATUS} =~ m/^3/ ) { $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{'3xx'}++; }
        elsif ( $linedata{STATUS} =~ m/^4/ ) { $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{'4xx'}++; }
        elsif ( $linedata{STATUS} =~ m/^5/ ) { $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{'5xx'}++; }

        # Get exectime count high
        if( ! exists( $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{EXECTIMEHIGH} ) )
        {
            $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{EXECTIMEHIGH} = $linedata{EXECTIME};
            }
        elsif( $linedata{EXECTIME} > $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{EXECTIMEHIGH} )
        {
            $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{EXECTIMEHIGH} = $linedata{EXECTIME};
            }

        # Get byte-in count high
        if( ! exists( $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{BYTESINHIGH} ) )
        {
            $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{BYTESINHIGH} = $linedata{BYTESIN};
            }
        elsif( $linedata{BYTESIN} > $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{BYTESINHIGH} )
        {
            $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{BYTESINHIGH} = $linedata{BYTESIN};
            }

        # Get byte-out count high
        if( ! exists( $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{BYTESOUTHIGH} ) )
        {
            $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{BYTESOUTHIGH} = $linedata{BYTESOUT};
            }
        elsif( $linedata{BYTESOUT} > $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{BYTESOUTHIGH} )
        {
            $data_hour{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{BYTESOUTHIGH} = $linedata{BYTESOUT};
            }
        }

    if( $conf{REPORT_MIN} )
    {
        # Summarize the data by date/time down to the minute
        $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{TOTAL}++;
        $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{URLS}->{$linedata{URL}}++;
        $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{STATUS}->{$linedata{STATUS}}++;
        $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{IPADDR}->{$linedata{IPADDR}}++;
        $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{BYTESIN}  += $linedata{BYTESIN};
        $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{BYTESOUT} += $linedata{BYTESOUT};
        $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{EXECTIME} += $linedata{EXECTIME};

        if    ( $linedata{STATUS} =~ m/^2/ ) { $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{'2xx'}++; }
        elsif ( $linedata{STATUS} =~ m/^3/ ) { $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{'3xx'}++; }
        elsif ( $linedata{STATUS} =~ m/^4/ ) { $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{'4xx'}++; }
        elsif ( $linedata{STATUS} =~ m/^5/ ) { $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{'5xx'}++; }

        # Get exectime counts high
        if( ! exists( $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{EXECTIMEHIGH} ) )
        {
            $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{EXECTIMEHIGH} = $linedata{EXECTIME};
            }
        elsif( $linedata{EXECTIME} > $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{EXECTIMEHIGH} )
        {
            $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{EXECTIMEHIGH} = $linedata{EXECTIME};
            }

        # Get byte-in counts high
        if( ! exists( $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{BYTESINHIGH} ) )
        {
            $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{BYTESINHIGH} = $linedata{BYTESIN};
            }
        elsif( $linedata{BYTESIN} > $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{BYTESINHIGH} )
        {
            $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{BYTESINHIGH} = $linedata{BYTESIN};
            }

        # Get byte-out counts high
        if( ! exists( $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{BYTESOUTHIGH} ) )
        {
            $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{BYTESOUTHIGH} = $linedata{BYTESOUT};
            }
        elsif( $linedata{BYTESOUT} > $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{BYTESOUTHIGH} )
        {
            $data_min{$linedata{YEAR}}->{$linedata{MON}}->{$linedata{DAY}}->{$linedata{HOUR}}->{$linedata{MIN}}->{BYTESOUTHIGH} = $linedata{BYTESOUT};
            }
        }

    if( $conf{REPORT_URL} )
    {
        $data_url{$linedata{URL}}->{TOTAL}++;
        $data_url{$linedata{URL}}->{URLS}->{$linedata{URL}}++;
        $data_url{$linedata{URL}}->{IPADDR}->{$linedata{IPADDR}}++;
        $data_url{$linedata{URL}}->{STATUS}->{$linedata{STATUS}}++;
        $data_url{$linedata{URL}}->{BYTESIN}  += $linedata{BYTESIN};
        $data_url{$linedata{URL}}->{BYTESOUT} += $linedata{BYTESOUT};
        $data_url{$linedata{URL}}->{EXECTIME} += $linedata{EXECTIME};

        # Get exectime counts
        if( ! exists( $data_url{$linedata{URL}}->{EXECTIMEHIGH} ) )
        {
            $data_url{$linedata{URL}}->{EXECTIMEHIGH} = $linedata{EXECTIME};
            }
        elsif( $linedata{EXECTIME} > $data_url{$linedata{URL}}->{EXECTIMEHIGH} )
        {
            $data_url{$linedata{URL}}->{EXECTIMEHIGH} = $linedata{EXECTIME};
            }

        # Get byte-in count high
        if( ! exists( $data_url{$linedata{URL}}->{BYTESINHIGH} ) )
        {
            $data_url{$linedata{URL}}->{BYTESINHIGH} = $linedata{BYTESIN};
            }
        elsif( $linedata{BYTESIN} > $data_url{$linedata{URL}}->{BYTESINHIGH} )
        {
            $data_url{$linedata{URL}}->{BYTESINHIGH} = $linedata{BYTESIN};
            }

        # Get byte-out count high
        if( ! exists( $data_url{$linedata{URL}}->{BYTESOUTHIGH} ) )
        {
            $data_url{$linedata{URL}}->{BYTESOUTHIGH} = $linedata{BYTESOUT};
            }
        elsif( $linedata{BYTESOUT} > $data_url{$linedata{URL}}->{BYTESOUTHIGH} )
        {
            $data_url{$linedata{URL}}->{BYTESOUTHIGH} = $linedata{BYTESOUT};
            }

        # Get status code summaries
        $data_url{$linedata{URL}}->{STATUS}->{$linedata{STATUS}}++;
        if    ( $linedata{STATUS} =~ m/^2/   ) { $data_url{$linedata{URL}}->{'2xx'}++; }
        elsif ( $linedata{STATUS} =~ m/^3/   ) { $data_url{$linedata{URL}}->{'3xx'}++; }
        elsif ( $linedata{STATUS} =~ m/^4/   ) { $data_url{$linedata{URL}}->{'4xx'}++; }
        elsif ( $linedata{STATUS} =~ m/^400/ ) { $data_url{$linedata{URL}}->{'400'}++; }
        elsif ( $linedata{STATUS} =~ m/^401/ ) { $data_url{$linedata{URL}}->{'401'}++; }
        elsif ( $linedata{STATUS} =~ m/^403/ ) { $data_url{$linedata{URL}}->{'403'}++; }
        elsif ( $linedata{STATUS} =~ m/^404/ ) { $data_url{$linedata{URL}}->{'404'}++; }
        elsif ( $linedata{STATUS} =~ m/^5/   ) { $data_url{$linedata{URL}}->{'5xx'}++; }
        }

    if( $conf{REPORT_STAT} )
    {
        $data_stat{$linedata{STATUS}}->{TOTAL}++;
        $data_stat{$linedata{STATUS}}->{URLS}->{$linedata{URL}}++;
        $data_stat{$linedata{STATUS}}->{IPADDR}->{$linedata{IPADDR}}++;
        #$data_stat{$linedata{STATUS}}->{USERAGENT}->{$linedata{USERAGENT}}++;
        $data_stat{$linedata{STATUS}}->{BYTESIN}  += $linedata{BYTESIN};
        $data_stat{$linedata{STATUS}}->{BYTESOUT} += $linedata{BYTESOUT};
        $data_stat{$linedata{STATUS}}->{EXECTIME} += $linedata{EXECTIME};

        # Get exectime counts
        if( ! exists( $data_stat{$linedata{STATUS}}->{EXECTIMEHIGH} ) )
        {
            $data_stat{$linedata{STATUS}}->{EXECTIMEHIGH} = $linedata{EXECTIME};
            }
        elsif( $linedata{EXECTIME} > $data_stat{$linedata{STATUS}}->{EXECTIMEHIGH} )
        {
            $data_stat{$linedata{STATUS}}->{EXECTIMEHIGH} = $linedata{EXECTIME};
            }

        # Get byte-in count high
        if( ! exists( $data_stat{$linedata{STATUS}}->{BYTESINHIGH} ) )
        {
            $data_stat{$linedata{STATUS}}->{BYTESINHIGH} = $linedata{BYTESIN};
            }
        elsif( $linedata{BYTESIN} > $data_stat{$linedata{STATUS}}->{BYTESINHIGH} )
        {
            $data_stat{$linedata{STATUS}}->{BYTESINHIGH} = $linedata{BYTESIN};
            }

        # Get byte-out count high
        if( ! exists( $data_stat{$linedata{STATUS}}->{BYTESOUTHIGH} ) )
        {
            $data_stat{$linedata{STATUS}}->{BYTESOUTHIGH} = $linedata{BYTESOUT};
            }
        elsif( $linedata{BYTESOUT} > $data_stat{$linedata{STATUS}}->{BYTESOUTHIGH} )
        {
            $data_stat{$linedata{STATUS}}->{BYTESOUTHIGH} = $linedata{BYTESOUT};
            }
        }

    if( $conf{REPORT_IP} )
    {
        $data_ip{$linedata{IPADDR}}->{TOTAL}++;
        $data_ip{$linedata{IPADDR}}->{URLS}->{$linedata{URL}}++;
        $data_ip{$linedata{IPADDR}}->{USERAGENT}->{$linedata{USERAGENT}}++;
        $data_ip{$linedata{IPADDR}}->{BYTESIN}  += $linedata{BYTESIN};
        $data_ip{$linedata{IPADDR}}->{BYTESOUT} += $linedata{BYTESOUT};
        $data_ip{$linedata{IPADDR}}->{EXECTIME} += $linedata{EXECTIME};

        # Get exectime counts
        if( ! exists( $data_ip{$linedata{IPADDR}}->{EXECTIMEHIGH} ) )
        {
            $data_ip{$linedata{IPADDR}}->{EXECTIMEHIGH} = $linedata{EXECTIME};
            }
        elsif( $linedata{EXECTIME} > $data_ip{$linedata{IPADDR}}->{EXECTIMEHIGH} )
        {
            $data_ip{$linedata{IPADDR}}->{EXECTIMEHIGH} = $linedata{EXECTIME};
            }

        # Get byte-in count high
        if( ! exists( $data_ip{$linedata{IPADDR}}->{BYTESINHIGH} ) )
        {
            $data_ip{$linedata{IPADDR}}->{BYTESINHIGH} = $linedata{BYTESIN};
            }
        elsif( $linedata{BYTESIN} > $data_ip{$linedata{IPADDR}}->{BYTESINHIGH} )
        {
            $data_ip{$linedata{IPADDR}}->{BYTESINHIGH} = $linedata{BYTESIN};
            }

        # Get byte-out count high
        if( ! exists( $data_ip{$linedata{IPADDR}}->{BYTESOUTHIGH} ) )
        {
            $data_ip{$linedata{IPADDR}}->{BYTESOUTHIGH} = $linedata{BYTESOUT};
            }
        elsif( $linedata{BYTESOUT} < $data_ip{$linedata{IPADDR}}->{BYTESOUTHIGH} )
        {
            $data_ip{$linedata{IPADDR}}->{BYTESOUTHIGH} = $linedata{BYTESOUT};
            }

        # Get status code summaries
        $data_ip{$linedata{IPADDR}}->{STATUS}->{$linedata{STATUS}}++;
        if    ( $linedata{STATUS} =~ m/^2/ ) { $data_ip{$linedata{IPADDR}}->{'2xx'}++; }
        elsif ( $linedata{STATUS} =~ m/^3/ ) { $data_ip{$linedata{IPADDR}}->{'3xx'}++; }
        elsif ( $linedata{STATUS} =~ m/^4/ ) { $data_ip{$linedata{IPADDR}}->{'4xx'}++; }
        elsif ( $linedata{STATUS} =~ m/^5/ ) { $data_ip{$linedata{IPADDR}}->{'5xx'}++; }
        }

    if( $conf{REPORT_CODES} )
    {
        $data_codes{$linedata{URL}}->{COUNTS}->{TOTAL}++;
        $data_codes{$linedata{URL}}->{CODES}->{$linedata{STATUS}}++;
        $data_codes{$linedata{URL}}->{IPADDR}->{$linedata{IPADDR}}++;
        if( $linedata{STATUS} =~ m/^2/ ) { $data_codes{$linedata{URL}}->{COUNTS}->{'2xx'}++; }
        if( $linedata{STATUS} =~ m/^3/ ) { $data_codes{$linedata{URL}}->{COUNTS}->{'3xx'}++; }
        if( $linedata{STATUS} =~ m/^4/ ) { $data_codes{$linedata{URL}}->{COUNTS}->{'4xx'}++; }
        if( $linedata{STATUS} =~ m/^5/ ) { $data_codes{$linedata{URL}}->{COUNTS}->{'5xx'}++; }
        if( $linedata{STATUS} =~ m/^[45]/ ) { $data_codes{$linedata{URL}}->{COUNTS}->{'ERR'}++; }
        }
    }

## Reporting ##

#if(    $sort =~ m/^In-Total$/i  ) { $sort = 'BYTESIN';      }
#elsif( $sort =~ m/^In-Avg$/i    ) { $sort = 'BYTESINAVG';   }
#elsif( $sort =~ m/^In-High$/i   ) { $sort = 'BYTESINHIGH';  }
#elsif( $sort =~ m/^Out-Total$/i ) { $sort = 'BYTESOUT';     }
#elsif( $sort =~ m/^Out-Avg$/i   ) { $sort = 'BYTESOUTAVG';  }
#elsif( $sort =~ m/^Out-High$/i  ) { $sort = 'BYTESOUTHIGH'; }
#elsif( $sort =~ m/^Exec-Avg$/i  ) { $sort = 'EXECTIMEAVG';  }
#elsif( $sort =~ m/^Exec-High$/i ) { $sort = 'EXECTIMEHIGH'; }

if( $conf{REPORT_SUM}   )  { report_sum(   'DEFAULT' );  print( "\n" ); }
if( $conf{REPORT_DAY}   )  { report_day(   'TIME'    );  print( "\n" ); }
if( $conf{REPORT_HOUR}  )  { report_hour(  'TIME'    );  print( "\n" ); }
if( $conf{REPORT_MIN}   )  { report_min(   'TIME'    );  print( "\n" ); }
if( $conf{REPORT_STAT}  )  { report_stat(  'DEFAULT' );  print( "\n" ); }
if( $conf{REPORT_IP}    )  { foreach my $sort ( split( ',', $conf{SORT} ) ) { report_ip(    $sort ); print( "\n" ); } }
if( $conf{REPORT_URL}   )  { foreach my $sort ( split( ',', $conf{SORT} ) ) { report_url(   $sort ); print( "\n" ); } }
if( $conf{REPORT_CODES} )  { foreach my $sort ( split( ',', $conf{SORT} ) ) { report_codes( $sort ); print( "\n" ); } }

###################################################################################################
# End

exit(0);

###################################################################################################
# Functions

#################################################
# Summary Report
sub report_sum
{
    ## Variables ##

    my $show_count = 0;
    my $sort = $_[0];
    if( $sort eq '' ) { $sort = 'DEFAULT'; }

    ## Main ##

    # Debugging
    if( $conf{DEBUG} ) { print( "Sum data: ", Dumper( \%data_sum ),"\n" ); }

    if( ! defined( $data_sum{BADLINE} ) ) { $data_sum{BADLINE} = 0; }

    if( grep { m/^${sort}$/ } qw( DEFAULT ) )
    {
        printf( "############################################################################################################\n" );
        printf( "# Web Log Summary, Sorted by: %s, Limit: %u, Max-width: %u, WebFiles: %s, Images: %s, Known-IPs: %s\n", $sort, $conf{LIMIT}, $conf{URLWIDTH}, $conf{ALLOW_CSSJS}, $conf{ALLOW_IMAGES}, $conf{SHOW_KNOWN_IPS} );
        printf( "############################################################################################################\n" );
        printf( "  Requests:  %u\n", $data_sum{TOTAL} );
        printf( "  Bytes-In:  Total: %-6s Avg: %-6s High: %-6s\n", byte_size( $data_sum{BYTESIN}  ), byte_size( ( $data_sum{BYTESIN}  / $data_sum{TOTAL} ) ), byte_size( $data_sum{BYTESINHIGH}  ) );
        printf( "  Bytes-Out: Total: %-6s Avg: %-6s High: %-6s\n", byte_size( $data_sum{BYTESOUT} ), byte_size( ( $data_sum{BYTESOUT} / $data_sum{TOTAL} ) ), byte_size( $data_sum{BYTESOUTHIGH} ) );
        printf( "  ExecTime:  Total: %-6s Avg: %-6s High: %-6s\n", time_size( $data_sum{EXECTIME} ), time_size( ( $data_sum{EXECTIME} / $data_sum{TOTAL} ) ), time_size( $data_sum{EXECTIMEHIGH} ) );
        printf( "  Badlines:  %-6u\n", $data_sum{BADLINE} );

        # IP Addresses
        printf( "    IP Addresses: (top %s)\n", $conf{LIMIT} );
        printf( "      %-6s %-$conf{IP_WIDTH}s\n", 'Count', 'IPAddress' );
        $show_count = 0;
        foreach my $ipaddr ( sort { $data_sum{IPADDR}->{$b} <=> $data_sum{IPADDR}->{$a} } keys( $data_sum{IPADDR} ) )
        {
            $show_count++;
            printf( "      %-6u %-$conf{IP_WIDTH}s \n", $data_sum{IPADDR}->{$ipaddr}, $ipaddr );
            if( $show_count >= $conf{LIMIT} ) { last; }
            }

        # URLs
        printf( "    URLs: (top %s)\n", $conf{LIMIT} );
        printf( "      %-6s %-$conf{URLWIDTH}.$conf{URLWIDTH}s\n", 'Count', 'URL' );
        $show_count = 0;
        foreach my $url ( sort { $data_sum{URLS}->{$b} <=> $data_sum{URLS}->{$a} } keys( $data_sum{URLS} ) )
        {
            $show_count++;
            printf( "      %-6u %-$conf{URLWIDTH}.$conf{URLWIDTH}s\n", $data_sum{URLS}->{$url}, $url );
            if( $show_count >= $conf{LIMIT} ) { last; }
            }

        # UserAgents
        printf( "    UserAgents: (top %s)\n", $conf{LIMIT} );
        printf( "      %-6s %-$conf{URLWIDTH}.$conf{URLWIDTH}s\n", 'Count', 'UserAgent' );
        $show_count = 0;
        foreach my $useragent ( sort { $data_sum{USERAGENT}->{$a} <=> $data_sum{USERAGENT}->{$b} } keys( $data_sum{USERAGENT} ) )
        {
            $show_count++;
            printf( "      %-6u %-$conf{URLWIDTH}.$conf{URLWIDTH}s\n", $data_sum{USERAGENT}->{$useragent}, $useragent );
            if( $show_count >= $conf{LIMIT} ) { last; }
            }

        # Status
        my @stats;
        printf( "    Status Codes:\n" );
        printf( "      %-6s %-6s\n", 'Status', 'Count' );
        foreach my $stat ( keys( $data_sum{STATUS} ) )
        {
            push( @stats, $stat );
            }
        foreach my $stat ( sort( @stats ) )
        {
            printf( "      %-6s %-6u\n", $stat, $data_sum{STATUS}->{$stat} );
            }

        # Requests
        printf( "    Requests: (top %s)\n", $conf{LIMIT} );
        printf( "      %-6s %-$conf{URLWIDTH}.$conf{URLWIDTH}s\n", 'Count', 'Request' );
        $show_count = 0;
        foreach my $request ( sort { $data_sum{REQUESTS}->{$b} <=> $data_sum{REQUESTS}->{$a} } keys( $data_sum{REQUESTS} ) )
        {
            $show_count++;
            #my ( $request_ip, $request_method, $request_url ) = ( split( ' ', $request ) );
            printf( "      %-6u %-$conf{IP_WIDTH}s %-8s %-$conf{URLWIDTH}.$conf{URLWIDTH}s\n", $data_sum{REQUESTS}->{$request}, ( split( ' ', $request ) ) );
            if( $show_count >= $conf{LIMIT} ) { last; }
            }
        }
    else
    {
        if( $conf{VERBOSE} ) { print( "Invalid sorting type for this report: ${sort}\n" ); }
        }

    ## Return ##
    $conf{REPORTDONE}++;
    return;
    }

#################################################
# Daily Report
sub report_day
{
    ## Variables ##

    my $sort = $_[0];
    if( $sort eq 'DEFAULT' ) { $sort = 'TIME'; }

    ## Main ##

    # Debugging
    if( $conf{DEBUG} ) { print( "Day data: ", Dumper( \%data_day ),"\n" ); }

    # Clean up our data, compute the averages, compute counts
    # The averages need computes in advance so we can sort on them
    foreach my $year ( keys( %data_day ) )
    {
        foreach my $month ( keys( $data_day{$year} ) )
        {
            foreach my $day ( keys( $data_day{$year}->{$month} ) )
            {
                $data_day{$year}->{$month}->{$day}->{EXECTIMEAVG} = $data_day{$year}->{$month}->{$day}->{EXECTIME} / $data_day{$year}->{$month}->{$day}->{TOTAL};
                $data_day{$year}->{$month}->{$day}->{BYTESINAVG}  = $data_day{$year}->{$month}->{$day}->{BYTESIN}  / $data_day{$year}->{$month}->{$day}->{TOTAL};
                $data_day{$year}->{$month}->{$day}->{BYTESOUTAVG} = $data_day{$year}->{$month}->{$day}->{BYTESOUT} / $data_day{$year}->{$month}->{$day}->{TOTAL};
                $data_day{$year}->{$month}->{$day}->{URLCOUNT}    = keys( %{ $data_day{$year}->{$month}->{$day}->{URLS} } );
                $data_day{$year}->{$month}->{$day}->{IPCOUNT}     = keys( %{ $data_day{$year}->{$month}->{$day}->{IPADDR} } );

                # Fix non-existant values
                if( ! exists( $data_day{$year}->{$month}->{$day}->{'2xx'} ) ) { $data_day{$year}->{$month}->{$day}->{'2xx'} = 0; }
                if( ! exists( $data_day{$year}->{$month}->{$day}->{'3xx'} ) ) { $data_day{$year}->{$month}->{$day}->{'3xx'} = 0; }
                if( ! exists( $data_day{$year}->{$month}->{$day}->{'4xx'} ) ) { $data_day{$year}->{$month}->{$day}->{'4xx'} = 0; }
                if( ! exists( $data_day{$year}->{$month}->{$day}->{'5xx'} ) ) { $data_day{$year}->{$month}->{$day}->{'5xx'} = 0; }
                }
            }
        }

    if( grep { m/^${sort}$/ } qw( TIME ) )
    {
        # Print the header
        printf( "############################################################################################################\n" );
        printf( "# Per Day Summary, Sorted by: %s, Limit: %u, Max-width: %u, WebFiles: %s, Images: %s, Known-IPs: %s\n", $sort, $conf{LIMIT}, $conf{URLWIDTH}, $conf{ALLOW_CSSJS}, $conf{ALLOW_IMAGES}, $conf{SHOW_KNOWN_IPS} );
        printf( "############################################################################################################\n" );
        printf( "%-10.10s %-9s %-8s %-7s %-7s %-9s %-7s %-8s %-8s %-9s %-6s %-5s %-5s %-5s %-5s %-5s\n",
                'Date', 'Count', 'In-Total', 'In-Avg', 'In-High', 'Out-Total', 'Out-Avg', 'Out-High', 'Exec-Avg', 'Exec-High', '2xx', '3xx', '4xx', '5xx', 'URLs', 'IPs' );

        foreach my $year ( sort { $data_day{$a} <=> $data_day{$b} } keys( %data_day ) )
        {
            foreach my $month ( sort { $data_day{$year}->{$a} <=> $data_day{$year}->{$b} } keys( $data_day{$year} ) )
            {
                foreach my $day ( sort { $data_day{$year}->{$month}->{$a} <=> $data_day{$year}->{$month}->{$b} } keys( $data_day{$year}->{$month} ) )
                {
                    #print( Dumper( $data_day{$year}->{$month}->{$day} ), "\n" );
                    printf( "%4u-%02u-%02u %-9u %-8s %-7s %-7s %-9s %-7s %-8s %-8s %-9s %-6u %-5u %-5u %-5u %-5u %-5u\n",
                            $year,
                            $month,
                            $day,
                            $data_day{$year}->{$month}->{$day}->{TOTAL},
                            byte_size( $data_day{$year}->{$month}->{$day}->{BYTESIN} ),
                            byte_size( $data_day{$year}->{$month}->{$day}->{BYTESINAVG} ),
                            byte_size( $data_day{$year}->{$month}->{$day}->{BYTESINHIGH} ),
                            byte_size( $data_day{$year}->{$month}->{$day}->{BYTESOUT} ),
                            byte_size( $data_day{$year}->{$month}->{$day}->{BYTESOUTAVG} ),
                            byte_size( $data_day{$year}->{$month}->{$day}->{BYTESOUTHIGH} ),
                            time_size( $data_day{$year}->{$month}->{$day}->{EXECTIMEAVG} ),
                            time_size( $data_day{$year}->{$month}->{$day}->{EXECTIMEHIGH} ),
                            $data_day{$year}->{$month}->{$day}->{'2xx'},
                            $data_day{$year}->{$month}->{$day}->{'3xx'},
                            $data_day{$year}->{$month}->{$day}->{'4xx'},
                            $data_day{$year}->{$month}->{$day}->{'5xx'},
                            $data_day{$year}->{$month}->{$day}->{URLCOUNT},
                            $data_day{$year}->{$month}->{$day}->{IPCOUNT},
                            );
                    }
                }
            }
        }
    else
    {
        if( $conf{VERBOSE} ) { print( "Invalid sorting type for this report: ${sort}\n" ); }
        }

    ## Return ##
    return;
    }

#################################################
# Hourly Report

sub report_hour
{
    ## Variables ##

    my $sort = $_[0];
    if( $sort eq 'DEFAULT' ) { $sort = 'TIME'; }

    ## Main ##

    # Debugging
    if( $conf{DEBUG} ) { print( "Minute data: ", Dumper( \%data_min ),"\n" ); }

    # Clean up our data, compute the averages, compute counts
    # The averages need computes in advance so we can sort on them
    foreach my $year ( keys( %data_hour ) )
    {
        foreach my $month ( keys( $data_hour{$year} ) )
        {
            foreach my $day ( keys( $data_hour{$year}->{$month} ) )
            {
                foreach my $hour ( keys( $data_hour{$year}->{$month}->{$day} ) )
                {
                    $data_hour{$year}->{$month}->{$day}->{$hour}->{EXECTIMEAVG} = $data_hour{$year}->{$month}->{$day}->{$hour}->{EXECTIME} / $data_hour{$year}->{$month}->{$day}->{$hour}->{TOTAL};
                    $data_hour{$year}->{$month}->{$day}->{$hour}->{BYTESINAVG}  = $data_hour{$year}->{$month}->{$day}->{$hour}->{BYTESIN}  / $data_hour{$year}->{$month}->{$day}->{$hour}->{TOTAL};
                    $data_hour{$year}->{$month}->{$day}->{$hour}->{BYTESOUTAVG} = $data_hour{$year}->{$month}->{$day}->{$hour}->{BYTESOUT} / $data_hour{$year}->{$month}->{$day}->{$hour}->{TOTAL};
                    $data_hour{$year}->{$month}->{$day}->{$hour}->{URLCOUNT}    = keys( %{ $data_hour{$year}->{$month}->{$day}->{$hour}->{URLS} } );
                    $data_hour{$year}->{$month}->{$day}->{$hour}->{IPCOUNT}     = keys( %{ $data_hour{$year}->{$month}->{$day}->{$hour}->{IPADDR} } );

                    # Fix non-existant values
                    if( ! exists( $data_hour{$year}->{$month}->{$day}->{$hour}->{'2xx'} ) ) { $data_hour{$year}->{$month}->{$day}->{$hour}->{'2xx'} = 0; }
                    if( ! exists( $data_hour{$year}->{$month}->{$day}->{$hour}->{'3xx'} ) ) { $data_hour{$year}->{$month}->{$day}->{$hour}->{'3xx'} = 0; }
                    if( ! exists( $data_hour{$year}->{$month}->{$day}->{$hour}->{'4xx'} ) ) { $data_hour{$year}->{$month}->{$day}->{$hour}->{'4xx'} = 0; }
                    if( ! exists( $data_hour{$year}->{$month}->{$day}->{$hour}->{'5xx'} ) ) { $data_hour{$year}->{$month}->{$day}->{$hour}->{'5xx'} = 0; }
                    }
                }
            }
        }

    if( grep { m/^${sort}$/ } qw( TIME ) )
    {
        # Print the header
        printf( "############################################################################################################\n" );
        printf( "# Per Hour Summary, Sorted by: %s, Limit: %u, Max-width: %u, WebFiles: %s, Images: %s, Known-IPs: %s\n", $sort, $conf{LIMIT}, $conf{URLWIDTH}, $conf{ALLOW_CSSJS}, $conf{ALLOW_IMAGES}, $conf{SHOW_KNOWN_IPS}  );
        printf( "############################################################################################################\n" );
        printf( "%-10.10s %-4s %-8s %-8s %-7s %-7s %-9s %-7s %-8s %-8s %-9s %-6s %-5s %-5s %-5s %-5s %-5s\n",
                'Date', 'Hour', 'Count', 'In-Total', 'In-Avg', 'In-High', 'Out-Total', 'Out-Avg', 'Out-High', 'Exec-Avg', 'Exec-High', '2xx', '3xx', '4xx', '5xx', 'URLs', 'IPs' );

        foreach my $year ( sort { $data_hour{$a} <=> $data_hour{$b} } keys( %data_hour ) )
        {
            foreach my $month ( sort { $data_hour{$year}->{$a} <=> $data_hour{$year}->{$b} } keys( $data_hour{$year} ) )
            {
                foreach my $day ( sort { $data_hour{$year}->{$month}->{$a} <=> $data_hour{$year}->{$month}->{$b} } keys( $data_hour{$year}->{$month} ) )
                {
                    foreach my $hour ( sort { $data_hour{$year}->{$month}->{$day}->{$a} <=> $data_hour{$year}->{$month}->{$day}->{$b} } keys( $data_hour{$year}->{$month}->{$day} ) )
                    {
                        #print( Dumper( $data_hour{$year}->{$month}->{$day}->{$hour} ), "\n" );
                        printf( "%4u-%02u-%02u %-04u %-8u %-8s %-7s %-7s %-9s %-7s %-8s %-8s %-9s %-6u %-5u %-5u %-5u %-5u %-5u\n",
                                $year,
                                $month,
                                $day,
                                $hour,
                                $data_hour{$year}->{$month}->{$day}->{$hour}->{TOTAL},
                                byte_size( $data_hour{$year}->{$month}->{$day}->{$hour}->{BYTESIN} ),
                                byte_size( $data_hour{$year}->{$month}->{$day}->{$hour}->{BYTESINAVG} ),
                                byte_size( $data_hour{$year}->{$month}->{$day}->{$hour}->{BYTESINHIGH} ),
                                byte_size( $data_hour{$year}->{$month}->{$day}->{$hour}->{BYTESOUT} ),
                                byte_size( $data_hour{$year}->{$month}->{$day}->{$hour}->{BYTESOUTAVG} ),
                                byte_size( $data_hour{$year}->{$month}->{$day}->{$hour}->{BYTESOUTHIGH} ),
                                time_size( $data_hour{$year}->{$month}->{$day}->{$hour}->{EXECTIMEAVG} ),
                                time_size( $data_hour{$year}->{$month}->{$day}->{$hour}->{EXECTIMEHIGH} ),
                                $data_hour{$year}->{$month}->{$day}->{$hour}->{'2xx'},
                                $data_hour{$year}->{$month}->{$day}->{$hour}->{'3xx'},
                                $data_hour{$year}->{$month}->{$day}->{$hour}->{'4xx'},
                                $data_hour{$year}->{$month}->{$day}->{$hour}->{'5xx'},
                                $data_hour{$year}->{$month}->{$day}->{$hour}->{URLCOUNT},
                                $data_hour{$year}->{$month}->{$day}->{$hour}->{IPCOUNT},
                                );
                        }
                    }
                }
            }
        }
    else
    {
        if( $conf{VERBOSE} ) { print( "Invalid sorting type for this report: ${sort}\n" ); }
        }

    ## Return ##
    return;
    }

#################################################
# Minute Report

sub report_min
{
    ## Variables ##

    my $sort = $_[0];
    if( $sort eq 'DEFAULT' ) { $sort = 'TIME'; }

    ## Main ##

    # Debugging
    if( $conf{DEBUG} ) { print( "Minute data: ", Dumper( \%data_min ),"\n" ); }

    # Clean up our data, compute the averages, compute counts
    # The averages need computes in advance so we can sort on them
    foreach my $year ( keys( %data_min ) )
    {
        foreach my $month ( keys( $data_min{$year} ) )
        {
            foreach my $day ( keys( $data_min{$year}->{$month} ) )
            {
                foreach my $hour ( keys( $data_min{$year}->{$month}->{$day} ) )
                {
                    foreach my $min ( keys( $data_min{$year}->{$month}->{$day}->{$hour} ) )
                    {
                        $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{EXECTIMEAVG} = $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{EXECTIME} / $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{TOTAL};
                        $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{BYTESINAVG}  = $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{BYTESIN}  / $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{TOTAL};
                        $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{BYTESOUTAVG} = $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{BYTESOUT} / $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{TOTAL};
                        $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{URLCOUNT}    = keys( %{ $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{URLS} } );
                        $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{IPCOUNT}     = keys( %{ $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{IPADDR} } );

                        # Fix non-existant values
                        if( ! exists( $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{'2xx'} ) ) { $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{'2xx'} = 0; }
                        if( ! exists( $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{'3xx'} ) ) { $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{'3xx'} = 0; }
                        if( ! exists( $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{'4xx'} ) ) { $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{'4xx'} = 0; }
                        if( ! exists( $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{'5xx'} ) ) { $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{'5xx'} = 0; }
                        }
                    }
                }
            }
        }

    if( grep { m/^${sort}$/ } qw( TIME ) )
    {
        # Print the header
        printf( "############################################################################################################\n" );
        printf( "# Per Minute Summary, Sorted by: %s, Limit: %u, Max-width: %u, WebFiles: %s, Images: %s, Known-IPs: %s\n", $sort, $conf{LIMIT}, $conf{URLWIDTH}, $conf{ALLOW_CSSJS}, $conf{ALLOW_IMAGES}, $conf{SHOW_KNOWN_IPS} );
        printf( "############################################################################################################\n" );
        printf( "%-10.10s %-4s %-4s %-6s %-8s %-7s %-7s %-9s %-7s %-8s %-8s %-9s %-6s %-5s %-5s %-5s %-5s %-5s\n",
                'Date', 'Hour', 'Min', 'Count', 'In-Total', 'In-Avg', 'In-High', 'Out-Total', 'Out-Avg', 'Out-High', 'Exec-Avg', 'Exec-High', '2xx', '3xx', '4xx', '5xx', 'URLs', 'IPs' );

        foreach my $year ( sort { $data_min{$a} <=> $data_min{$b} } keys( %data_min ) )
        {
            foreach my $month ( sort { $data_min{$year}->{$a} <=> $data_min{$year}->{$b} } keys( $data_min{$year} ) )
            {
                foreach my $day ( sort { $data_min{$year}->{$month}->{$a} <=> $data_min{$year}->{$month}->{$b} } keys( $data_min{$year}->{$month} ) )
                {
                    foreach my $hour ( sort { $data_min{$year}->{$month}->{$day}->{$a} <=> $data_min{$year}->{$month}->{$day}->{$b} } keys( $data_min{$year}->{$month}->{$day} ) )
                    {
                        foreach my $min ( sort { $data_min{$year}->{$month}->{$day}->{$hour}->{$a} <=> $data_min{$year}->{$month}->{$day}->{$hour}->{$b} } keys( $data_min{$year}->{$month}->{$day}->{$hour} ) )
                        {
                            #print( Dumper( $data_min{$year}->{$month}->{$day}->{$hour}->{$min} ), "\n" );
                            printf( "%4u-%02u-%02u %-04u %-04u %-6u %-8s %-7s %-7s %-9s %-7s %-8s %-8s %-9s %-6u %-5u %-5u %-5u %-5u %-5u\n",
                                    $year,
                                    $month,
                                    $day,
                                    $hour,
                                    $min,
                                    $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{TOTAL},
                                    byte_size( $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{BYTESIN} ),
                                    byte_size( $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{BYTESINAVG} ),
                                    byte_size( $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{BYTESINHIGH} ),
                                    byte_size( $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{BYTESOUT} ),
                                    byte_size( $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{BYTESOUTAVG} ),
                                    byte_size( $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{BYTESOUTHIGH} ),
                                    time_size( $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{EXECTIMEAVG} ),
                                    time_size( $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{EXECTIMEHIGH} ),
                                    $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{'2xx'},
                                    $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{'3xx'},
                                    $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{'4xx'},
                                    $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{'5xx'},
                                    $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{URLCOUNT},
                                    $data_min{$year}->{$month}->{$day}->{$hour}->{$min}->{IPCOUNT},
                                    );
                            }
                        }
                    }
                }
            }
        }
    else
    {
        if( $conf{VERBOSE} ) { print( "Invalid sorting type for this report: ${sort}\n" ); }
        }

    ## Return ##
    return;
    }

#################################################
# URL Report
sub report_url
{
    ## Variables ##

    my $show_count = 0;
    my $sort = $_[0];
    if( $sort eq 'DEFAULT' ) { $sort = 'TOTAL'; }

    ## Main ##

    # Debugging
    if( $conf{DEBUG} ) { print( "URL data: ", Dumper( \%data_url ),"\n" ); }

    # Clean up our data, compute the averages, compute counts
    # The averages need computes in advance so we can sort on them
    foreach my $url ( keys( %data_url ) )
    {
        $data_url{$url}->{EXECTIMEAVG}    = $data_url{$url}->{EXECTIME} / $data_url{$url}->{TOTAL};
        $data_url{$url}->{BYTESINAVG}     = $data_url{$url}->{BYTESIN}  / $data_url{$url}->{TOTAL};
        $data_url{$url}->{BYTESOUTAVG}    = $data_url{$url}->{BYTESOUT} / $data_url{$url}->{TOTAL};
        $data_url{$url}->{IPCOUNT}        = keys( %{ $data_url{$url}->{IPADDR} } );

        # Fix non-existant values
        if( ! exists( $data_url{$url}->{'2xx'} ) ) { $data_url{$url}->{'2xx'} = 0; }
        if( ! exists( $data_url{$url}->{'3xx'} ) ) { $data_url{$url}->{'3xx'} = 0; }
        if( ! exists( $data_url{$url}->{'4xx'} ) ) { $data_url{$url}->{'4xx'} = 0; }
        if( ! exists( $data_url{$url}->{'4xx'} ) ) { $data_url{$url}->{'4xx'} = 0; }
        if( ! exists( $data_url{$url}->{'400'} ) ) { $data_url{$url}->{'400'} = 0; }
        if( ! exists( $data_url{$url}->{'401'} ) ) { $data_url{$url}->{'401'} = 0; }
        if( ! exists( $data_url{$url}->{'403'} ) ) { $data_url{$url}->{'403'} = 0; }
        if( ! exists( $data_url{$url}->{'404'} ) ) { $data_url{$url}->{'404'} = 0; }
        if( ! exists( $data_url{$url}->{'5xx'} ) ) { $data_url{$url}->{'5xx'} = 0; }
        }

    # Each different reporting function can only handle different types of sorting
    # Make sure before sorting that a corret sorting type is provided
    if( grep { m/^${sort}$/ } qw( TOTAL BYTESIN BYTESINAVG BYTESINHIGH BYTESOUT BYTESOUTAVG BYTESOUTHIGH EXECTIMEAVG EXECTIMEHIGH 2xx 3xx 4xx 5xx IPCOUNT ) )
    {
        # Header
        printf( "############################################################################################################\n" );
        printf( "# Per URL Summary, Sorted by: %s, Limit: %u, Max-width: %u, WebFiles: %s, Images: %s, Known-IPs: %s\n", $sort, $conf{LIMIT}, $conf{URLWIDTH}, $conf{ALLOW_CSSJS}, $conf{ALLOW_IMAGES}, $conf{SHOW_KNOWN_IPS} );
        printf( "############################################################################################################\n" );
        printf( "%-7s %-8s %-7s %-7s %-9s %-7s %-8s %-8s %-9s %-7s %-4s %-4s %-4s %-4s %-4s %-4s %-4s %-5s %-.$conf{URLWIDTH}s\n",
                'Count', 'In-Total', 'In-Avg', 'In-High', 'Out-Total', 'Out-Avg', 'Out-High', 'Exec-Avg', 'Exec-High', '2xx', '3xx', '4xx', '400', '401', '403', '404', '5xx', 'IPs', 'URL' );

        foreach my $url ( sort { $data_url{$b}->{$sort} <=> $data_url{$a}->{$sort} } keys( %data_url ) )
        {
            $show_count++;
            if( $conf{DEBUG} > 2 ) { print( "Before print: ", Dumper( \$data_url{$url} ),"\n" ); }
            printf( "%-7u %-8s %-7s %-7s %-9s %-7s %-8s %-8s %-9s %-7u %-4u %-4u %-4u %-4s %-4s %-4s %-4s %-5u %-.$conf{URLWIDTH}s\n",
                $data_url{$url}->{TOTAL},
                byte_size( $data_url{$url}->{BYTESIN} ),
                byte_size( $data_url{$url}->{BYTESINAVG} ),
                byte_size( $data_url{$url}->{BYTESINHIGH} ),
                byte_size( $data_url{$url}->{BYTESOUT} ),
                byte_size( $data_url{$url}->{BYTESOUTAVG} ),
                byte_size( $data_url{$url}->{BYTESOUTHIGH} ),
                time_size( $data_url{$url}->{EXECTIMEAVG} ),
                time_size( $data_url{$url}->{EXECTIMEHIGH} ),
                $data_url{$url}->{'2xx'},
                $data_url{$url}->{'3xx'},
                $data_url{$url}->{'4xx'},
                $data_url{$url}->{'400'},
                $data_url{$url}->{'401'},
                $data_url{$url}->{'403'},
                $data_url{$url}->{'404'},
                $data_url{$url}->{'5xx'},
                $data_url{$url}->{IPCOUNT},
                $url,
                );
            if( $show_count > $conf{LIMIT} ) { last; }
            }
        }
    else
    {
        if( $conf{VERBOSE} ) { print( "Invalid sorting type for this report: ${sort}\n" ); }
        }

    ## Return ##
    return;
    }

#################################################
# Status Report
sub report_stat
{
    ## Variables ##

    my $sort = $_[0];

    ## Main ##

    # Debugging
    if( $conf{DEBUG} ) { print( "Stat data: ", Dumper( \%data_stat ),"\n" ); }

    # Clean up our data, compute the averages, compute counts
    # The averages need computes in advance so we can sort on them
    foreach my $stat ( keys( %data_stat ) )
    {
        $data_stat{$stat}->{EXECTIMEAVG} = $data_stat{$stat}->{EXECTIME} / $data_stat{$stat}->{TOTAL};
        $data_stat{$stat}->{BYTESINAVG}  = $data_stat{$stat}->{BYTESIN}  / $data_stat{$stat}->{TOTAL};
        $data_stat{$stat}->{BYTESOUTAVG} = $data_stat{$stat}->{BYTESOUT} / $data_stat{$stat}->{TOTAL};
        $data_stat{$stat}->{IPCOUNT}     = keys( %{ $data_stat{$stat}->{IPADDR} } );
        $data_stat{$stat}->{URLCOUNT}    = keys( %{ $data_stat{$stat}->{URLS} } );

        # get top url
        $data_stat{$stat}->{TOPURL} = ( sort { $data_stat{$stat}->{URLS}->{$b} <=> $data_stat{$stat}->{URLS}->{$a} } keys( $data_stat{$stat}->{URLS} ) )[0];
        }

    # Each different reporting function can only handle different types of sorting
    # Make sure before sorting that a corret sorting type is provided

    if( grep { m/^${sort}$/ } qw( DEFAULT ) )
    {
        # Header
        printf( "############################################################################################################\n" );
        printf( "# Per Status Code Summary, Sorted by: %s, Limit: %u, Max-width: %u, WebFiles: %s, Images: %s, Known-IPs: %s\n", $sort, $conf{LIMIT}, $conf{URLWIDTH}, $conf{ALLOW_CSSJS}, $conf{ALLOW_IMAGES}, $conf{SHOW_KNOWN_IPS} );
        printf( "############################################################################################################\n" );
        printf( "%-4s %-8s %-8s %-7s %-7s %-9s %-7s %-8s %-8s %-9s %-5s %-5s %-$conf{URLWIDTH}s\n",
                'Code', 'Count', 'In-Total', 'In-Avg', 'In-High', 'Out-Total', 'Out-Avg', 'Out-High', 'Exec-Avg', 'Exec-High', 'URLs', 'IPs', 'TOPURL' );

        foreach my $stat ( sort { $a <=> $b } keys( %data_stat ) )
        {
            if( $conf{DEBUG} > 2 ) { print( "Before print: ", Dumper( \$data_stat{$stat} ),"\n" ); }
            printf( "%-4u %-8u %-8s %-7s %-7s %-9s %-7s %-8s %-8s %-9s %-5u %-5u %-$conf{URLWIDTH}s\n",
                $stat,
                $data_stat{$stat}->{TOTAL},
                byte_size( $data_stat{$stat}->{BYTESIN} ),
                byte_size( $data_stat{$stat}->{BYTESINAVG} ),
                byte_size( $data_stat{$stat}->{BYTESINHIGH} ),
                byte_size( $data_stat{$stat}->{BYTESOUT} ),
                byte_size( $data_stat{$stat}->{BYTESOUTAVG} ),
                byte_size( $data_stat{$stat}->{BYTESOUTHIGH} ),
                time_size( $data_stat{$stat}->{EXECTIMEAVG} ),
                time_size( $data_stat{$stat}->{EXECTIMEHIGH} ),
                $data_stat{$stat}->{IPCOUNT},
                $data_stat{$stat}->{URLCOUNT},
                $data_stat{$stat}->{TOPURL},
                );
            }
        }
    else
    {
        if( $conf{VERBOSE} ) { print( "Invalid sorting type for this report: ${sort}\n" ); }
        }

    ## Return ##
    return;
    }

#################################################
# IPADDR Report
sub report_ip
{
    ## Variables ##

    my $show_count = 0;
    my $sort = $_[0];
    if( $sort eq 'DEFAULT' ) { $sort = 'TOTAL'; }
    $conf{IP_WIDTH} = 16; # This report can't handle the wide width

    ## Main ##

    # Debugging
    if( $conf{DEBUG} ) { print( "IP data: ", Dumper( \%data_ip ),"\n" ); }

    # Clean up our data, compute the averages, compute counts
    # The averages need computes in advance so we can sort on them
    foreach my $ipaddr ( keys( %data_ip ) )
    {
        $data_ip{$ipaddr}->{EXECTIMEAVG}    = $data_ip{$ipaddr}->{EXECTIME} / $data_ip{$ipaddr}->{TOTAL};
        $data_ip{$ipaddr}->{BYTESINAVG}     = $data_ip{$ipaddr}->{BYTESIN}  / $data_ip{$ipaddr}->{TOTAL};
        $data_ip{$ipaddr}->{BYTESOUTAVG}    = $data_ip{$ipaddr}->{BYTESOUT} / $data_ip{$ipaddr}->{TOTAL};
        $data_ip{$ipaddr}->{URLCOUNT}       = keys( %{ $data_ip{$ipaddr}->{URLS} } );
        $data_ip{$ipaddr}->{USERAGENTTOP}   = ( sort { $data_ip{$ipaddr}->{USERAGENT}->{$b} <=> $data_ip{$ipaddr}->{USERAGENT}->{$a} } keys( $data_ip{$ipaddr}->{USERAGENT} ) )[0];
        $data_ip{$ipaddr}->{USERAGENTCOUNT} = keys( $data_ip{$ipaddr}->{USERAGENT} );

        # Fix non-existant values
        if( ! exists( $data_ip{$ipaddr}->{'2xx'} ) ) { $data_ip{$ipaddr}->{'2xx'} = 0; }
        if( ! exists( $data_ip{$ipaddr}->{'3xx'} ) ) { $data_ip{$ipaddr}->{'3xx'} = 0; }
        if( ! exists( $data_ip{$ipaddr}->{'4xx'} ) ) { $data_ip{$ipaddr}->{'4xx'} = 0; }
        if( ! exists( $data_ip{$ipaddr}->{'5xx'} ) ) { $data_ip{$ipaddr}->{'5xx'} = 0; }
        }

    $show_count = 0;
    # Each different reporting function can only handle different types of sorting
    # Make sure before sorting that a corret sorting type is provided
    if( grep { m/^${sort}$/ } qw( TOTAL BYTESIN BYTESINAVG BYTESINHIGH BYTESOUT BYTESOUTAVG BYTESOUTHIGH EXECTIMEAVG EXECTIMEHIGH 2xx 3xx 4xx 5xx ) )
    {
        # Header
        printf( "############################################################################################################\n" );
        printf( "# Per IPAddr Summary, Sorted by: %s, Limit: %u, Max-width: %u, WebFiles: %s, Images: %s, Known-IPs: %s\n", $sort, $conf{LIMIT}, $conf{URLWIDTH}, $conf{ALLOW_CSSJS}, $conf{ALLOW_IMAGES}, $conf{SHOW_KNOWN_IPS} );
        printf( "############################################################################################################\n" );
        printf( "%-$conf{IP_WIDTH}s %-8s %-8s %-7s %-7s %-9s %-7s %-8s %-8s %-9s %-6s %-4s %-4s %-4s %-4s %-4s %-.$conf{URLWIDTH}s\n",
                'IPAddr', 'Count ', 'In-Total', 'In-Avg', 'In-High', 'Out-Total', 'Out-Avg', 'Out-High', 'Exec-Avg', 'Exec-High', '2xx', '3xx', '4xx', '5xx', 'URLs', '#UA', 'UserAgent' );

        foreach my $ipaddr ( sort { $data_ip{$b}->{$sort} <=> $data_ip{$a}->{$sort} } keys( %data_ip ) )
        {
            $show_count++;
            if( $conf{DEBUG} > 2 ) { print( Dumper( \$data_ip{$ipaddr} ),"\n" ); }
            printf( "%-$conf{IP_WIDTH}s %-8u %-8s %-7s %-7s %-9s %-7s %-8s %-8s %-9s %-6u %-4u %-4u %-4u %-4s %-4u %-.$conf{URLWIDTH}s\n",
                $ipaddr,
                $data_ip{$ipaddr}->{TOTAL},
                byte_size( $data_ip{$ipaddr}->{BYTESIN} ),
                byte_size( $data_ip{$ipaddr}->{BYTESINAVG} ),
                byte_size( $data_ip{$ipaddr}->{BYTESINHIGH} ),
                byte_size( $data_ip{$ipaddr}->{BYTESOUT} ),
                byte_size( $data_ip{$ipaddr}->{BYTESOUTAVG} ),
                byte_size( $data_ip{$ipaddr}->{BYTESOUTHIGH} ),
                time_size( $data_ip{$ipaddr}->{EXECTIMEAVG} ),
                time_size( $data_ip{$ipaddr}->{EXECTIMEHIGH} ),
                $data_ip{$ipaddr}->{'2xx'},
                $data_ip{$ipaddr}->{'3xx'},
                $data_ip{$ipaddr}->{'4xx'},
                $data_ip{$ipaddr}->{'5xx'},
                $data_ip{$ipaddr}->{URLCOUNT},
                $data_ip{$ipaddr}->{USERAGENTCOUNT},
                $data_ip{$ipaddr}->{USERAGENTTOP},
                );
            if( $show_count > $conf{LIMIT} ) { last; }
            }
        }
    else
    {
        if( $conf{VERBOSE} ) { print( "Invalid sorting type for this report: ${sort}\n" ); }
        }

    ## Return ##
    return;
    }

#################################################
# Codes Report
sub report_codes
{
    ## Variables ##

    my $show_count = 0;
    my $sort = $_[0];
    my %codes;

    ## Main ##

    # Get the list of error codes
    foreach my $url ( keys( %data_codes ) )
    {
        foreach my $code ( keys( $data_codes{$url}->{CODES} ) )
        {
            $codes{$code}++;
            }
        }
    # Get the highest code count
    if( $sort eq 'DEFAULT' ) { $sort = ( sort { $codes{$b} <=> $codes{$a} } keys( %codes ) )[0]; }

    # Loops through each url and add the empty codes
    # Needed or else the sort will break
    foreach my $url ( keys( %data_codes ) )
    {
        foreach my $code ( keys( %codes) )
        {
            if( ! defined( $data_codes{$url}->{CODES}->{$code} ) ) { $data_codes{$url}->{CODES}->{$code} = 0; }
            }
        if( ! defined( $data_codes{$url}->{COUNTS}->{'2xx'} ) ) { $data_codes{$url}->{COUNTS}->{'2xx'} = 0; }
        if( ! defined( $data_codes{$url}->{COUNTS}->{'3xx'} ) ) { $data_codes{$url}->{COUNTS}->{'3xx'} = 0; }
        if( ! defined( $data_codes{$url}->{COUNTS}->{'4xx'} ) ) { $data_codes{$url}->{COUNTS}->{'4xx'} = 0; }
        if( ! defined( $data_codes{$url}->{COUNTS}->{'5xx'} ) ) { $data_codes{$url}->{COUNTS}->{'5xx'} = 0; }
        if( ! defined( $data_codes{$url}->{COUNTS}->{'ERR'} ) ) { $data_codes{$url}->{COUNTS}->{'ERR'} = 0; }
        }

    # Debugging
    if( $conf{DEBUG} ) { print( "Codes data: ", Dumper( \%data_codes ),"\n" ); }

    # Each different reporting function can only handle different types of sorting
    # Make sure before sorting that a corret sorting type is provided
    if( grep { m/^${sort}$/ } ( keys( %codes ) ) )
    {
        # Header
        printf( "############################################################################################################\n" );
        printf( "# Per Code Summary, Sorted by: %s, Limit: %u, Max-width: %u, WebFiles: %s, Images: %s, Known-IPs: %s\n", $sort, $conf{LIMIT}, $conf{URLWIDTH}, $conf{ALLOW_CSSJS}, $conf{ALLOW_IMAGES}, $conf{SHOW_KNOWN_IPS} );
        printf( "############################################################################################################\n" );
        printf( "%-8s ", 'Count' );
        foreach my $code ( sort { $a <=> $b } keys( %codes ) ) { printf ( "%-6s ", $code ); }
        printf( "%-.$conf{URLWIDTH}s\n", 'URL' );

        foreach my $url ( sort { $data_codes{$b}->{CODES}->{$sort} <=> $data_codes{$a}->{CODES}->{$sort} } keys( %data_codes ) )
        {
            $show_count++;
            printf( "%-8s ", $data_codes{$url}->{COUNTS}->{TOTAL} );
            foreach my $code ( sort { $a <=> $b } keys( %codes ) )
            {
                printf( "%-6u ", $data_codes{$url}->{CODES}->{$code} );
                }
            printf( "%-.$conf{URLWIDTH}s\n", $url );
            if( $show_count > $conf{LIMIT} ) { last; }
            }
        }
    elsif( grep { m/^${sort}$/ } ( 'COUNT', '2xx', '3xx', '4xx', '5xx', 'ERR' ) )
    {
        # Header
        printf( "############################################################################################################\n" );
        printf( "# Per Code Summary, Sorted by: %s, Limit: %u, Max-width: %u, WebFiles: %s, Images: %s, Known-IPs: %s\n", $sort, $conf{LIMIT}, $conf{URLWIDTH}, $conf{ALLOW_CSSJS}, $conf{ALLOW_IMAGES}, $conf{SHOW_KNOWN_IPS} );
        printf( "############################################################################################################\n" );
        printf( "%-8s ", 'Count' );
        foreach my $code ( sort { $a <=> $b } keys( %codes ) ) { printf ( "%-6s ", $code ); }
        printf( "%-.$conf{URLWIDTH}s\n", 'URL' );

        foreach my $url ( sort { $data_codes{$b}->{COUNTS}->{$sort} <=> $data_codes{$a}->{COUNTS}->{$sort} } keys( %data_codes ) )
        {
            $show_count++;
            printf( "%-8s ", $data_codes{$url}->{COUNTS}->{TOTAL} );
            foreach my $code ( sort { $a <=> $b } keys( %codes ) )
            {
                printf( "%-6u ", $data_codes{$url}->{CODES}->{$code} );
                }
            printf( "%-.$conf{URLWIDTH}s\n", $url );
            if( $show_count > $conf{LIMIT} ) { last; }
            }
        }
    else
    {
        if( $conf{VERBOSE} ) { print( "Invalid sorting type for this report: ${sort}\n" ); }
        }

    ## Return ##
    return;
    }

#################################################
# Byte Sizing
# Takes a byte value and return a string value in In Bytes, Kilo, Mega, or Giga bytes

sub byte_size
{
    ## Variables ##

    my $bytes     = $_[0];
    my $bytesized = '';

    ## Main ##

    if( $bytes > 9999999999 )
    {
        $bytesized = sprintf("%.0fG", ( $bytes / 1000000000 ) );
        }
    elsif( $bytes > 9999999 )
    {
        $bytesized = sprintf("%.0fM", ( $bytes / 1000000 ) );
        }
    elsif( $bytes > 9999 )
    {
        $bytesized = sprintf("%.0fK", ( $bytes / 1000 ) );
        }
    else
    {
        $bytesized = sprintf("%.0fB", ( $bytes ) );
        }

    ## Return ##
    return( $bytesized );
    }

#################################################
# Time Sizing
# Takes a usec time value and return a string in usec, msec, sec
sub time_size
{
    ## Variables ##

    my $time      = $_[0];
    my $timesized = '';

    ## Main ##

    if( $time > 600000000 )
    {
        $timesized = sprintf("%.0fM", ( $time / 60000000 ) );
        }
    elsif( $time > 9999999 )
    {
        $timesized = sprintf("%.0fs", ( $time / 1000000 ) );
        }
    elsif( $time > 9999 )
    {
        $timesized = sprintf("%.0fm", ( $time / 1000 ) );
        }
    else
    {
        $timesized = sprintf("%.0fu", ( $time ) );
        }

    ## Return ##
    return( $timesized );
    }

#################################################
# Time Sizing
# Takes a usec time value and return a string in usec, msec, sec
sub time_size_dec
{
    ## Variables ##

    my $time      = $_[0];
    my $timesized = '';

    ## Main ##

    if( $time > 60000000 )
    {
        $timesized = sprintf("%.0fm", ( $time / 60000000 ) );
        }
    elsif( $time > 9999999 )
    {
        $timesized = sprintf("%.1fs", ( $time / 1000000 ) );
        }
    elsif( $time > 999999 )
    {
        $timesized = sprintf("%.2fs", ( $time / 1000000 ) );
        }
    elsif( $time > 99999 )
    {
        $timesized = sprintf("%.0fm", ( $time / 1000 ) );
        }
    elsif( $time > 9999 )
    {
        $timesized = sprintf("%.1fs", ( $time / 1000 ) );
        }
    elsif( $time > 999 )
    {
        $timesized = sprintf("%.2fm", ( $time / 1000 ) );
        }
    else
    {
        $timesized = sprintf("%.0fu", ( $time ) );
        }

    ## Return ##
    return( $timesized );
    }

#################################################
# Help Sub
sub showhelp
{

# Get this program's short name
my $program = $0;
$program =~ s/^.+[\/\\]//;

print <<__END_PRINT__;
This tool parses a web log stream and displays useful information.
Version: ${version};
Usage:
  tail -f LOGFILE | $program [options]
Options:
  -? --help           Display this help message
  -d --debug          Turn on debugging
  -f --files          Show css,xml,js,txt file requests
  -i --images         Show image file requests
     --ignore-ips     Ignore known IP addresses
  -l --limit=###      Limit output to ## line
  -s --sort=###       Sort output data by: DEFAULT, TOTAL, TIME, BYTESIN, BYTESINAVG, BYTESINHIGH,
                                           BYTESOUT, BYTESOUTAVG, BYTESOUTHIGH, EXECTIMEAVG,
                                           EXECTIMEHIGH, 2xx, 3xx, 4xx, 5xx, IPCOUNT, URLCOUNT
  -w --width=##       Display width for URLs
     --limit-hour <Hour>  Limit data to this hour
     --limit-ip <IPAddr>  Limit data to this IP
     --ipv6           Show full ipv6 addresses

  Report Types:
     --sum            Enable Summary report
     --day            Enable Daily report
     --hour           Enable Hourly report
     --min            Enable Minute report
     --ip             Enable IP Address report
     --url            Enable URL report
     --stat           Enable status code report
     --codes          Enable status codes per url report

Notes:
  * Multipe sort types can be used, example: 'TOTAL,BYTESIN,BYTESOUT'
  * Not all sort methods are valud for all report types
  * --limit is not valid for all report types

Example Usage:
  tail -f web.log | $program
__END_PRINT__
exit(0);
}

###################################################################################################

__END__
