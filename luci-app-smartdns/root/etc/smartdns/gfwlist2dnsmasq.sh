#!/bin/sh

# Name:        gfwlist2dnsmasq.sh
# Desription:  A shell script which convert gfwlist into dnsmasq rules.
# Version:     0.9.0 (2020.04.09)
# Author:      Cokebar Chi
# Website:     https://github.com/cokebar

_green() {
    printf '\033[1;31;32m'
    printf -- "%b" "$1"
    printf '\033[0m'
}

_red() {
    printf '\033[1;31;31m'
    printf -- "%b" "$1"
    printf '\033[0m'
}

_yellow() {
    printf '\033[1;31;33m'
    printf -- "%b" "$1"
    printf '\033[0m'
}

usage() {
    cat <<-EOF

Name:        gfwlist2dnsmasq.sh
Desription:  A shell script which convert gfwlist into dnsmasq rules.
Version:     0.8.0 (2017.12.25)
Author:      Cokebar Chi
Website:     https://github.com/cokebar

Usage: sh gfwlist2dnsmasq.sh [options] -o FILE
Valid options are:
    -d, --dns <dns_ip>
                DNS IP address for the GfwList Domains (Default: 127.0.0.1)
    -p, --port <dns_port>
                DNS Port for the GfwList Domains (Default: 5353)
    -g, --group <group_name>
                This option can be selected when the --domain-smartdns option is used
    -s, --ipset <ipset_name>
                Ipset name for the GfwList domains
                (If not given, ipset rules will not be generated.)
        --ipset-SD <ipset_name>
                This option can be selected when the --domain-smartdns option is used
    -o, --output <FILE>
                /path/to/output_filename
    -i, --insecure
                Force bypass certificate validation (insecure)
    -l, --domain-list
                Convert Gfwlist into domain list instead of dnsmasq rules
                (If this option is set, DNS IP/Port & ipset are not needed)
        --domain-smartdns
                Convert Gfwlist into SmartDNS files instead of dnsmasq rules
                (If this option is set, DNS IP/Port are not needed)
        --exclude-domain-file <FILE>
                Delete specific domains in the result from a domain list text file
                Please put one domain per line
        --extra-domain-file <FILE>
                Include extra domains to the result from a domain list text file
                This file will be processed after the exclude-domain-file
                Please put one domain per line
    -h, --help
                Usage
EOF
    exit $1
}

clean_and_exit(){
    # Clean up temp files
    printf 'Cleaning up... '
    rm -rf $TMP_DIR
    _green 'Done\n\n'
    [ $1 -eq 0 ] && _green 'Job Finished.\n\n' || _red 'Exit with Error code '$1'.\n'
    exit $1
}

check_depends(){
    which sed base64 mktemp >/dev/null
    if [ $? != 0 ]; then
        _red 'Error: Missing Dependency.\nPlease check whether you have the following binaries on you system:\nwhich, sed, base64, mktemp.\n'
        exit 3
    fi
    which curl >/dev/null
    if [ $? != 0 ]; then
        which wget >/dev/null
        if [ $? != 0 ]; then
            _red 'Error: Missing Dependency.\nEither curl or wget required.\n'
            exit 3
        fi
        USE_WGET=1
    else
        USE_WGET=0
    fi

    SYS_KERNEL=`uname -s`
    if [ $SYS_KERNEL = "Darwin"  -o $SYS_KERNEL = "FreeBSD" ]; then
        BASE64_DECODE='base64 -D'
        SED_ERES='sed -E'
    else
        BASE64_DECODE='base64 -d'
        SED_ERES='sed -r'
    fi
}

get_args(){
    OUT_TYPE='DNSMASQ_RULES'
    DNS_IP='127.0.0.1'
    DNS_PORT='5353'
	DNS_GROUP=''
    IPSET_NAME=''
	IPSET_NAME_SD=''
    FILE_FULLPATH=''
    CURL_EXTARG=''
    WGET_EXTARG=''
    WITH_IPSET=0
    EXTRA_DOMAIN_FILE=''
    EXCLUDE_DOMAIN_FILE=''
    IPV4_PATTERN='^((2[0-4][0-9]|25[0-5]|[01]?[0-9][0-9]?)\.){3}(2[0-4][0-9]|25[0-5]|[01]?[0-9][0-9]?)$'
    IPV6_PATTERN='^((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}))|:)))(%.+)?$'

    while [ ${#} -gt 0 ]; do
        case "${1}" in
            --help | -h)
                usage 0
                ;;
            --domain-list | -l)
                OUT_TYPE='DOMAIN_LIST'
                ;;
            --domain-smartdns)
                OUT_TYPE='DOMAIN_SMARTDNS'
                ;;
            --insecure | -i)
                CURL_EXTARG='--insecure'
                WGET_EXTARG='--no-check-certificate'
                ;;
            --dns | -d)
                DNS_IP="$2"
                shift
                ;;
            --port | -p)
                DNS_PORT="$2"
                shift
                ;;
            --group | -g)
                DNS_GROUP="$2"
                shift
                ;;
            --ipset | -s)
                IPSET_NAME="$2"
                shift
                ;;
            --ipset-SD)
                IPSET_NAME_SD="$2"
                shift
                ;;
            --output | -o)
                OUT_FILE="$2"
                shift
                ;;
            --extra-domain-file)
                EXTRA_DOMAIN_FILE="$2"
                shift
                ;;
           --exclude-domain-file)
                EXCLUDE_DOMAIN_FILE="$2"
                shift
                ;;
            *)
                _red "Invalid argument: $1"
                usage 1
                ;;
        esac
        shift 1
    done

    # Check path & file name
    if [ -z $OUT_FILE ]; then
        _red 'Error: Please specify the path to the output file(using -o/--output argument).\n'
        exit 1
    else
        if [ -z ${OUT_FILE##*/} ]; then
            _red 'Error: '$OUT_FILE' is a path, not a file.\n'
            exit 1
        else
            if [ ${OUT_FILE}a != ${OUT_FILE%/*}a ] && [ ! -d ${OUT_FILE%/*} ]; then
                _red 'Error: Folder do not exist: '${OUT_FILE%/*}'\n'
                exit 1
            fi
        fi
    fi

    if [ $OUT_TYPE = 'DNSMASQ_RULES' ]; then
        # Check DNS IP
        IPV4_TEST=$(echo $DNS_IP | grep -E $IPV4_PATTERN)
        IPV6_TEST=$(echo $DNS_IP | grep -E $IPV6_PATTERN)
        if [ "$IPV4_TEST" != "$DNS_IP" -a "$IPV6_TEST" != "$DNS_IP" ]; then
            _red 'Error: Please enter a valid DNS server IP address.\n'
            exit 1
        fi

        # Check DNS port
        if [ $DNS_PORT -lt 1 -o $DNS_PORT -gt 65535 ]; then
            _red 'Error: Please enter a valid DNS server port.\n'
            exit 1
        fi

        # Check ipset name
        if [ -z $IPSET_NAME ]; then
            WITH_IPSET=0
        else
            IPSET_TEST=$(echo $IPSET_NAME | grep -E '^\w+(,\w+)*$')
            if [ "$IPSET_TEST" != "$IPSET_NAME" ]; then
                _red 'Error: Please enter a valid IP set name.\n'
                exit 1
            else
                WITH_IPSET=1
            fi
        fi
    fi

    if [ ! -z $EXTRA_DOMAIN_FILE ] && [ ! -f $EXTRA_DOMAIN_FILE ]; then
        _yellow 'WARNING:\nExtra domain file does not exist, ignored.\n\n'
        EXTRA_DOMAIN_FILE=''
    fi

    if [ ! -z $EXCLUDE_DOMAIN_FILE ] && [ ! -f $EXCLUDE_DOMAIN_FILE ]; then
        _yellow 'WARNING:\nExclude domain file does not exist, ignored.\n\n'
        EXCLUDE_DOMAIN_FILE=''
    fi
}

process(){
    # Set Global Var
    BASE_URL='https://github.com/gfwlist/gfwlist/raw/master/gfwlist.txt'
    TMP_DIR=`mktemp -d /tmp/gfwlist2dnsmasq.XXXXXX`
    BASE64_FILE="$TMP_DIR/base64.txt"
    GFWLIST_FILE="$TMP_DIR/gfwlist.txt"
    DOMAIN_TEMP_FILE="$TMP_DIR/gfwlist2domain.tmp"
    DOMAIN_FILE="$TMP_DIR/gfwlist2domain.txt"
    CONF_TMP_FILE="$TMP_DIR/gfwlist.conf.tmp"
    OUT_TMP_FILE="$TMP_DIR/gfwlist.out.tmp"

    # Fetch GfwList and decode it into plain text
    printf 'Fetching GfwList... '
    if [ $USE_WGET = 0 ]; then
        curl -s -L $CURL_EXTARG -o$BASE64_FILE $BASE_URL
    else
        wget -q $WGET_EXTARG -O$BASE64_FILE $BASE_URL
    fi
    if [ $? != 0 ]; then
        _red '\nFailed to fetch gfwlist.txt. Please check your Internet connection, and check TLS support for curl/wget.\n'
        clean_and_exit 2
    fi
    $BASE64_DECODE $BASE64_FILE > $GFWLIST_FILE || ( _red 'Failed to decode gfwlist.txt. Quit.\n'; clean_and_exit 2 )
    _green 'Done.\n\n'

    # Convert
    IGNORE_PATTERN='^\!|\[|^@@|(https?://){0,1}[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'
    HEAD_FILTER_PATTERN='s#^(\|\|?)?(https?://)?##g'
    TAIL_FILTER_PATTERN='s#/.*$|%2F.*$##g'
    DOMAIN_PATTERN='([a-zA-Z0-9][-a-zA-Z0-9]*(\.[a-zA-Z0-9][-a-zA-Z0-9]*)+)'
    HANDLE_WILDCARD_PATTERN='s#^(([a-zA-Z0-9]*\*[-a-zA-Z0-9]*)?(\.))?([a-zA-Z0-9][-a-zA-Z0-9]*(\.[a-zA-Z0-9][-a-zA-Z0-9]*)+)(\*[a-zA-Z0-9]*)?#\4#g'

    printf 'Converting GfwList to ' && _green $OUT_TYPE && printf ' ...\n' 
    _yellow '\nWARNING:\nThe following lines in GfwList contain regex, and might be ignored:\n\n'
    cat $GFWLIST_FILE | grep -n '^/.*$'
    _yellow "\nThis script will try to convert some of the regex rules. But you should know this may not be a equivalent conversion.\nIf there's regex rules which this script do not deal with, you should add the domain manually to the list.\n\n"
    grep -vE $IGNORE_PATTERN $GFWLIST_FILE | $SED_ERES $HEAD_FILTER_PATTERN | $SED_ERES $TAIL_FILTER_PATTERN | grep -E $DOMAIN_PATTERN | $SED_ERES $HANDLE_WILDCARD_PATTERN > $DOMAIN_TEMP_FILE

    printf 'google.ac\ngoogle.ad\ngoogle.ae\ngoogle.al\ngoogle.am\ngoogle.as\ngoogle.at\ngoogle.az\ngoogle.ba\ngoogle.be\ngoogle.bf\ngoogle.bg\ngoogle.bi\ngoogle.bj\ngoogle.bs\ngoogle.bt\ngoogle.by\ngoogle.ca\ngoogle.cat\ngoogle.cc\ngoogle.cd\ngoogle.cf\ngoogle.cg\ngoogle.ch\ngoogle.ci\ngoogle.cl\ngoogle.cm\ngoogle.cn\ngoogle.co.ao\ngoogle.co.bw\ngoogle.co.ck\ngoogle.co.cr\ngoogle.co.id\ngoogle.co.il\ngoogle.co.in\ngoogle.co.jp\ngoogle.co.ke\ngoogle.co.kr\ngoogle.co.ls\ngoogle.com\ngoogle.co.ma\ngoogle.com.af\ngoogle.com.ag\ngoogle.com.ai\ngoogle.com.ar\ngoogle.com.au\ngoogle.com.bd\ngoogle.com.bh\ngoogle.com.bn\ngoogle.com.bo\ngoogle.com.br\ngoogle.com.bz\ngoogle.com.co\ngoogle.com.cu\ngoogle.com.cy\ngoogle.com.do\ngoogle.com.ec\ngoogle.com.eg\ngoogle.com.et\ngoogle.com.fj\ngoogle.com.gh\ngoogle.com.gi\ngoogle.com.gt\ngoogle.com.hk\ngoogle.com.jm\ngoogle.com.kh\ngoogle.com.kw\ngoogle.com.lb\ngoogle.com.lc\ngoogle.com.ly\ngoogle.com.mm\ngoogle.com.mt\ngoogle.com.mx\ngoogle.com.my\ngoogle.com.na\ngoogle.com.nf\ngoogle.com.ng\ngoogle.com.ni\ngoogle.com.np\ngoogle.com.om\ngoogle.com.pa\ngoogle.com.pe\ngoogle.com.pg\ngoogle.com.ph\ngoogle.com.pk\ngoogle.com.pr\ngoogle.com.py\ngoogle.com.qa\ngoogle.com.sa\ngoogle.com.sb\ngoogle.com.sg\ngoogle.com.sl\ngoogle.com.sv\ngoogle.com.tj\ngoogle.com.tr\ngoogle.com.tw\ngoogle.com.ua\ngoogle.com.uy\ngoogle.com.vc\ngoogle.com.vn\ngoogle.co.mz\ngoogle.co.nz\ngoogle.co.th\ngoogle.co.tz\ngoogle.co.ug\ngoogle.co.uk\ngoogle.co.uz\ngoogle.co.ve\ngoogle.co.vi\ngoogle.co.za\ngoogle.co.zm\ngoogle.co.zw\ngoogle.cv\ngoogle.cz\ngoogle.de\ngoogle.dj\ngoogle.dk\ngoogle.dm\ngoogle.dz\ngoogle.ee\ngoogle.es\ngoogle.fi\ngoogle.fm\ngoogle.fr\ngoogle.ga\ngoogle.ge\ngoogle.gf\ngoogle.gg\ngoogle.gl\ngoogle.gm\ngoogle.gp\ngoogle.gr\ngoogle.gy\ngoogle.hn\ngoogle.hr\ngoogle.ht\ngoogle.hu\ngoogle.ie\ngoogle.im\ngoogle.io\ngoogle.iq\ngoogle.is\ngoogle.it\ngoogle.je\ngoogle.jo\ngoogle.kg\ngoogle.ki\ngoogle.kz\ngoogle.la\ngoogle.li\ngoogle.lk\ngoogle.lt\ngoogle.lu\ngoogle.lv\ngoogle.md\ngoogle.me\ngoogle.mg\ngoogle.mk\ngoogle.ml\ngoogle.mn\ngoogle.ms\ngoogle.mu\ngoogle.mv\ngoogle.mw\ngoogle.ne\ngoogle.net\ngoogle.nl\ngoogle.no\ngoogle.nr\ngoogle.nu\ngoogle.org\ngoogle.pl\ngoogle.pn\ngoogle.ps\ngoogle.pt\ngoogle.ro\ngoogle.rs\ngoogle.ru\ngoogle.rw\ngoogle.sc\ngoogle.se\ngoogle.sh\ngoogle.si\ngoogle.sk\ngoogle.sm\ngoogle.sn\ngoogle.so\ngoogle.sr\ngoogle.st\ngoogle.td\ngoogle.tg\ngoogle.tk\ngoogle.tl\ngoogle.tm\ngoogle.tn\ngoogle.to\ngoogle.tt\ngoogle.vg\ngoogle.vu\ngoogle.ws\n' >> $DOMAIN_TEMP_FILE
    printf 'Google search domains... ' && _green 'Added\n'

    # Add blogspot domains
    printf 'blogspot.ae\nblogspot.al\nblogspot.am\nblogspot.ba\nblogspot.be\nblogspot.bg\nblogspot.bj\nblogspot.ca\nblogspot.cat\nblogspot.cf\nblogspot.ch\nblogspot.cl\nblogspot.co.at\nblogspot.co.id\nblogspot.co.il\nblogspot.co.ke\nblogspot.com\nblogspot.com.ar\nblogspot.com.au\nblogspot.com.br\nblogspot.com.by\nblogspot.com.co\nblogspot.com.cy\nblogspot.com.ee\nblogspot.com.eg\nblogspot.com.es\nblogspot.com.mt\nblogspot.com.ng\nblogspot.com.tr\nblogspot.com.uy\nblogspot.co.nz\nblogspot.co.uk\nblogspot.co.za\nblogspot.cv\nblogspot.cz\nblogspot.de\nblogspot.dk\nblogspot.fi\nblogspot.fr\nblogspot.gr\nblogspot.hk\nblogspot.hr\nblogspot.hu\nblogspot.ie\nblogspot.in\nblogspot.is\nblogspot.it\nblogspot.jp\nblogspot.kr\nblogspot.li\nblogspot.lt\nblogspot.lu\nblogspot.md\nblogspot.mk\nblogspot.mr\nblogspot.mx\nblogspot.my\nblogspot.nl\nblogspot.no\nblogspot.pe\nblogspot.pt\nblogspot.qa\nblogspot.re\nblogspot.ro\nblogspot.rs\nblogspot.ru\nblogspot.se\nblogspot.sg\nblogspot.si\nblogspot.sk\nblogspot.sn\nblogspot.td\nblogspot.tw\nblogspot.ug\nblogspot.vn\n' >> $DOMAIN_TEMP_FILE
    printf 'Blogspot domains... ' && _green 'Added\n'

    # Add twimg.edgesuite.net
    printf 'twimg.edgesuite.net\n' >> $DOMAIN_TEMP_FILE
    printf 'twimg.edgesuite.net... ' && _green 'Added\n'

    # Delete exclude domains
    if [ ! -z $EXCLUDE_DOMAIN_FILE ]; then
        for line in $(cat $EXCLUDE_DOMAIN_FILE)
        do
            cat $DOMAIN_TEMP_FILE | grep -vF -f $EXCLUDE_DOMAIN_FILE > $DOMAIN_FILE
        done
        printf 'Domains in exclude domain file '$EXCLUDE_DOMAIN_FILE'... ' && _green 'Deleted\n'
    else
        cat $DOMAIN_TEMP_FILE > $DOMAIN_FILE
    fi

    # Add extra domains
    if [ ! -z $EXTRA_DOMAIN_FILE ]; then
        cat $EXTRA_DOMAIN_FILE >> $DOMAIN_FILE
        printf 'Extra domain file '$EXTRA_DOMAIN_FILE'... ' && _green 'Added\n'
    fi

    if [ $OUT_TYPE = 'DNSMASQ_RULES' ]; then
    # Convert domains into dnsmasq rules
        if [ $WITH_IPSET -eq 1 ]; then
            _green 'Ipset rules included.'
            sort -u $DOMAIN_FILE | $SED_ERES 's#(.+)#server=/\1/'$DNS_IP'\#'$DNS_PORT'\
ipset=/\1/'$IPSET_NAME'#g' > $CONF_TMP_FILE
        else
            _green 'Ipset rules not included.'
            sort -u $DOMAIN_FILE | $SED_ERES 's#(.+)#server=/\1/'$DNS_IP'\#'$DNS_PORT'#g' > $CONF_TMP_FILE
        fi

        # Generate output file
        echo '# dnsmasq rules generated by gfwlist' > $OUT_TMP_FILE
        echo "# Last Updated on $(date "+%Y-%m-%d %H:%M:%S")" >> $OUT_TMP_FILE
        echo '# ' >> $OUT_TMP_FILE
        cat $CONF_TMP_FILE >> $OUT_TMP_FILE

    elif [ $OUT_TYPE = 'DOMAIN_SMARTDNS' ]; then
        local GI=""
        if [ -z "$DNS_GROUP" ]; then
            _green 'Group rules not included.'
        else
            _green 'Group rules included.'
            GI="$GI -nameserver $DNS_GROUP"
        fi
        echo ""
        if [ -z "$IPSET_NAME_SD" ]; then
            _green 'Ipset-SD rules not included.'
        else
            _green 'Ipset-SD rules included.'
            GI="$GI -ipset $IPSET_NAME_SD"
        fi
        echo ""
        sort -u $DOMAIN_FILE | $SED_ERES 's#(.+)#domain-rules\ /\1/'"$GI"'#g' > $CONF_TMP_FILE

        # Generate output file
        echo '# smartdns rules generated by gfwlist' > $OUT_TMP_FILE
        echo "# Last Updated on $(date "+%Y-%m-%d %H:%M:%S")" >> $OUT_TMP_FILE
        echo '# ' >> $OUT_TMP_FILE
        cat $CONF_TMP_FILE >> $OUT_TMP_FILE
    else
        sort -u $DOMAIN_FILE > $OUT_TMP_FILE
    fi

    cp $OUT_TMP_FILE $OUT_FILE
    printf '\nConverting GfwList to '$OUT_TYPE'... ' && _green 'Done\n\n'

    # Clean up
    clean_and_exit 0
}

main() {
    if [ -z "$1" ]; then
        usage 0
    else
        check_depends
        get_args "$@"
        _green '\nJob Started.\n\n'
        process
    fi
}

main "$@"
