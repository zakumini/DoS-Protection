#!/bin/bash
##############################################################################
## Develop by                                                               ##
## Billy  <zakumi54@gmail.com>                                              ##      
## Original Author: Zaf <zaf@vsnl.com>                                      ##
## Contributors:                                                            ##
## Jefferson González <jgmdev@gmail.com>                                    ##
## Marc S. Brooks <devel@mbrooks.info>                                      ##
##############################################################################


# Variables
CONF_PATH="/etc/dos"
CONF_PATH="${CONF_PATH}/"
BANS_IP_LIST="/var/lib/dos/bans.list"
SERVER_IP_LIST=$(ifconfig | \
    grep -E "inet6? " | \
    sed "s/addr: /addr:/g" | \
    awk '{print $2}' | \
    sed -E "s/addr://g" | \
    sed -E "s/\\/[0-9]+//g"
)
SERVER_IP4_LIST=$(ifconfig | \
    grep -E "inet " | \
    sed "s/addr: /addr:/g" | \
    awk '{print $2}' | \
    sed -E "s/addr://g" | \
    sed -E "s/\\/[0-9]+//g" | \
    grep -v "127.0.0.1"
)
SERVER_IP6_LIST=$(ifconfig | \
    grep -E "inet6 " | \
    sed "s/addr: /addr:/g" | \
    awk '{print $2}' | \
    sed -E "s/addr://g" | \
    sed -E "s/\\/[0-9]+//g" | \
    grep -v "::1"
)

SS_MISSING=false
if ! command -v ss>/dev/null; then
    SS_MISSING=true
fi

load_conf()
{
    CONF="${CONF_PATH}dos.conf"
    if [ -f "$CONF" ] && [ -n "$CONF" ]; then
        . $CONF
    else
        dos_head
        echo "\$CONF not found."
        exit 1
    fi
}

dos_head()
{
    echo "Dos-Protection version 1.0"
    echo
}

showhelp()
{
    dos_head
    echo 'Usage: dos [OPTIONS] [N]'
    echo 'N : number of tcp/udp connections (default '"$NO_OF_CONNECTIONS"')'
    echo
    echo 'OPTIONS:'
    echo '-h      | --help: Show this help screen'
    echo '-i      | --ignore-list: List whitelisted ip addresses'
    echo '-b      | --bans-list: List currently banned ip addresses.'
    echo '-v      | --view: Display active connections to the server'
    echo '-u      | --unban: Unbans a given ip address.'
    echo '-d      | --start: Initialize a daemon to monitor connections'
    echo '-s      | --stop: Stop the daemon'
    echo '-t      | --status: Show status of daemon and pid if currently running'
    echo '-k      | --kill: Block all ip addresses making more than N connections'

}

# Check if super user is executing the
# script and exit with message if not.
su_required()
{
    user_id=$(id -u)

    if [ "$user_id" != "0" ]; then
        echo "You need super user priviliges for this."
        exit
    fi
}

log_msg()
{
    if [ ! -e /var/log/dos.log ]; then
        touch /var/log/dos.log
        chmod 0640 /var/log/dos.log
    fi

    echo "$(date +'[%Y-%m-%d %T]') $1" >> /var/log/dos.log
}

# Gets a list of ip address to ignore with hostnames on the
# ignore_host_list resolved to ip numbers
# param1 can be set to 1 to also include the bans list
ignore_list()
{
    for the_host in $(grep -v "#" "${CONF_PATH}${IGNORE_HOST_LIST}"); do
        host_ip=$(nslookup "$the_host" | tail -n +3 | grep "Address" | awk '{print $2}')

        # In case an ip is given instead of hostname
        # in the ignore.hosts.list file
        if [ "$host_ip" = "" ]; then
            echo "$the_host"
        else
            for ips in $host_ip; do
                echo "$ips"
            done
        fi
    done

    grep -v "#" "${CONF_PATH}${IGNORE_IP_LIST}"

    if [ "$1" = "1" ]; then
        cut -d" " -f2 "${BANS_IP_LIST}"
    fi
}

# Bans a given ip using iptables
# param1 The ip address to block
ban_ip()
{
    # iptables ban an ip address
    iptables -I INPUT -s "$1" -j DROP     

}

# Unbans an ip.
# param1 The ip address
# param2 Optional amount of connections the unbanned ip did.
unban_ip()
{
    if [ "$1" = "" ]; then
        return 1
    fi
    # iptables un ban ip address
    iptables -D INPUT -s "$1" -j DROP
      
    if [ "$2" != "" ]; then
        log_msg "Unbanned $1 that opened $2 connections"
        line=`curl -X POST -H "Authorization: Bearer $ACCESS_TOKEN" \
        -F "message=Unbanned $1 that opened $2 connections" https://notify-api.line.me/api/notify`
    else
        log_msg "Unbanned $1"
        line=`curl -X POST -H "Authorization: Bearer $ACCESS_TOKEN" \
        -F "message=Unbanned $1 as Admin" https://notify-api.line.me/api/notify`
    fi

    grep -v "$1" "${BANS_IP_LIST}" > "${BANS_IP_LIST}.tmp"
    rm "${BANS_IP_LIST}"
    mv "${BANS_IP_LIST}.tmp" "${BANS_IP_LIST}"

    return 0
}

# Unbans ip's after the amount of time given on BAN_PERIOD
unban_ip_list()
{
    current_time=$(date +"%s")

    while read line; do
        if [ "$line" = "" ]; then
            continue
        fi

        ban_time=$(echo "$line" | cut -d" " -f1)
        ip=$(echo "$line" | cut -d" " -f2)
        connections=$(echo "$line" | cut -d" " -f3)

        if [ "$current_time" -gt "$ban_time" ]; then
            unban_ip "$ip" "$connections"
        fi
    done < $BANS_IP_LIST
}


# Get table of ip connections from ss or netstat. Makes netstat output
# similar to that of ss in order for functions that use this to assume
# ss output format.
# param1 optional ipversion can be 4 oR 6
# param2 If not empty means listening services should be returned.
get_connections()
{
    # Find all connections
    if [ "$2" = "" ]; then
        if ! $SS_MISSING; then
            ss -ntu"$1" \
                state $(echo "$CONN_STATES" | sed 's/:/ state /g') | \
                # fixing dependency on '-H' switch which is unavailable in some versions of ss
                tail -n +2 | \
                # Fix possible ss bug
                sed -E "s/(tcp|udp)/\\1 /g"
        else
            netstat -ntu"$1" | tail -n+3 | grep -E "$CONN_STATES_NS" | \
                # Add [] brackets and prepend dummy column to match ss output
                awk '{
                    if($1 == "tcp6" || $1 == "udp6") {
                        gsub(/:[0-9]+$/, "]&", $4)
                        gsub(/:[0-9]+$/, "]&", $5)

                        print "col " $1 " " $2 " " $3 " [" $4 " [" $5;
                    } else {
                        print "col " $1 " " $2 " " $3 " " $4 " " $5;
                    }
                }'
        fi
    # Find listening services
    else
        if ! $SS_MISSING; then
            # state unconnected used to also include udp services
            ss -ntu"$1" state listening state unconnected | \
                tail -n +2 | \
                # Fix possible ss bug and convert *:### to [::]:###
                sed -E "s/(tcp|udp)/\\1 /g; s/ *:([0-9]+) / [::]:\\1 /g"
        else
            netstat -ntul"$1" | tail -n+3 | \
                # Add [] brackets and prepend dummy column to match ss output
                awk '{
                    if($1 == "tcp6" || $1 == "udp6") {
                        gsub(/:[0-9]+$/, "]&", $4)
                        gsub(/:([0-9]+|\*)$/, "]&", $5)

                        print "col " $1 " " $2 " " $3 " [" $4 " [" $5;
                    } else {
                        print "col " $1 " " $2 " " $3 " " $4 " " $5;
                    }
                }'
        fi
    fi
}

# Count incoming and outgoing connections and stores those that exceed
# max allowed on a given file.
# param1 File used to store the list of ip addresses as: conn_count ip
ban_incoming_and_outgoing()
{
    whitelist=$(ignore_list "1")

    # Find all connections
    get_connections | \
        # Extract the client ip
        awk '{print $6}' | \
        # Strip port and [ ] brackets
        sed -E "s/\\[//g; s/\\]//g; s/:[0-9]+$//g" | \
        # Only leave non whitelisted, we add ::1 to ensure -v works for ipv6
        grepcidr -v -e "$SERVER_IP_LIST $whitelist ::1" 2>/dev/null | \
        # Sort addresses for uniq to work correctly
        sort | \
        # Group same occurrences of ip and prepend amount of occurences found
        uniq -c | \
        # sort by number of connections
        sort -nr | \
        # Only store connections that exceed max allowed
        awk "{ if (\$1 >= $NO_OF_CONNECTIONS) print; }" > \
        "$1"
}

# Count incoming connections only and stores those that exceed
# max allowed on a given file.
# param1 File used to store the list of ip addresses as: conn_count ip
# Check active connections and ban if neccessary.
ban_only_incoming()
{
    whitelist=$(ignore_list "1")

    ALL_LISTENING=$(mktemp "$TMP_PREFIX".XXXXXXXX)
    ALL_LISTENING_FULL=$(mktemp "$TMP_PREFIX".XXXXXXXX)
    ALL_CONNS=$(mktemp "$TMP_PREFIX".XXXXXXXX)
    ALL_SERVER_IP=$(mktemp "$TMP_PREFIX".XXXXXXXX)
    ALL_SERVER_IP6=$(mktemp "$TMP_PREFIX".XXXXXXXX)

    # Find all connections
    get_connections | \
        # Extract both local and foreign address:port
        awk '{print $5" "$6;}' > \
        "$ALL_CONNS"

    # Find listening connections
    get_connections " " "l" | \
        # Only keep local address:port
        awk '{print $5}' > \
        "$ALL_LISTENING"

    # Also append all server addresses when address is 0.0.0.0 or [::]
    echo "$SERVER_IP4_LIST" > "$ALL_SERVER_IP"
    echo "$SERVER_IP6_LIST" > "$ALL_SERVER_IP6"

    awk '
    FNR == 1 { ++fIndex }
    fIndex == 1{ip_list[$1];next}
    fIndex == 2{ip6_list[$1];next}
    {
        ip_pos = index($0, "0.0.0.0");
        ip6_pos = index($0, "[::]");
        if (ip_pos != 0) {
            port_pos = index($0, ":");
            print $0;
            for (ip in ip_list){
                print ip substr($0, port_pos);
            }
        } else if (ip6_pos != 0) {
            port_pos = index($0, "]:");
            print $0;
            for (ip in ip6_list){
                print "[" ip substr($0, port_pos);
            }
        } else {
            print $0;
        }
    }
    ' "$ALL_SERVER_IP" "$ALL_SERVER_IP6" "$ALL_LISTENING" > "$ALL_LISTENING_FULL"

    # Only keep connections which are connected to local listening service
    awk 'NR==FNR{a[$1];next} $1 in a {print $2}' "$ALL_LISTENING_FULL" "$ALL_CONNS" | \
        # Strip port and [ ] brackets
        sed -E "s/\\[//g; s/\\]//g; s/:[0-9]+$//g" | \
        # Only leave non whitelisted, we add ::1 to ensure -v works
        grepcidr -v -e "$SERVER_IP_LIST $whitelist ::1" 2>/dev/null | \
        # Sort addresses for uniq to work correctly
        sort | \
        # Group same occurrences of ip and prepend amount of occurences found
        uniq -c | \
        # Numerical sort in reverse order
        sort -nr | \
        # Only store connections that exceed max allowed
        awk "{ if (\$1 >= $NO_OF_CONNECTIONS) print; }" > \
        "$1"

    # remove temp files
    rm "$ALL_LISTENING" "$ALL_LISTENING_FULL" "$ALL_CONNS" \
        "$ALL_SERVER_IP" "$ALL_SERVER_IP6"
}
check_connections()
{
    su_required
    TMP_PREFIX='/tmp/dos'
    TMP_FILE="mktemp $TMP_PREFIX.XXXXXXXX"
    BAD_IP_LIST=$($TMP_FILE)

    if $ONLY_INCOMING; then
        bah_only_incoming "$BAD_IP_LIST"
    else
        ban_incoming_and_outgoing "$BAD_IP_LIST"
    fi

    
    FOUND=$(cat "$BAD_IP_LIST")

    if [ "$FOUND" = "" ]; then
        rm -f "$BAD_IP_LIST"

        if [ "$KILL" -eq 1 ]; then
            echo "No connections exceeding max allowed."
        fi

        return 0
    fi

    if [ "$KILL" -eq 1 ]; then
        echo "List of connections that exceed max allowed"
        echo "==========================================="
        cat "$BAD_IP_LIST"
    fi

    BANNED_IP_LIST=$($TMP_FILE)
    IP_BAN_NOW=0

    FIELDS_COUNT=$(head -n1 "$BAD_IP_LIST" | xargs | sed "s/ /\\n/g" | wc -l)
    
    while read line; do
        BAN_TOTAL="$BAN_PERIOD"

        CURR_LINE_CONN=$(echo "$line" | cut -d" " -f1)
        CURR_LINE_IP=$(echo "$line" | cut -d" " -f2)

        if [ "$FIELDS_COUNT" -gt 2 ]; then
            BAN_TOTAL=$(echo "$line" | cut -d" " -f4)
        fi


        IP_BAN_NOW=1
        echo "${CURR_LINE_IP}" >> "$BANNED_IP_LIST"
        current_time=$(date +"%s")
        echo "$((current_time+BAN_TOTAL)) ${CURR_LINE_IP} ${CURR_LINE_CONN}" >> "${BANS_IP_LIST}"
        
        # execute tcpkill for 60 seconds
        timeout -k 60 -s 9 60 \
            tcpkill -9 host "$CURR_LINE_IP" > /dev/null 2>&1 &

        ban_ip "$CURR_LINE_IP"
        line=`curl -X POST -H "Authorization: Bearer $ACCESS_TOKEN" \
        -F "message=banned IP: $CURR_LINE_IP with $CURR_LINE_CONN connections for ban period $BAN_TOTAL"\
        https://notify-api.line.me/api/notify`
        log_msg "Banned ${CURR_LINE_IP} with $CURR_LINE_CONN connections for ban period $BAN_TOTAL"
        statusCode
    done < "$BAD_IP_LIST"
    
    if [ "$IP_BAN_NOW" -eq 1 ]; then
        if [ "$KILL" -eq 1 ]; then
            echo "==========================================="
            echo "Banned IP addresses:"
            echo "==========================================="
            cat "$BANNED_IP_LIST"
        fi
    fi

    rm -f "$TMP_PREFIX".*
}

ip_to_hex()
{
    printf '%02x' "$(echo "$1" | sed "s/\\./ /g")"
}

# Active connections to server.
view_connections()
{
    ip6_show=false
    ip4_show=false

    if [ "$1" = "6" ]; then
        ip6_show=true
    elif [ "$1" = "4" ]; then
        ip4_show=true
    else
        ip6_show=true
        ip4_show=true
    fi

    whitelist=$(ignore_list "1")

    # Find all ipv4 connections
    if $ip4_show; then
        get_connections "4" | \
            # Extract only the fifth column
            awk '{print $6}' | \
            # Strip port
            cut -d":" -f1 | \
            # Sort addresses for uniq to work correctly
            sort | \
            # Only leave non whitelisted
            grepcidr -v -e "$SERVER_IP_LIST $whitelist" 2>/dev/null | \
            # Group same occurrences of ip and prepend amount of occurences found
            uniq -c | \
            # Numerical sort in reverse order
            sort -nr
    fi

    # Find all ipv6 connections
    if $ip6_show; then
        get_connections "6" | \
            # Extract only the fifth column
            awk '{print $6}' | \
            # Strip port and leading [
            sed -E "s/]:[0-9]+//g" | sed "s/\\[//g" | \
            # Sort addresses for uniq to work correctly
            sort | \
            # Only leave non whitelisted, we add ::1 to ensure -v works
            grepcidr -v -e "$SERVER_IP_LIST $whitelist ::1" 2>/dev/null | \
            # Group same occurrences of ip and prepend amount of occurences found
            uniq -c | \
            # Numerical sort in reverse order
            sort -nr
    fi
}

view_bans()
{
    echo "List of currently banned ip's."
    echo "==================================="

    if [ -e "$BANS_IP_LIST" ]; then
        printf "% -5s %s\\n" "Exp." "IP"
        echo '-----------------------------------'
        while read line; do
            time=$(echo "$line" | cut -d" " -f1)
            ip=$(echo "$line" | cut -d" " -f2)
            conns=$(echo "$line" | cut -d" " -f3)
            port=$(echo "$line" | cut -d" " -f4)

            current_time=$(date +"%s")
            hours=$(echo $(((time-current_time)/60/60)))
            minutes=$(echo $(((time-current_time)/60%60)))

            echo "$(printf "%02d" "$hours"):$(printf "%02d" "$minutes") $ip $port $conns"
        done < "$BANS_IP_LIST"
    fi
}

# Executed as a cleanup function when the daemon is stopped
on_daemon_exit()
{
    stop_bandwidth_control

    pkill -9 tcpdump

    if [ -e /var/run/dos.pid ]; then
        rm -f /var/run/dos.pid
    fi

    exit 0
}

# Return the current process id of the daemon or 0 if not running
daemon_pid()
{
    if [ -e "/var/run/dos.pid" ]; then
        echo $(cat /var/run/dos.pid)

        return
    fi

    echo "0"
}

# Check if daemon is running.
# Outputs 1 if running 0 if not.
daemon_running()
{
    if [ -e /var/run/dos.pid ]; then
        running_pid=$(pgrep dos)

        if [ "$running_pid" != "" ]; then
            current_pid=$(daemon_pid)

            for pid_num in $running_pid; do
                if [ "$current_pid" = "$pid_num" ]; then
                    echo "1"
                    return
                fi
            done
        fi
    fi

    echo "0"
}

start_daemon()
{
    su_required

    if [ "$(daemon_running)" = "1" ]; then
        echo "DoS daemon is already running..."
        exit 0
    fi

    echo "starting DoS daemon..."

    if [ ! -e "$BANS_IP_LIST" ]; then
        touch "${BANS_IP_LIST}"
    fi

    nohup "$0" -l > /dev/null 2>&1 &

    log_msg "DoS daemon started"
}

stop_daemon()
{
    su_required

    if [ "$(daemon_running)" = "0" ]; then
        echo "DoS daemon is not running..."
        exit 0
    fi

    echo "stopping DoS daemon..."

    kill "$(daemon_pid)"

    while [ -e "/var/run/dos.pid" ]; do
        continue
    done

    log_msg "DoS daemon stopped"
}

daemon_loop()
{
    su_required

    if [ "$(daemon_running)" = "1" ]; then
        exit 0
    fi

    echo "$$" > "/var/run/dos.pid"

    trap 'on_daemon_exit' INT
    trap 'on_daemon_exit' QUIT
    trap 'on_daemon_exit' TERM
    trap 'on_daemon_exit' EXIT


    if $ONLY_INCOMING; then
        echo "Ban only incoming connections that exceed $NO_OF_CONNECTIONS"
    else
        echo "Ban in/out connections that combined exceed $NO_OF_CONNECTIONS"
    fi
    # run unban lists after 10 seconds of initialization
    ban_check_timer=$(date +"%s")
    ban_check_timer=$((ban_check_timer+10))

    echo "Monitoring connections!"
    while true; do
        check_connections
        # unban expired ip's every 1 minute
        current_loop_time=$(date +"%s")
        if [ "$current_loop_time" -gt "$ban_check_timer" ]; then 
            unban_ip_list        
            ban_check_timer=$(date +"%s")
            ban_check_timer=$((ban_check_timer+60))
        fi

        sleep "$DAEMON_FREQ"
    done
}

daemon_status()
{
    current_pid=$(daemon_pid)

    if [ "$(daemon_running)" = "1" ]; then
        echo "DoS Protection status: running with pid $current_pid"
    else
        echo "DoS Protection status: not running"
    fi
}
statusCode()
{
    HTTP_CODE=`curl -sL -w "%{http_code}" "${site}" -o /dev/null`
    if [ "$HTTP_CODE" != "200" ]; then
        line_msg2="Website something wrong happened[status code:$HTTP_CODE]"
        line=`curl -X POST -H "Authorization: Bearer $ACCESS_TOKEN" \
        -F "message=$line_msg2" https://notify-api.line.me/api/notify`
    
    fi

}

# Set Default settings
PROGDIR="/usr/local/dos"
SBINDIR="/usr/local/sbin"
PROG="$PROGDIR/dos.sh"
IGNORE_IP_LIST="ignore_ip.list"
IGNORE_HOST_LIST="ignore_host.list"
IPT="/sbin/iptables"
IPT6="/sbin/ip6tables"
TC="/sbin/tc"
FREQ=1
NO_OF_CONNECTIONS=50
BAN_PERIOD=600
CONN_STATES="connected"
CONN_STATES_NS="ESTABLISHED|SYN_SENT|SYN_RECV|FIN_WAIT1|FIN_WAIT2|TIME_WAIT|CLOSE_WAIT|LAST_ACK|CLOSING"
ONLY_INCOMING=false

# Load custom settings
load_conf



# Overwrite old configuration values
if echo "$CONN_STATES" | grep "|">/dev/null; then
    CONN_STATES="connected"
fi

KILL=0

while [ "$1" ]; do
    case $1 in
        '-h' | '--help' | '?' )
            showhelp 
            exit
            ;;
        '--ignore-list' | '-i' )
            echo "List of currently whitelisted ip's."
            echo "==================================="
            ignore_list
            exit
            ;;
        '--bans-list' | '-b' )
            view_bans
            exit
            ;;
        '--unban' | '-u' )
            su_required
            shift

            if ! unban_ip "$1"; then
                echo "Please specify a valid ip address."
            fi
            exit
            ;;
        '--start' | '-d' )
            start_daemon
            exit
            ;;
        '--stop' | '-s' )
            stop_daemon
            exit
            ;;
        '--status' | '-t' )
            daemon_status
            exit
            ;;
        '--loop' | '-l' )
            # start daemon loop, used internally by --start | -s
            daemon_loop
            exit
            ;;
        '--view' | '-v' )
            shift
            view_connections "$1"
            exit
            ;;
        '--kill' | '-k' )
            su_required
            KILL=1
            ;;
        *[0-9]* )
            NO_OF_CONNECTIONS=$1
            ;;
        * )
            showhelp
            exit 
            ;;
    esac

    shift
done

if [ $KILL -eq 1 ]; then
    check_connections
else
    showhelp
fi

exit 0
