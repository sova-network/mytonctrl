#!/bin/bash
set -e

# colors
COLOR='\033[92m'
ENDC='\033[0m'
mydir=`pwd`

# check sudo permissions
if [ "$(id -u)" != "0" ]; then
    echo "Please run script as root"
    exit 1
fi

author="ton-blockchain"
repo="mytonctrl"
branch="master"
network="mainnet"
ton_node_version="master"  # Default version


show_help_and_exit() {
    echo 'Supported arguments:'
    echo ' -c  PATH         Provide custom config for toninstaller.sh'
    echo ' -t               Disable telemetry'
    echo ' -i               Ignore minimum requirements'
    echo ' -d               Use pre-packaged dump. Reduces duration of initial synchronization.'
    echo ' -a               Set MyTonCtrl git repo author'
    echo ' -r               Set MyTonCtrl git repo'
    echo ' -b               Set MyTonCtrl git repo branch'
    echo ' -m  MODE         Install MyTonCtrl with specified mode (validator or liteserver)'
    echo ' -n  NETWORK      Specify the network (mainnet or testnet)'
    echo ' -v  VERSION      Specify the ton node version (commit, branch, or tag)'
    echo ' -u  USER         Specify the user to be used for MyTonCtrl installation'
    echo ' -p  PATH         Provide backup file for MyTonCtrl installation'
    echo ' -o               Install only MyTonCtrl. Must be used with -p'
    echo ' -l               Install only TON node'
    echo ' -h               Show this help'
    exit
}

if [[ "${1-}" =~ ^-*h(elp)?$ ]]; then
    show_help_and_exit
fi

# node install parameters
config="https://raw.githubusercontent.com/sova-network/mytonctrl/refs/heads/master/sova-mainnet-global.config.json"
telemetry=true
ignore=false
dump=false
only_mtc=false
only_node=false
backup=none
mode=none
cpu_required=16
mem_required=64000000  # 64GB in KB

while getopts ":c:tidola:r:b:m:n:v:u:p:h" flag; do
    case "${flag}" in
        c) config=${OPTARG};;
        t) telemetry=false;;
        i) ignore=true;;
        d) dump=true;;
        a) author=${OPTARG};;
        r) repo=${OPTARG};;
        b) branch=${OPTARG};;
        m) mode=${OPTARG};;
        n) network=${OPTARG};;
        v) ton_node_version=${OPTARG};;
        u) user=${OPTARG};;
        o) only_mtc=true;;
        l) only_node=true;;
        p) backup=${OPTARG};;
        h) show_help_and_exit;;
        *)
            echo "Flag -${flag} is not recognized. Aborting"
        exit 1 ;;
    esac
done


if [ "$only_mtc" = true ] && [ "$backup" = "none" ]; then
    echo "Backup file must be provided if only mtc installation"
    exit 1
fi


if [ "${mode}" = "none" ] && [ "$backup" = "none" ]; then  # no mode or backup was provided
    echo "Running cli installer"
    wget https://raw.githubusercontent.com/${author}/${repo}/${branch}/scripts/install.py
    if ! command -v pip3 &> /dev/null; then
        echo "pip not found. Installing pip..."
        python3 -m pip install --upgrade pip
    fi
    pip3 install questionary==2.1.0 --break-system-packages
    python3 install.py
    pip3 uninstall questionary -y
    exit
fi

# Set config based on network argument
if [ "${network}" = "testnet" ]; then
    config="https://raw.githubusercontent.com/sova-network/mytonctrl/refs/heads/master/sova-testnet-global.config.json"
    cpu_required=8
    mem_required=16000000  # 16GB in KB
fi

# check machine configuration
echo -e "${COLOR}[1/5]${ENDC} Checking system requirements"

cpus=$(lscpu | grep "CPU(s)" | head -n 1 | awk '{print $2}')
memory=$(cat /proc/meminfo | grep MemTotal | awk '{print $2}')

echo "This machine has ${cpus} CPUs and ${memory}KB of Memory"
if [ "$ignore" = false ] && ([ "${cpus}" -lt "${cpu_required}" ] || [ "${memory}" -lt "${mem_required}" ]); then
    echo "Insufficient resources. Requires a minimum of "${cpu_required}"  processors and  "${mem_required}" RAM."
    exit 1
fi

echo -e "${COLOR}[2/5]${ENDC} Checking for required TON components"
SOURCES_DIR=/usr/src
BIN_DIR=/usr/bin

# create dirs for OSX
if [[ "$OSTYPE" =~ darwin.* ]]; then
    SOURCES_DIR=/usr/local/src
    BIN_DIR=/usr/local/bin
    mkdir -p ${SOURCES_DIR}
fi

if [ ! -f ~/.config/pip/pip.conf ]; then  # create pip config
    mkdir -p ~/.config/pip
cat > ~/.config/pip/pip.conf <<EOF
[global]
break-system-packages = true
EOF
fi

# check TON components
file1=${BIN_DIR}/ton/crypto/fift
file2=${BIN_DIR}/ton/lite-client/lite-client
file3=${BIN_DIR}/ton/validator-engine-console/validator-engine-console

if  [ ! -f "${file1}" ] || [ ! -f "${file2}" ] || [ ! -f "${file3}" ]; then
    echo "TON does not exists, building"
    wget https://raw.githubusercontent.com/${author}/${repo}/${branch}/scripts/ton_installer.sh -O /tmp/ton_installer.sh
    bash /tmp/ton_installer.sh -c ${config} -v ${ton_node_version}
fi

# Cloning mytonctrl
echo -e "${COLOR}[3/5]${ENDC} Installing MyTonCtrl"
echo "https://github.com/${author}/${repo}.git -> ${branch}"

# remove previous installation
cd $SOURCES_DIR
rm -rf $SOURCES_DIR/mytonctrl
pip3 uninstall -y mytonctrl

git clone --branch ${branch} --recursive https://github.com/${author}/${repo}.git ${repo}  # TODO: return --recursive back when fix libraries
git config --global --add safe.directory $SOURCES_DIR/${repo}
cd $SOURCES_DIR/${repo}

pip3 install -U .  # TODO: make installation from git directly

echo -e "${COLOR}[4/5]${ENDC} Running mytoninstaller"
# DEBUG

if [ "${user}" = "" ]; then  # no user
    parent_name=$(ps -p $PPID -o comm=)
    user=$(whoami)
    if [ "$parent_name" = "sudo" ] || [ "$parent_name" = "su" ] || [ "$parent_name" = "python3" ]; then
        user=$(logname)
    fi
fi
echo "User: $user"
python3 -m mytoninstaller -u ${user} -t ${telemetry} --dump ${dump} -m ${mode} --only-mtc ${only_mtc} --backup ${backup} --only-node ${only_node}

# set migrate version
migrate_version=1
version_dir="/home/${user}/.local/share/mytonctrl"
version_path="${version_dir}/VERSION"
mkdir -p ${version_dir}
echo ${migrate_version} > ${version_path}
chown ${user}:${user} ${version_dir} ${version_path}

# create symbolic link if branch not eq mytonctrl
if [ "${repo}" != "mytonctrl" ]; then
    ln -sf ${SOURCES_DIR}/${repo} ${SOURCES_DIR}/mytonctrl
fi

echo -e "${COLOR}[5/5]${ENDC} Mytonctrl installation completed"
exit 0
