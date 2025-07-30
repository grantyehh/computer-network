from scapy.all import *

# The interface connected to bob
iface = "br0"


server_ip = "192.168.0.254"  # DHCP Server IP(alice)
client_ip = "192.168.0.10" # Assign fixed IP to bob
subnet_mask = "255.255.255.0"
lease_time = 86400  # 1 day

def handle_dhcp(pkt):
    if DHCP in pkt and pkt[DHCP].options[0][1] == 3:  # No.3 is DHCP REQUEST
        client_mac = pkt[Ether].src
        transaction_id = pkt[BOOTP].xid

        print(f"DHCP REQUEST detected from {client_mac}, replying with ACK")
        print("-----------------------------------------------------------")
        ether = Ether(src=get_if_hwaddr(iface), dst=client_mac)
        ip = IP(src=server_ip, dst="255.255.255.255")
        udp = UDP(sport=67, dport=68)
        bootp = BOOTP(op=2, yiaddr=client_ip, siaddr=server_ip, chaddr=pkt[BOOTP].chaddr, xid=transaction_id, flags=0)
        dhcp = DHCP(options=[
            ("message-type", "ack"),
            ("server_id", server_ip),
            ("subnet_mask", subnet_mask),
            ("lease_time", lease_time),
            "end"
        ])

        dhcp_ack = ether / ip / udp / bootp / dhcp
        sendp(dhcp_ack, iface=iface, verbose=0)
        print(f"Sent DHCP ACK with {client_ip}")
        print("-----------------------------------------------------------")

print(f"Listening for DHCP REQUEST on interface: {iface}")
print("-----------------------------------------------------------")
sniff(filter="udp and (port 67 or 68)", prn=handle_dhcp, iface=iface, store=0)
