#!/usr/bin/env bash

OPT=$1
ARGS=$@

DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

main (){
    case $OPT in
        init)
            rm -rf $DIR/tool
            mkdir $DIR/tool
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

main
