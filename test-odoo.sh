#!/bin/bash

ODOOVERSION=""
ODOOREPO=""
UBUNTUVERSION=""
SHAREPATH="/usr/share"

usage() { echo "Usage: $0 [-v <odooversion>] [-r <odoorepo>] [-u <ubuntuversion]" 1>&2; exit 1;}

while getopts ":v:r:u:" option; do
    case $option in
        v) ODOOVERSION=${OPTARG} ;;
        r) ODOOREPO=${OPTARG} ;;
        u) UBUNTUVERSION=${OPTARG} ;;
        :) echo "Option -$OPTARG requires an argument" >&2; usage ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    esac
done

if [ -z "$ODOOVERSION" ] || [ -z "$ODOOREPO" ]; then
    echo "Both -v (Odoo Version) and -r (Odoo Repo) options are required" >&2
    usage
fi

if [ -z "$UBUNTUVERSION" ]; then
    while true; do
        read -rp "Which version of ubuntu should be used? " UBUNTUVERSION
        if [ -n "${UBUNTUVERSION}" ]; then
            break
        fi
    done
fi
 
echo "Odoo Version: $ODOOVERSION"
echo "Odoo Repo: $ODOOREPO"
MACHINENAME="${ODOOVERSION}-${ODOOREPO}-$(date +%Y-%m-%d-%H-%M-%S)"
echo "$MACHINENAME"

sudo lxc launch ubuntu:"$UBUNTUVERSION" "$MACHINENAME"

echo "Waiting for the machine to receive an IP address..."
sleep 5

echo "Installing Odoo..."
sudo lxc exec "$MACHINENAME" -- bash -c "wget -O- https://raw.githubusercontent.com/vertelab/odootools/18.0/install | bash" 
echo "Odoo installd"

echo "use odootools"
sudo lxc exec "$MACHINENAME" -- bash -c 'sudo git clone -b "$VERSION" https://github.com/vertelab/"$ODOOREPO".git'

sudo lxc exec "$MACHINENAME" -- bash -c '. /etc/profile.d/odootools.sh; odooaddons; odooreqclone "$SHAREPATH""$ODOOREPO"/requirements.repo; odooallrequirements; odoosetperms'

sudo lxc exec "$MACHINENAME" -- su odoo -c 'odoo -c \'"$ODOO_SERVER_CONF" --database "$ODOOREPO" --init "$ODOOREPO" --stop-after-init\''
