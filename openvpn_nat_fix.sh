#!/bin/sh
# ==========================================
# Script complementario para OpenVPN modo TUN en OpenWrt
# Permite navegación de clientes VPN a través del servidor
# ==========================================

echo -e "\033[34m=== Configurando NAT y reenvío para OpenVPN ===\033[0m"

# Habilitar reenvío IPv4
uci set network.globals.forwarding='1'
uci commit network

# Asegurarse de que la zona WAN tenga masquerading activado
uci set firewall.@zone[1].masq='1'
uci set firewall.@zone[1].mtu_fix='1'

# Si la interfaz VPN no está marcada como forwarding hacia WAN, agregarla
uci -q delete firewall.vpn_to_wan
uci set firewall.vpn_to_wan="forwarding"
uci set firewall.vpn_to_wan.src="vpn"
uci set firewall.vpn_to_wan.dest="wan"

# Asegurarse de que la zona vpn exista (por compatibilidad)
uci show firewall | grep -q "zone.vpn" || {
    uci set firewall.vpn="zone"
    uci set firewall.vpn.name="vpn"
    uci set firewall.vpn.input="ACCEPT"
    uci set firewall.vpn.output="ACCEPT"
    uci set firewall.vpn.forward="ACCEPT"
    uci add_list firewall.vpn.network="vpn"
}

uci commit firewall

# Reiniciar servicios
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/openvpn restart

echo -e "\033[32m=== NAT y reenvío configurados con éxito ===\033[0m"
echo -e "\033[32mLos clientes VPN ahora podrán navegar por Internet.\033[0m"
