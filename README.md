## BSDPy Server Initializer (bsdpserver-init) ##
Initialize a BSDPy Apple Netboot server. Based off of bruienne/bsdpy python script.

## Usage ##
	-h: Display this dialog
	-i interface: Set the network interface to bind to. Default: eth0
	-p absolute-path: Set the path to the boot images. Default: /nbi
	-d: Enable Debugging.
## Notes ##
Calling startup.sh with no arguments will initiate the startup process. It will attempt to use defaults, and ask questions for interfaces (if there are more than one) and docker containers (if there are some running).
