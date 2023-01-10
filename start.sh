#!/usr/bin/env bash

OPT=$1
ARGS=$@

DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

main (){
    case $OPT in
        init)
            rm -rf $DIR/tool
            mkdir $DIR/tool
            # proxy
            wget https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip -O $DIR/tool/proxy-latest.zip
            unzip $DIR/tool/proxy-latest.zip -d $DIR/tool/proxy
            rm -rf $DIR/tool/proxy-latest.zip
            touch $DIR/proxy.json
            # rwfus
            git clone -b dev --depth 1 https://github.com/ValShaped/rwfus.git $DIR/tool/rwfus
            cd $DIR/tool/rwfus
            ./rwfus -iI
            echo Done
            ;;
        update)
            echo Updating Routing data
            wget https://github.com/v2fly/geoip/releases/latest/download/geoip-only-cn-private.dat -O $DIR/tool/proxy/geoip.dat
            wget https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat -O $DIR/tool/proxy/geosite.dat
            echo Done
            ;;
        proxy)
            need_root
            start_proxy
            ;;
        chkos)
            need_root
            chkos
            ;;
        fixos)
            need_root
            chkos | pacman -S
            ;;
        *)
            echo Usage: $0 COMMAND
            echo Commands:
            echo init   - Download helper tools
            echo update - Download routing data
            echo proxy  - Start proxy
            echo chkos  - List broken packages
            echo fixos  - Reinstalling broken packages
            exit 1
            ;;
    esac
}

need_root (){
if [ $UID -ne 0 ]; then
    echo Please run as root.
    exit 1
fi
}

require (){
if ! command -v $1 &> /dev/null
then
    echo \"$1\" not found
    exit 1
fi
}

chkos (){
    pacman -Qknq | cut -d' ' -f 1 | sort -u
}

start_proxy (){
    require jq
    echo === Info
    IP=$(ip route get 8.8.8.8 | head -1 | cut -d' ' -f7)
    GW=$(ip route | grep default | awk '{print $3}')
    IF=$(ip route | grep default | awk '{print $5}')
    echo $IP via $GW dev $IF

    PROXY_IPS=($(cat proxy.json | perl -pe 's/^(.+?)\/\/ (.+?)$/\1/' | jq --raw-output '.outbounds[] | .settings.servers | select(. != null)[].address | select(test("^[0-9]"))'))
    DIRECT_IPS=("127.0.0.1/8" "224.0.0.0/4" "255.255.255.255/32" $IP)
    echo Direct: ${DIRECT_IPS[@]}
    echo === Setup

    echo Setup re-route rule
    ip rule add fwmark 1 table 100
    ip route add local 0.0.0.0/0 dev lo table 100
    ip route flush cache

    echo Setup mangle PREROUTING chain
    iptables -t mangle -N V2RAY
    iptables -t mangle -A V2RAY -j RETURN -m socket
    iptables -t mangle -A V2RAY -j RETURN -m mark --mark 0xff # 0xff passthrough
    for ip in ${DIRECT_IPS[@]}; do
        iptables -t mangle -A V2RAY -d $ip -j RETURN
    done
    iptables -t mangle -A V2RAY -p udp -j TPROXY --on-ip 127.0.0.1 --on-port 12000 --tproxy-mark 1 # send to proxy
    iptables -t mangle -A V2RAY -p tcp -j TPROXY --on-ip 127.0.0.1 --on-port 12000 --tproxy-mark 1 # send to proxy
    iptables -t mangle -A PREROUTING -j V2RAY

    echo Setup mangle OUTPUT chain
    iptables -t mangle -N V2RAY_MASK
    iptables -t mangle -A V2RAY_MASK -j RETURN -m mark --mark 0xff # 0xff passthrough
    for ip in ${DIRECT_IPS[@]}; do
        iptables -t mangle -A V2RAY_MASK -d $ip -j RETURN
    done
    iptables -t mangle -A V2RAY_MASK -p udp -j MARK --set-mark 1 # re-route
    iptables -t mangle -A V2RAY_MASK -p tcp -j MARK --set-mark 1 # re-route
    iptables -t mangle -A OUTPUT -j V2RAY_MASK

    echo Start proxy
    $DIR/tool/proxy/v2ray run -c $DIR/proxy.json

    echo Clean up...
    ip rule del table 100
    ip route flush table 100
    ip route flush cache
    iptables -t mangle -D PREROUTING -j V2RAY # de-apply
    iptables -t mangle -D OUTPUT -j V2RAY_MASK # de-apply
    iptables -t mangle -F V2RAY # flush chain
    iptables -t mangle -F V2RAY_MASK # flush chain
    iptables -t mangle -X V2RAY # remove chain
    iptables -t mangle -X V2RAY_MASK # remove chain
}

main
