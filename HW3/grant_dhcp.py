from scapy.all import *

# Monitor the bridge
iface = "br0"


server_ip = "192.168.0.254" # DHCP Server IP (alice)
subnet_mask = "255.255.255.0"
lease_time = 86400  # 1 day
assigned_ip = "192.168.0.10"  # Fixed IP assigned to bob

# Track current DHCP transaction IDs to respond consistently
pending_offers = {}

def handle_dhcp(pkt):
    if DHCP in pkt and BOOTP in pkt:
        msg_type = None
        for opt in pkt[DHCP].options:
            if isinstance(opt, tuple) and opt[0] == "message-type":
                msg_type = opt[1]
                break

        client_mac = pkt[Ether].src
        xid = pkt[BOOTP].xid
        chaddr = pkt[BOOTP].chaddr

        if msg_type == 1:  # DHCP Discover
            print(f"[DISCOVER] From {client_mac}")
            ether = Ether(src=get_if_hwaddr(iface), dst=client_mac)
            ip = IP(src=server_ip, dst="255.255.255.255")
            udp = UDP(sport=67, dport=68)
            bootp = BOOTP(op=2, yiaddr=assigned_ip, siaddr=server_ip, xid=xid, chaddr=chaddr, flags=0)
            dhcp = DHCP(options=[
                ("message-type", "offer"),
                ("server_id", server_ip),
                ("subnet_mask", subnet_mask),
                ("lease_time", lease_time),
                ("router", server_ip),
                "end"
            ])
            offer = ether / ip / udp / bootp / dhcp
            sendp(offer, iface=iface, verbose=0)
            pending_offers[xid] = assigned_ip
            print(f" → Sent OFFER with IP {assigned_ip}")

        elif msg_type == 3:  # DHCP Request
            print(f"[REQUEST] From {client_mac}")
            requested_ip = assigned_ip
            ether = Ether(src=get_if_hwaddr(iface), dst=client_mac)
            ip = IP(src=server_ip, dst="255.255.255.255")
            udp = UDP(sport=67, dport=68)
            bootp = BOOTP(op=2, yiaddr=requested_ip, siaddr=server_ip, xid=xid, chaddr=chaddr, flags=0)
            dhcp = DHCP(options=[
                ("message-type", "ack"),
                ("server_id", server_ip),
                ("subnet_mask", subnet_mask),
                ("lease_time", lease_time),
                ("router", server_ip),
                "end"
            ])
            ack = ether / ip / udp / bootp / dhcp
            sendp(ack, iface=iface, verbose=0)
            print(f" → Sent ACK with IP {requested_ip}")

print(f"[*] Listening for DHCP packets on {iface} ...")
print("-----------------------------------------------------------")
sniff(filter="udp and (port 67 or 68)", prn=handle_dhcp, iface=iface, store=0)
