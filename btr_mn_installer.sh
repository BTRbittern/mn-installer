#!/bin/bash
# Author Alexander Khudyakov
# Copyright (c) 2020-2020 The BITTERN developers

declare -r COIN_NAME='bittern'
declare -r COIN_DAEMON="${COIN_NAME}d"
declare -r COIN_CLI="${COIN_NAME}-cli"
declare -r COIN_PATH='/usr/local/bin'
declare -r COIN_ARH='https://github.com/BTRbittern/BITTERN/releases/download/V1.0.0.0/bittern-ubuntu18-cli-d.tar.gz'
declare -r COIN_TGZ=$(echo ${COIN_ARH} | awk -F'/' '{print $NF}')
declare -r COIN_PORT=42021
declare -r COIN_RPC_PORT=42020
declare -r CONFIG_FILE="${COIN_NAME}.conf"
declare -r CONFIG_FOLDER="${HOME}/.${COIN_NAME}"
declare -r SERVICE_FILE="/etc/systemd/system/${COIN_DAEMON}.service"
declare -r TMP_FOLDER="${HOME}/${COIN_NAME}/tmp"
declare -r BLUE="\033[0;34m"
declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r NC='\033[0m'

function start_setup() {
  echo -e "${BLUE}"
  echo -e " Author Alexander Khudyakov "
  echo -e ""
  echo -e "   ______  _______  _____   "
  echo -e "  |  __  ||__   __||  __ \  "
  echo -e "  | |__) |   | |   | |__) | "
  echo -e "  |  ___ \   | |   |  _  /  "
  echo -e "  | |___) |  | |   | | \ \  "
  echo -e "  |_______|  |_|   |_|  \_\ "
  echo -e ""
  echo -e "${NC}"
  echo -e "${BLUE}Welcome to the BITTERN masternode installation${NC}"
  echo -e ""
  echo -e "${RED}Do you want to install BITTERN masternode?${NC}"
  echo -e ""
}

function check_system() {
    echo -e "* Checking system for compatibilities"
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi
	
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
	echo -e "Verision ${VERSION_ID}"
	if [[ "${VERSION_ID}" != "16.04" ]] && [[ "${VERSION_ID}" != "18.04" ]] ; then
		echo -e "This script only supports Ubuntu 16.04 & 18.04 LTS, exiting."
		exit 1
	fi
else
    echo -e "This script only supports Ubuntu 16.04 & 18.04 LTS, exiting."
    exit 1
fi
MAIN_IP=$(wget -qO- https://api.ipify.org)
}

function create_mn_dirs() {
    echo -e "* Creating masternode directories"
    mkdir -p ${CONFIG_FOLDER}   
    mkdir -p ${TMP_FOLDER}      	
}

function download_binary(){
    echo -e "* Download binary files"
	cd 	${TMP_FOLDER}
	rm -f ${COIN_TGZ}
	if [[ ! -f "${TMP_FOLDER}/${COIN_TGZ}" ]]; then
		wget ${COIN_ARH}
	fi
	if [[ -f "${TMP_FOLDER}/${COIN_TGZ}" ]]; then
		tar xvzf "${TMP_FOLDER}/${COIN_TGZ}" --strip-components=1 -C ${TMP_FOLDER}
		chmod +x $COIN_DAEMON $COIN_CLI
		mv $COIN_DAEMON $COIN_CLI $COIN_PATH/
	fi
    rm -Rf "${HOME}/${COIN_NAME}"
}

function install_packages() {
    echo -e "* Package installation"
    apt-get -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true update 	
    apt-get -y -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true install dirmngr wget software-properties-common
    add-apt-repository -yu ppa:bitcoin/bitcoin 
    apt-get -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true update 
    apt-get -y -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true install build-essential \
    libboost-all-dev autotools-dev automake libssl-dev libcurl4-openssl-dev \
    libboost-all-dev make autoconf libtool git apt-utils g++ libzmq3-dev libminiupnpc-dev\
    libprotobuf-dev pkg-config libcurl3-dev libudev-dev libqrencode-dev bsdmainutils \
    pkg-config libssl-dev libgmp3-dev libevent-dev python-virtualenv virtualenv libdb4.8-dev libdb4.8++-dev libdb5.3++
    
    # only for 18.04 // openssl
if [[ "${VERSION_ID}" == "18.04" ]] ; then
       apt-get -qqy -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true install libssl1.0-dev libdb5.3++
fi
}

function create_config() {
    echo -e "* Creating config file ${CONFIG_FILE}"
if [[ ! -d "${CONFIG_FOLDER}" ]]; then mkdir -p ${CONFIG_FOLDER}; fi

if [[ ! -f "${CONFIG_FOLDER}/${CONFIG_FILE}" ]]; then
	RPCUSER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
	RPCPASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
	printf "%s\n" "rpcuser=${RPCUSER}" "rpcpassword=${RPCPASS}" "rpcport=${COIN_RPC_PORT}" "rpcallowip=127.0.0.1" "listen=1" "server=1" "daemon=1" > ${CONFIG_FOLDER}/${CONFIG_FILE}
	${COIN_DAEMON}
	sleep 30
	if [ -z "$(ps axo cmd:100 | grep ${COIN_DAEMON})" ]; then
	   echo -e "${RED}${COIN_NAME} server couldn not start. Check /var/log/syslog for errors.{$NC}"
	   exit 1
	fi
    MNPRIVKEY=$(${COIN_CLI} masternode genkey)
	if [ "$?" -gt "0" ];
		then
		echo -e "${RED}Wallet not fully loaded. Let us wait and try again to generate the Private Key${NC}"
		sleep 30
		MNPRIVKEY=$(${COIN_CLI} masternode genkey)
	fi
    ${COIN_CLI} stop	
	printf "%s\n" "" "externalip=${MAIN_IP}" "masternodeaddr=${MAIN_IP}:${COIN_PORT}" "masternode=1" "masternodeprivkey=${MNPRIVKEY}" >> ${CONFIG_FOLDER}/${CONFIG_FILE}
else
    echo -e "* Config file ${CONFIG_FILE} already exists!"
    . "${CONFIG_FOLDER}/${CONFIG_FILE}"
	MNPRIVKEY=${masternodeprivkey}
fi
}

function create_systemd_service() {

cat > ${SERVICE_FILE} <<-EOF
[Unit]
Description=${COIN_DAEMON} distributed currency daemon
After=network.target
[Service]
User=$(whoami)
Group=$(id -gn)
Type=forking
PIDFile=${CONFIG_FOLDER}/${COIN_DAEMON}.pid
ExecStart=${COIN_PATH}/${COIN_DAEMON} -pid=${CONFIG_FOLDER}/${COIN_DAEMON}.pid
ExecStop=${COIN_PATH}/${COIN_CLI} stop
PrivateTmp=true
[Install]
WantedBy=multi-user.target
EOF

if [ -n "$(ps axo cmd:100 | grep ${COIN_DAEMON})" ]; then
	${COIN_CLI} stop
	sleep 3
fi
systemctl daemon-reload
systemctl enable ${COIN_DAEMON}.service
systemctl start ${COIN_DAEMON}.service

sleep 3
}

function display_information() {
 echo
 echo -e "================================================================================================================================"
 echo -e "${COIN_NAME} Masternode is up and running listening on port ${GREEN}${COIN_PORT}${NC}."
 echo -e "Configuration folder is: ${RED}$CONFIG_FOLDER${NC}"
 echo -e "Configuration file is: ${RED}$CONFIG_FOLDER/$CONFIG_FILE${NC}"
 echo -e "Configuration masternode file is: ${RED}$CONFIG_FOLDER/masternode.conf${NC}"
 echo -e "Node start: ${RED}systemctl start ${COIN_DAEMON}.service${NC}"
 echo -e "Node restart: ${RED}systemctl restart ${COIN_DAEMON}.service${NC}"
 echo -e "Node stop: ${RED}systemctl stop ${COIN_DAEMON}.service${NC}"
 echo -e "VPS_IP:PORT ${RED}${MAIN_IP}:${COIN_PORT}${NC}"
 echo -e "MASTERNODE PRIVATEKEY is: ${RED}${MNPRIVKEY}${NC}"
 echo -e "Please check ${GREEN}$COIN_NAME${NC} is running with the following command: ${GREEN}systemctl status ${COIN_DAEMON}.service${NC}"
 echo -e "================================================================================================================================"
}

start_setup
check_system
install_packages
create_mn_dirs
download_binary
create_config
create_systemd_service
display_information

