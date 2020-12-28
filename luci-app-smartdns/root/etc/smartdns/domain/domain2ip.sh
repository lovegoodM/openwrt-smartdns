#!/bin/sh

usage() {
    cat <<-EOF
Usage: sh domain2ip.sh domain [tihuan] [-o file](default: /etc/smartdns/custom.conf)
EOF
    exit $1
}

get_args() {
    DOMAIN=''
    DOMAIN2=''
    TIHUAN=''
    OUT_FILE='/etc/smartdns/custom.conf'

    if [[ ${#} == 0 ]]; then
        usage 1
    else
        DOMAIN="$1"
        if [[ -n "$(echo "$DOMAIN" | awk -F. '{print $3}')" ]]; then
            DOMAIN2="$(echo "$DOMAIN" | sed -r 's/([a-zA-Z0-9][-a-zA-Z0-9]*\.)//')"
        fi

        if [[ "${2}" != "" && "${2}" != "-o" ]]; then
            TIHUAN="$2"
            shift
        fi
        shift
    fi

    while [[ ${#} -gt 0 ]]; do
        case "${1}" in
        --output | -o)
            OUT_FILE="$2"
            shift
            ;;
        esac
        shift 1
    done

    echo $DOMAIN
    echo $DOMAIN2
    echo $TIHUAN
    echo $OUT_FILE
}

findip() {
    IPV4_PATTERN='^((2[0-4][0-9]|25[0-5]|[01]?[0-9][0-9]?)\.){3}(2[0-4][0-9]|25[0-5]|[01]?[0-9][0-9]?)$'
    makeurl=''
    getip=''

    if [[ "$DOMAIN2" != '' ]]; then
        makeurl="https://$DOMAIN2.ipaddress.com/$DOMAIN"
    else
        makeurl="https://$DOMAIN.ipaddress.com"
    fi

    getip="$(
        curl -fsSL --connect-timeout 8 --max-time 15 $makeurl | \
        sed -r "s/.*ip address[^0-9]*(((2[0-4][0-9]|25[0-5]|[01]?[0-9][0-9]?)\.){3}(2[0-4][0-9]|25[0-5]|[01]?[0-9][0-9]?)).*/\1/i" | \
        grep -E "$IPV4_PATTERN"
    )"
    # getip="$(curl -fsSL --connect-timeout 5 $makeurl | \
    # sed "s/.*ip address.*\b\(\(\([0-9]\|[1-9][0-9]\|1[0-9][0-9]\|2[0-4][0-9]\|25[0-5]\)\.\)\{3\}[0-9]\+\).*/\1/i" | \
    # grep -E "$IPV4_PATTERN")"
    [[ "$getip" == "" ]] && echo "Did not get ip." && exit 1

    echo $makeurl
    echo $getip
}

outandclean() {
    sed -i "/address \/$DOMAIN/d" $OUT_FILE 2>/dev/null
    [ -n "$TIHUAN" ] && sed -i "/address \/$TIHUAN/d" $OUT_FILE 2>/dev/null
    [ -n "$TIHUAN" ] && echo "address /$TIHUAN/$getip" >>$OUT_FILE || echo "address /$DOMAIN/$getip" >>$OUT_FILE
    echo -e "done.\n"
    exit 0
}

main() {
    get_args "$@"
    findip
    outandclean
}

main "$@"

