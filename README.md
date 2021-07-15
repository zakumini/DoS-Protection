# DoS-Protection
## Script for protect your system from dos-attack on 7 layer
## Original Author                       
### Original Author: Zaf zaf@vsnl.com (Copyright (C) 2005)  						 
### Jefferson González jgmdev@gmail.com                                                                         
### Marc S. Brooks devel@mbrooks.info  

## Install
### Ubuntu/Debian
 #### $sudo apt-get install net-tools dsniff grepcidr -y
#### $git clone https://github.com/zakumini/DoS-Protection.git
#### $cd DoS-Protection
#### $chmod 700  install.sh uninstall.sh
#### $sudo ./install
#### $sudo nano /etc/dos/config/dos.conf
 ### Add "URL your website or server" and "Your LINE TOKEN" in below file (site="" ACCESS_TOKEN="") And save dos.conf file
 ### Start DoS-Protection
#### $sudo dos -d
 ### How to use
 #### $ dos -h
 #### DoS-Protection version 1.0
 #### Usage: dos [OPTIONS] [N]
 #### N : number of tcp/udp connections (default 50)
 #### OPTIONS:
 #### -h      | --help: Show this help screen
 #### -i      | --ignore-list: List whitelisted ip addresses
 #### -b      | --bans-list: List currently banned ip addresses.
 #### -v      | --view: Display active connections to the server
 #### -u      | --unban: Unbans a given ip address.
 #### -d      | --start: Initialize a daemon to monitor connections
 #### -s      | --stop: Stop the daemon
 #### -t      | --status: Show status of daemon and pid if currently running
 #### -k      | --kill: Block all ip addresses making more than N connections

## Uninstall
#### $sudo ./uninstall.sh

