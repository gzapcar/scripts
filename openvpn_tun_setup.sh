#!/bin/sh
# ==========================================
# Script automático de configuración OpenVPN (modo TUN) para OpenWrt
# Autor original: (tu nombre o alias)
# Adaptado y optimizado por ChatGPT (GPT-5)
# ==========================================

# ---------- Función para verificar errores ----------
check_status() {
    if [ $? -ne 0 ]; then
        echo -e "\033[31m- Ha ocurrido un error. Abortando.\033[0m"
        exit 1
    fi
}

# ---------- Parte 1: Instalación ----------
echo -e "\033[34m=== Instalando paquetes necesarios ===\033[0m"
opkg update
check_status
opkg install openvpn-easy-rsa openvpn-openssl luci-app-openvpn nano
check_status

echo -e "\033[32m- Instalación completada con éxito.\033[0m"

# ---------- Parte 2: Generación de certificados ----------
cd /etc/easy-rsa || exit 1
check_status

# Configurar expiraciones largas
sed -i 's/#set_var EASYRSA_CA_EXPIRE.*/set_var EASYRSA_CA_EXPIRE      99999/' vars
sed -i 's/#set_var EASYRSA_CERT_EXPIRE.*/set_var EASYRSA_CERT_EXPIRE    99999/' vars
check_status

# Inicializar PKI
echo -e "yes\nyes" | easyrsa init-pki
check_status

# Crear CA, servidor y cliente
echo -e "yes\nserver" | easyrsa build-ca nopass
check_status
echo -e "yes" | easyrsa build-server-full server nopass
check_status
echo -e "yes" | easyrsa build-client-full client nopass
check_status

# Generar Diffie-Hellman
easyrsa gen-dh
check_status

# ---------- Parte 3: Copiar certificados ----------
mkdir -p /etc/openvpn
cp /etc/easy-rsa/pki/ca.crt /etc/openvpn/
cp /etc/easy-rsa/pki/private/server.key /etc/openvpn/
cp /etc/easy-rsa/pki/issued/server.crt /etc/openvpn/
cp /etc/easy-rsa/pki/dh.pem /etc/openvpn/
check_status

echo -e "\033[32m- Certificados copiados a /etc/openvpn/ correctamente.\033[0m"

# ---------- Parte 4: Configuración de OpenVPN (modo TUN) ----------
cat > /etc/config/openvpn <<'EOF'
config openvpn 'VPN_Tun_Server'
    option enabled '1'
    option mode 'server'
    option dev 'tun0'
    option proto 'udp'
    option port '1194'
    option topology 'subnet'
    option server '10.8.0.0 255.255.255.0'
    option keepalive '10 120'
    option persist_key '1'
    option persist_tun '1'
    option user 'nobody'
    option group 'nogroup'
    option cipher 'AES-256-GCM'
    option ncp_ciphers 'AES-256-GCM:AES-128-GCM'
    option verb '3'
    option client_to_client '1'
    option tls_server '1'
    option remote_cert_tls 'client'
    list push 'redirect-gateway def1'
    list push 'dhcp-option DNS 8.8.8.8'
    option ca '/etc/openvpn/ca.crt'
    option cert '/etc/openvpn/server.crt'
    option key '/etc/openvpn/server.key'
    option dh '/etc/openvpn/dh.pem'
EOF
check_status

echo -e "\033[32m- Archivo /etc/config/openvpn (modo TUN) creado.\033[0m"

# ---------- Parte 5: Configuración de red y firewall ----------
# Crear interfaz VPN (tun0)
uci -q delete network.vpn
uci set network.vpn="interface"
uci set network.vpn.proto="none"
uci set network.vpn.ifname="tun0"
uci commit network
check_status

# Crear zona de firewall
uci -q delete firewall.vpn
uci set firewall.vpn="zone"
uci set firewall.vpn.name="vpn"
uci set firewall.vpn.input="ACCEPT"
uci set firewall.vpn.output="ACCEPT"
uci set firewall.vpn.forward="ACCEPT"
uci add_list firewall.vpn.network="vpn"

# Reenvío LAN <-> VPN
uci -q delete firewall.vpn_forward_lan
uci set firewall.vpn_forward_lan="forwarding"
uci set firewall.vpn_forward_lan.src="lan"
uci set firewall.vpn_forward_lan.dest="vpn"

uci -q delete firewall.vpn_forward_back
uci set firewall.vpn_forward_back="forwarding"
uci set firewall.vpn_forward_back.src="vpn"
uci set firewall.vpn_forward_back.dest="lan"
uci commit firewall
check_status

echo -e "\033[32m- Configuración de red y firewall completada.\033[0m"

# ---------- Parte 6: Obtener DDNS si existe ----------
DDNS=""
DDNS_CONFIGURED=false
if [ -f /etc/config/ddns ]; then
    DDNS=$(awk -F"'" '/option lookup_host/ {print $2}' /etc/config/ddns | head -n 1)
    [ -n "$DDNS" ] && DDNS_CONFIGURED=true
fi

# ---------- Parte 7: Generar client.ovpn ----------
cat > /etc/openvpn/client.ovpn <<EOF
client
dev tun
proto udp
remote ${DDNS:-"TU_DDNS_O_IP_PUBLICA"} 1194
resolv-retry infinite
nobind
persist-key
persist-tun
user nobody
group nogroup
remote-cert-tls server
cipher AES-256-GCM
verb 3
keepalive 10 120
<ca>
$(cat /etc/openvpn/ca.crt)
</ca>
<cert>
$(sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' /etc/easy-rsa/pki/issued/client.crt)
</cert>
<key>
$(cat /etc/easy-rsa/pki/private/client.key)
</key>
EOF
check_status

echo -e "\033[32m- Archivo client.ovpn generado en /etc/openvpn/\033[0m"

# ---------- Parte 8: Configurar reinicio de DDNS si aplica ----------
if $DDNS_CONFIGURED; then
    if ! grep -q "/etc/init.d/ddns restart" /etc/rc.local; then
        sed -i '/exit 0/i /etc/init.d/ddns restart' /etc/rc.local
        echo -e "\033[32m- Reinicio de DDNS añadido a /etc/rc.local.\033[0m"
    fi
else
    echo -e "\033[33m- DDNS no detectado, recuerda ajustar la IP en client.ovpn.\033[0m"
fi

# ---------- Parte 9: Reiniciar servicios ----------
echo -e "\033[34m=== Reiniciando servicios ===\033[0m"
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/openvpn restart
check_status

echo -e "\033[32m=== OpenVPN modo TUN configurado correctamente ===\033[0m"
echo -e "\033[32m- Archivo cliente: /etc/openvpn/client.ovpn\033[0m"
echo -e "\033[32m- Red VPN: 10.8.0.0/24 (interfaz tun0)\033[0m"
echo -e "\033[32m- Puerto: UDP 1194\033[0m"

# ---------- Reinicio final ----------
echo "- El dispositivo se reiniciará en 5 segundos..."
sleep 5
reboot
