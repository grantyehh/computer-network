#!/bin/bash

docker run --rm -d --name alice --cap-add=NET_ADMIN --device /dev/net/tun ubuntu:latest sleep infinity
docker run --rm -d --name bob --cap-add=NET_ADMIN --device /dev/net/tun ubuntu:latest sleep infinity
docker run --rm -d --name wireguard --cap-add=NET_ADMIN --device /dev/net/tun ubuntu:latest sleep infinity

mkdir -p /var/run/netns

for ns in alice bob wireguard; do
  ln -sf /proc/$(docker inspect -f '{{.State.Pid}}' $ns)/ns/net /var/run/netns/$ns
done

ip link add wg-alice type veth peer name alice-wg netns alice
ip link add wg-bob type veth peer name bob-wg netns bob
ip link set netns wireguard dev wg-alice
ip link set netns wireguard dev wg-bob

ip netns exec alice ip link set alice-wg up
ip netns exec bob ip link set bob-wg up
ip netns exec wireguard ip link set wg-alice up
ip netns exec wireguard ip link set wg-bob up


ip netns exec alice ip addr add 192.168.1.1/24 dev alice-wg
ip netns exec bob ip addr add 192.168.2.1/24 dev bob-wg
ip netns exec wireguard ip addr add 192.168.1.2/24 dev wg-alice
ip netns exec wireguard ip addr add 192.168.2.2/24 dev wg-bob

# 在三個 container 安裝 wireguard
for c in alice bob wireguard; do
  docker exec $c bash -c "apt update && apt install -y wireguard iproute2 iputils-ping"
done


# wireguard server
WG_PRIV="9V9kYRI0jzWbdStPhQfPlIGzShPt6/NzPyz08vA4LlY="

# bob client
BOB_PRIV="AZK1gLSoxAyatnh8Pl5eRCVVcikpBODcbzYxYTLpSkM="


WG_PUB=$(echo "$WG_PRIV" | wg pubkey)
BOB_PUB=$(echo "$BOB_PRIV" | wg pubkey)

# 在 wireguard 中寫入固定私鑰
echo "$WG_PRIV" | docker exec -i wireguard tee /etc/wireguard/privatekey > /dev/null
echo "$WG_PUB"  | docker exec -i wireguard tee /etc/wireguard/publickey > /dev/null

# 在 bob 中寫入固定私鑰
echo "$BOB_PRIV" | docker exec -i bob tee /etc/wireguard/privatekey > /dev/null
echo "$BOB_PUB"  | docker exec -i bob tee /etc/wireguard/publickey > /dev/null


# Setup wg0 on wireguard
docker exec wireguard bash -c "
ip link add dev wg0 type wireguard
ip addr add 192.168.3.254/24 dev wg0
wg set wg0 private-key /etc/wireguard/privatekey
wg set wg0 peer $BOB_PUB allowed-ips 192.168.3.1/32
wg set wg0 listen-port 51820
ip link set wg0 up
"

# Setup wg0 on bob
docker exec bob bash -c "
ip link add dev wg0 type wireguard
ip addr add 192.168.3.1/24 dev wg0
wg set wg0 private-key /etc/wireguard/privatekey
wg set wg0 peer $WG_PUB allowed-ips 192.168.1.0/24 endpoint 192.168.2.2:51820 persistent-keepalive 25
ip link set wg0 up
"

# Setup route from alice to bob via VPN 
ip netns exec alice ip route add 192.168.3.0/24 via 192.168.1.2

# (Optional) Test
ip netns exec bob ping -I bob-wg -c 3 192.168.1.1
ip netns exec bob ping -I wg0 -c 3 192.168.1.1

docker exec -it wireguard tcpdump -i wg0 icmp