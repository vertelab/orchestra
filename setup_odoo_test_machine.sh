#!/bin/bash

ODOOVERSION=""
ODOOREPO=""
UBUNTUVERSION=""
CI_BRANCH_ID=""
ODOOMODULES=""
PRIVSSHKEY="${HOME}/.ssh/id_ed25519"
GITURL="github.com"
SHAREPATH="/usr/share"
ODOOTOOLS="/etc/profile.d/odootools.sh"
ODOO_SERVER_CONF="/etc/odoo/odoo.conf"
ODOOREQPATH=""

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NOCOLOR='\033[0m'

VERSIONS=(8 9 10 11 12 13 14 15 16 17 18 19)
UBUNTUVERSIONS=(14.04 14.04 18.04 17.04 18.04 20.04 20.04 20.04 22.04 22.04 24.04 24.04)

usage() { echo "Usage: $0 [-b <odooversion>] [-p <odoorepo>] [-i optional <cibranchid>] [-m optional <module>] [-g optional <giturl>] [-r optional <reqfileinmodule>]" 1>&2; exit 1;}

while getopts ":b:p:i:m:g:r:" option; do
    case $option in
        b) ODOOVERSION=${OPTARG} ;;
        p) ODOOREPO=${OPTARG} ;;
        i) CI_BRANCH_ID=${OPTARG} ;; 
        m) ODOOMODULES=${OPTARG} ;; 
        g) GITURL=${OPTARG} ;; 
        r) ODOOREQPATH=${OPTARG} ;; 
        :) echo "Option -$OPTARG requires an argument" >&2; usage ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    esac
done

if [ -z "$ODOOVERSION" ] || [ -z "$ODOOREPO" ]; then
    echo "Both -b (Odoo Version) and -p (Odoo Repo) options are required" >&2
    usage
fi

for i in "${!VERSIONS[@]}"; do
    if [[ "${VERSIONS[$i]}" == "${ODOOVERSION}" ]]; then
        UBUNTUVERSION="${UBUNTUVERSIONS[$i]}"
        break
    fi
done

if [ -z "$UBUNTUVERSION" ]; then
    while true; do
        read -rp "The Odoo version you entered is not known to this script. Please enter which version of Ubuntu should be used?" UBUNTUVERSION
        if [ -n "${UBUNTUVERSION}" ]; then
            break
        fi
    done
fi

echo $GITURL
ODOOREPOPATH="$SHAREPATH/$ODOOREPO"
MACHINENAME="${ODOOVERSION}-${ODOOREPO}-$(date +%Y-%m-%d-%H-%M-%S)"
VERSION="$ODOOVERSION.0"

if [ -n $ODOOREQPATH ]; then
    ODOOREQPATH="$ODOOREPOPATH/$ODOOREQPATH"
fi

echo "Creating Ubuntu ${UBUNTUVERSION} for Odoo ${ODOOVERSION}"
echo "Cheking if machine with Odoo ${ODOOVERSION} Alredy exsists"
lxc launch "odoo${ODOOVERSION}" "${MACHINENAME}"
if [[ $? -ne 0 ]]; then
    lxc launch ubuntu:"$UBUNTUVERSION" "$MACHINENAME"

    echo "Waiting for the machine to receive an IP address..."
    sleep 5

    if [[ -z $(lxc exec "$MACHINENAME" -- bash -c 'which pip') ]]; then
        echo -e "${YELLOW}No pip installd${NOCOLOR}"
        echo Installing pip for root...
        lxc exec "$MACHINENAME" -- bash -c 'wget -O- https://bootstrap.pypa.io/get-pip.py | python3'
    fi

    if [ ! -d /root/.config ]; then
        lxc exec "$MACHINENAME" -- mkdir /root/.config
    fi

    if [ ! -d /root/.config/pip ]; then
        lxc exec "$MACHINENAME" -- mkdir /root/.config/pip
    fi

    echo "Fixing brake-system-pages"
    lxc exec "$MACHINENAME" -- bash -c "wget -O /root/.config/pip/pip.conf https://raw.githubusercontent.com/vertelab/orchestra/main/pip.conf" 

    echo "Installing Odoo..."
    lxc exec "$MACHINENAME" -- bash -c "wget -O- https://raw.githubusercontent.com/vertelab/odootools/${VERSION}/install | bash" 

    if ! lxc exec "$MACHINENAME" -- systemctl is-active odoo; then
        echo -e "${RED}Failed to install Odoo.${NOCOLOR}"
        exit 1
    fi
    echo -e "${GREEN}Odoo installd and working${NOCOLOR}"

    echo Shutting down machine in order to save it. Please be patient...
    lxc stop "$MACHINENAME" --force
    echo "Waiting for machine to shut down..."
    sleep 5
    lxc publish "$MACHINENAME" --alias "odoo${ODOOVERSION}"
    echo "Starting machine again..."
    lxc start "$MACHINENAME"
fi

sleep 5

lxc file push "$PRIVSSHKEY" "${MACHINENAME}/root/.ssh/"
lxc exec "$MACHINENAME" -- chown root:root /root/.ssh/ -R
lxc exec "$MACHINENAME" -- bash -c "ssh-keyscan -H github.com > /root/.ssh/known_hosts"
if [ -n $GITURL ]; then
    lxc exec "$MACHINENAME" -- bash -c "ssh-keyscan -H $GITURL >> /root/.ssh/known_hosts"
fi

echo "Cloning repo..."
if ! lxc exec "$MACHINENAME" -- bash -c "git clone -b $VERSION git@${GITURL}:vertelab/${ODOOREPO}.git $ODOOREPOPATH"; then
    echo -e "${RED}Faild to clone repo $ODOOREPO${NOCOLOR}"
    exit 1
fi

PYTHONREQ="$ODOOREPOPATH/requirements.txt"
ODOOEXTREQ="$ODOOREPOPATH/requirements.repo"
if [[ -n $ODOOREQPATH ]]; then
    PYTHONREQ="$ODOOREQPATH/requirements.txt"
    ODOOEXTREQ="$ODOOREQPATH/requirements.repo"
fi
ODOOEXTREQFILE=$(lxc exec "$MACHINENAME" -- cat "$ODOOEXTREQ")
readarray -t ODOOEXTREQFILEARRAY <<< $ODOOEXTREQFILE

echo "Checking for odootools.sh..."
if [[ -z "$(lxc exec ${MACHINENAME} -- cat ${ODOOTOOLS})" ]]; then
    echo -e "${YELLOW}No odootools.sh found${NOCOLOR}"
    echo "Installing odootools.sh..."
    lxc exec "$MACHINENAME" -- bash -c "wget -O $ODOOTOOLS https://raw.githubusercontent.com/vertelab/odootools/common/odootools.sh"
fi

if [[ -n "$(lxc exec ${MACHINENAME} -- cat ${ODOOEXTREQ})" ]]; then
    echo "Installing dependencies..."
    for line in "${ODOOEXTREQFILEARRAY[@]}"; 
    do
        IFS=' ' read -r repo_url repo_path <<< "$line"
        echo "$repo_url"
        if ! lxc exec "$MACHINENAME" -- bash -c "git clone -b $VERSION --depth 1  $repo_url $repo_path"; then
            echo -e "${RED}failed to git clone ${repo_url} ${NOCOLOR}"
        fi
    done
else
    echo "No dependencies found."
fi

echo "using odootools..."
lxc exec "$MACHINENAME" -- bash -c "source $ODOOTOOLS && odooaddons && odoosetperm"

if [[ -n "$(lxc exec ${MACHINENAME} -- cat ${PYTHONREQ})" ]]; then
    echo "Installing python dependencies..."
    if ! lxc exec "$MACHINENAME" -- pip3 install -r "$PYTHONREQ"; then
        lxc exec "$MACHINENAME" -- pip3 install -r "$PYTHONREQ" --ignore-installed;
    fi
else
    echo "No python dependencies found."
fi

if [[ -z $ODOOMODULES ]]; then
    ODOOMODULES=$(lxc exec "$MACHINENAME" -- find "$ODOOREPOPATH" -mindepth 1 -maxdepth 1 -type d -not \( -name ".git" \) -printf '%f\n' | tr '\n' ',' | sed 's/,$//')
fi
USERID=$(lxc exec "$MACHINENAME" -- id -u "odoo")
IP=$(lxc exec "$MACHINENAME" -- ip a | grep -Po '\d{1,3}.\d{1,3}.\d{1,3}.\d{1,3}(?=\/24)')

echo "Shutting down Odoo to avoid port conflicts when testing."
lxc exec "$MACHINENAME" -- systemctl stop odoo.service

echo "Installing odoo modules..."
lxc exec "$MACHINENAME" --user "$USERID" -- bash -c "odoo --config ${ODOO_SERVER_CONF} --database ${ODOOREPO} --init ${ODOOMODULES} --stop-after-init --test-enable --logfile /var/log/odoo/test-odoo-server.log"

CHECK=$(lxc exec "$MACHINENAME" -- cat /var/log/odoo/test-odoo-server.log | grep "CRITICAL")
IS_SUCCESS=""

if [[ -z "$CHECK" ]]; then
    echo -e "${GREEN}Successfully installed and tested modules.${NOCOLOR}"
    IS_SUCCESS=true
else
    echo -e "${RED}Failed to install and test modules.${NOCOLOR}"
    IS_SUCCESS=false
fi

lxc exec "$MACHINENAME" -- bash -c "perl -i -pe 's/^admin_passwd.*=.*/admin_passwd = admin/g' ${ODOO_SERVER_CONF}"
lxc exec "$MACHINENAME" -- systemctl start odoo.service

lxc exec "$MACHINENAME" -- bash -c 'wget -O /var/log/odoo/test_machine_report.py https://github.com/vertelab/orchestra/raw/refs/heads/main/test_machine_report.py'
lxc exec "$MACHINENAME" -- bash -c "python3 /var/log/odoo/test_machine_report.py $MACHINENAME $ODOOVERSION $IP $IS_SUCCESS $CI_BRANCH_ID" 