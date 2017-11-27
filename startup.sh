#!/bin/bash

#### Global Variables ####
DEBUG=0
VERBOSE=""
CONTAINERS=("macadmins/tftpd" "macadmins/netboot-httpd" "bruienne/bsdpy:1.0")
BOOT_IMAGES_PATH="/nbi"
NETWORK_INTERFACE="eth0"
IP=""
max_loops=5
loops=0
#### Functions ####
usage()
{
	echo ""
	echo "	Usage for $0:"
	echo "	Optional Flags:"
	echo "		-h: Display this dialog"
	echo "		-d: Enable Debugging."
	echo "	Required Flags:"
	echo ""
}
print()
{
	local OPTIND
	if [ "$(uname -s)" == "Darwin" ];then
		Black='\033[0;30m'        # Black
		Red='\033[0;31m'          # Red
		Green='\033[0;32m'        # Green
		Yellow='\033[0;33m'       # Yellow
		Blue='\033[0;34m'         # Blue
		Purple='\033[0;35m'       # Purple
		Cyan='\033[0;36m'         # Cyan
		White='\033[0;37m'        # White
		NC='\033[m'               # Color Reset
	else 
		Black='\e[0;30m'        # Black
		Red='\e[0;31m'          # Red
		Green='\e[0;32m'        # Green
		Yellow='\e[0;33m'       # Yellow
		Blue='\e[0;34m'         # Blue
		Purple='\e[0;35m'       # Purple
		Cyan='\e[0;36m'         # Cyan
		White='\e[0;37m'        # White
		NC="\e[m"               # Color Reset
	fi
	colors=( "$Red" "$Green" "$Gellow" "$Blue" "$Purple" "$Cyan" )
	local DEBUG=0
	FGND=""
	NL=1
	PNL=0
	STRING=" "
	while getopts "f:npKRGYBPCWS:" opt
	do
		case "$opt" in
			"f")					# Set foreground/text color.
				case "$OPTARG" in
					"black") FGND="$Black";;
					"red") FGND="$Red";;
					"green") FGND="$Green";;
					"yellow") FGND="$Yellow";;
					"blue") FGND="$Blue";;
					"purple") FGND="$Purple";;
					"cyan") FGND="$Cyan";;
					"white") FGND="$White";;
					"*") [ $DEBUG -eq 1 ] && echo "Unrecognized Arguement: $OPTARG" ;;
				esac
				;;
			"n") NL=0 ;;	 			# Print with newline.
			"p") ((PNL++)) ;; 			# Prepend with newline.
			"K") FGND="$Black";;
			"R") FGND="$Red";;
			"G") FGND="$Green";;
			"Y") FGND="$Yellow";;
			"B") FGND="$Blue";;
			"P") FGND="$Purple";;
			"C") FGND="$Cyan";;
			"W") FGND="$White";;
			"D") local DEBUG=1 ;;
			"S") STRING="$OPTARG" ;;
			"*") [ $DEBUG -eq 1 ] && echo "Unknown Arguement: $opt" ;;
		esac
	done
	if [[ "$STRING" == " " ]];then
		shift "$((OPTIND - 1))"
		STRING="$@" 
	fi
	if [ $DEBUG -eq 1 ]; then
		echo "FGND: $FGND"
		echo "NL: $NL"
		echo "PNL: $PNL"
		echo "STRING: $STRING"
	fi
	while [ $PNL -ne 0 ] 
	do
		printf "\n"
		((PNL--))
	done
	[ ! -z $FGND ] && STRING="$FGND$STRING$NC"
	printf -- "$STRING"
	[ $NL -eq 1 ] && printf "\n"
}
loop_gaurd()
{
        ((++loops))
        [ $loops -gt $max_loops ] && print -R "Loop Gaurd detected loops exceeded max loops: $max_loops" && exit 1
}
is_root()
{
	if [ "$(id -u)" -ne "0" ]; then
		print -R "Must run as root. Exiting."
		usage
		exit 1
	fi
}
get_system_details()
{
	ARCH="$(uname -s)"
	case "$ARCH" in
		"Darwin")
			[ $DEBUG -eq 1 ] && print -B "Detected Mac OS: $ARCH. Setting OS=mac."
			OS="MAC"
			;;
		"Linux")
			[ $DEBUG -eq 1 ] && print -B "Detected linux OS. Attempting to determine flavor..."
			if [ -f "/etc/os-release" ];then
				r=($(cat "/etc/os-release"))
				for d in "${r[@]}"
				do
					[ $DEBUG -eq 1 ] && print -B "Checking $d for ID..."
					if [[ "$(echo "$d" | cut -d"=" -f 1)" == "ID" ]];then
						OS="$(echo "$d" | cut -d"=" -f 2)"
						[ $DEBUG -eq 1 ] && print -B "Found ID. Setting OS=$OS"
						break
					fi
				done
			else
				print -R "Can't determine linux flavor."
			fi
			;;
		*)
			print -R "Unsupported architecture: $ARCH"
			exit 1
			;;
	esac
}
get_ip()
{
	ifconfig "$NETWORK_INTERFACE" >& /dev/null
	if [ $? -eq 0 ];then
		IP="$(ifconfig "$NETWORK_INTERFACE" >& /dev/null | awk '/inet / {print $2}'|sed -e 's/inet//g' -e 's/addr://g')"
		[ $DEBUG -eq 1 ] && print -B "Using IP: $IP"
	else
		print -R "Invalid network interface: $NETWORK_INTERFACE."
		IFACES=( $(ifconfig -s | awk 'NR>1 {print $1}') )
		count=0
		for i in "${IFACES[@]}"
		do
			print -Y "[$count] $i"
			((count++))
		done
		selection=$(expr $count + 1)
		while [ "$select" -gt "${#IFACES[@]}" -o "$select" -lt 0 ]
		do
			print -n -Y "Select an interface: "
			read -n 1 select
			if [[ $select =~ ^-?[0-9]+$ ]];then
				[ $DEBUG -eq 1 ] && print -B "$select is a number."
			else
				print -R "Invalid entry. Try again."
				selection=$(expr $count + 1)
			fi
		done
		NETWORK_INTERFACE="${IFACES[$select]}"
		get_ip
	fi
}
setup_image_path()
{
	if [ -d "$BOOT_IMAGES_PATH" ];then
		chmod -R 777 "$BOOT_IMAGES_PATH"
	else
		print -R "Missing boot images path."
		exit 1
	fi
}
start_services()
{
	docker run -d \
	  -v "$BOOT_IMAGES_PATH":/nbi \
	  --name web \
	  --restart=always \
	  -p 0.0.0.0:80:80 \
	  macadmins/netboot-httpd

	docker run -d \
	  -p 0.0.0.0:69:69/udp \
	  -v "$BOOT_IMAGES_PATH":/nbi \
	  --name tftpd \
	  --restart=always \
	  macadmins/tftpd

	docker run -d \
	  -p 0.0.0.0:67:67/udp \
	  -v "$BOOT_IMAGES_PATH":/nbi \
	  -e BSDPY_IFACE="$NETWORK_INTERFACE" \
	  -e BSDPY_NBI_URL=http://$IP \
	  -e BSDPY_IP=$IP \
	  --name bsdpy \
	  --restart=always \
	  bruienne/bsdpy:1.0
}
get_user_reply()
{
	if [ $# -lt 1 ];then
		print -R "Missing question."
		exit 1
	fi
	print -n -Y "$1 [y/n]"
	read -n 1 reply
	print ""
	case "$reply" in
		"y"|"Y")
			return 1
			;;
		"n"|"N")
			return 0
			;;
		*)
			print -R "Unrecognized response: $reply"
			get_user_reply "$1"
			;;
	esac
}
setup_docker_env()
{
	d=($(docker ps -qa))
	if [ ${#d[@]} -gt 1 ]; then
		print -R "Detected ${#d[@]} docker container(s) running."
		get_user_reply "Would you like to stop and remove them?"
		if [ $? -eq 1 ]; then
			docker stop $(docker ps -qa)
			docker rm $(docker ps -qa)
		else
			print -Y "Continuing without stopping the following containers:"
			docker ps
		fi
	fi
	for d in "${CONTAINERS[@]}"
	do
		docker pull "$d"
	done
}
check_requirements()
{
	case "$OS" in
		"centos")
			rpm -q "docker-ce" >& /dev/null
			if [ $? -eq 0 ]; then
				[ $DEBUG -eq 1 ] && print -B "Found docker-ce."
				systemctl status docker >& /dev/null
				loops=0
				while [ $? -ne 0 ]
				do
					loop_gaurd
					print -R "Docker is not running. Attempting to start."
					systemctl start docker
					sleep 2
				done
			else
				print -R "Missing Docker CE requirement."
				get_user_reply "Would you like to install now?"
				if [ $? -eq 1 ]; then
					install_requirements
				else
					print -R "Aborting install."
					exit 1
				fi
			fi
				;;
		*)
			print -R "Unsupported OS: $OS"
			exit 1
			;;
	esac
}
install_requirements()
{
	case "$OS" in
		"centos")
			packages=("yum-utils" "device-mapper-persistent-data" "lvm2")
			for p in "${packages[@]}"
			do
				yum install "$p" -y
			done
			yum-config-manager --add-repo "https://download.docker.com/linux/centos/docker-ce.repo"
			yum install docker-ce -y
			systemctl enable docker
			systemctl start docker
			;;
		*)
			print -R "Unsupported OS: $OS"
			exit 1
			;;
	esac

}
#### Main Run ####
is_root
if [ $# -lt 1 ]; then
	print -R "Missing arguments"
	usage
	exit 1
else
	while getopts "hd" opt
	do
		case "$opt" in
			"h")
				usage
				;;
			"d")
				DEBUG=1
				VERBOSE="v"
				;;
			"*")
				print -R "Unrecognized Argument: $opt"
				usage
				exit 1
				;;
		esac
	done
fi
if [ $DEBUG -eq 1 ]; then
	print -B "DEBUG: $DEBUG"
fi
get_system_details
check_requirements
setup_docker_env
get_ip
setup_image_path
start_services
echo "Tailing Logs..."
docker exec -it  bsdpy tail -f /var/log/bsdpserver.log
exit 0
