# Install packages
wireguard-tools
 
# Configuration parameters
VPN_IF="vpn"
VPN_SERV="SERVER_ADDRESS"
VPN_PORT="51820"
VPN_ADDR="192.168.9.2/24"
VPN_ADDR6="fd00:9::2/64"
# Generate keys
umask go=
wg genkey | tee wgserver.key | wg pubkey > wgserver.pub
wg genkey | tee wgclient.key | wg pubkey > wgclient.pub
wg genpsk > wgclient.psk
 
# Client private key
VPN_KEY="$(cat wgclient.key)"
 
# Pre-shared key
VPN_PSK="$(cat wgclient.psk)"
 
# Server public key
VPN_PUB="$(cat wgserver.pub)"
# Configure firewall
uci rename firewall.@zone[0]="lan"
uci rename firewall.@zone[1]="wan"
uci del_list firewall.wan.network="${VPN_IF}"
uci add_list firewall.wan.network="${VPN_IF}"
uci commit firewall
service firewall restart


# Configure network
uci -q delete network.${VPN_IF}
uci set network.${VPN_IF}="interface"
uci set network.${VPN_IF}.proto="wireguard"
uci set network.${VPN_IF}.private_key="${VPN_KEY}"
uci add_list network.${VPN_IF}.addresses="${VPN_ADDR}"
uci add_list network.${VPN_IF}.addresses="${VPN_ADDR6}"
 
# Add VPN peers
uci -q delete network.wgserver
uci set network.wgserver="wireguard_${VPN_IF}"
uci set network.wgserver.public_key="${VPN_PUB}"
uci set network.wgserver.preshared_key="${VPN_PSK}"
uci set network.wgserver.endpoint_host="${VPN_SERV}"
uci set network.wgserver.endpoint_port="${VPN_PORT}"
uci set network.wgserver.persistent_keepalive="25"
uci set network.wgserver.route_allowed_ips="1"
uci add_list network.wgserver.allowed_ips="0.0.0.0/0"
uci add_list network.wgserver.allowed_ips="::/0"
uci commit network
service network restart

