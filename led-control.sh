#! /bin/bash

#set -x

SCRIPTPATH=$(dirname "$0")
echo $SCRIPTPATH

devices=(p n x x x x)
map=(power netdev disk1 disk2 disk3 disk4)

# Check network status
gw=$(ip route | awk '/default/ { print $3 }')
if ping -q -c 1 -W 1 $gw >/dev/null; then
    devices[1]=u
fi

# Map sdX1 to hardware device
declare -A hwmap
echo "Mapping devices..."
while read line; do
    MAP=($line)
    device=${MAP[0]}
    hctl=${MAP[1]}
    partitions=$(lsblk -l -o NAME | grep "^${device}[0-9]\+$")
    for part in $partitions; do
        hwmap[$part]=${hctl:0:1}
        echo "Mapped $part to ${hctl:0:1}"
    done
done <<< "$(lsblk -S -o NAME,HCTL | tail -n +2)"

# Print the hwmap for verification
echo "Hardware mapping (hwmap):"
for key in "${!hwmap[@]}"; do
    echo "$key: ${hwmap[$key]}"
done

# Check status of zpool disks
echo "Checking zpool status..."
while read line; do
    DEV=($line)
    partition=${DEV[0]}
    echo "Processing $partition with status ${DEV[1]}"
    if [[ -n "${hwmap[$partition]}" ]]; then
        index=$((${hwmap[$partition]} + 2))
        echo "Device $partition maps to index $index"
        if [ ${DEV[1]} = "ONLINE" ]; then
            devices[$index]=o
        else
            devices[$index]=f
        fi
    else
        echo "Warning: No mapping found for $partition"
    fi
done <<< "$(zpool status -L | grep -E '^\s+sd[a-h][0-9]')"

# Check for alerts
alerts=$(midclt call alert.list)

if [[ ${#alerts} -gt 2 ]]; then
    if echo "$alerts" | grep -q -E "CRITICAL|ALERT|EMERGENCY"; then
        echo "There are critical alerts in the alert list"
        devices[0]=c
    elif echo "$alerts" | grep -q "ERROR"; then
        echo "There are error alerts in the alert list"
        devices[0]=e
    else
        echo "There are alerts in the alert list, but none are critical"
        devices[0]=a
    fi
else
    echo "There are no active alerts"
    devices[0]=p
fi

# Output the final device statuses
echo "Final device statuses:"
for i in "${!devices[@]}"; do
    echo "$i: ${devices[$i]}"
    case "${devices[$i]}" in
        p)
            "$SCRIPTPATH/ugreen_leds_cli" ${map[$i]} -color 255 255 255 -on -brightness 64
            ;;
        u)
            "$SCRIPTPATH/ugreen_leds_cli" ${map[$i]} -color 255 255 255 -on -brightness 64
            ;;
        o)
            "$SCRIPTPATH/ugreen_leds_cli" ${map[$i]} -color 0 255 0 -on -brightness 64
            ;;
        f)
            "$SCRIPTPATH/ugreen_leds_cli" ${map[$i]} -color 255 0 0 -blink 400 600 -brightness 64
            ;;
        a)
            "$SCRIPTPATH/ugreen_leds_cli" ${map[$i]} -color 255 200 0 -on -brightness 64
            ;;
        e)
            "$SCRIPTPATH/ugreen_leds_cli" ${map[$i]} -color 255 0 0 -on -brightness 64
            ;;
        c)
            "$SCRIPTPATH/ugreen_leds_cli" ${map[$i]} -color 255 0 0 -blink 400 600 -brightness 64
            ;;
        *)
            "$SCRIPTPATH/ugreen_leds_cli" ${map[$i]} -off
            ;;
    esac
done
