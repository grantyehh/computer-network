#!/bin/bash

docker run --rm -d --name hostA ubuntu:latest sleep infinity
docker run --rm -d --name hostB ubuntu:latest sleep infinity
docker run --rm -d --name gate ubuntu:latest sleep infinity
docker run --rm -d --name inter ubuntu:latest sleep infinity

mkdir -p /var/run/netns

ln -s /proc/`docker inspect -f '{{ .State.Pid }}' hostA`/ns/net \
/var/run/netns/hostA
ln -s /proc/`docker inspect -f '{{ .State.Pid }}' hostB`/ns/net \
/var/run/netns/hostB
ln -s /proc/`docker inspect -f '{{ .State.Pid }}' gate`/ns/net \
/var/run/netns/gate
ln -s /proc/`docker inspect -f '{{ .State.Pid }}' inter`/ns/net \
/var/run/netns/inter

ip link add br0 type bridge
ip link set br0 up

ip link add br-a master br0 type veth peer name a-br netns hostA
ip link add br-b master br0 type veth peer name b-br netns hostB
ip link add br-g master br0 type veth peer name g-br netns gate
ip link add g-i  type veth peer name i-g netns inter
ip link set netns gate dev g-i

ip link set br-a up
ip link set br-b up
ip link set br-g up
ip netns exec hostA ip link set a-br up
ip netns exec hostB ip link set b-br up
ip netns exec gate ip link set g-br up
ip netns exec gate ip link set g-i up 
ip netns exec inter ip link set i-g up


ip netns exec hostA ip addr add 192.168.0.100/24 dev a-br
ip netns exec hostB ip addr add 192.168.0.101/24 dev b-br
ip netns exec gate ip addr add 192.168.0.200/24 dev g-br
ip netns exec gate ip addr add 192.168.1.1/24 dev g-i
ip netns exec inter ip addr add 192.168.1.100/24 dev i-g 

# 打開 gate ip forwarding
ip netns exec gate sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"

# 設定 route
ip netns exec hostA ip route add 192.168.1.0/24 via 192.168.0.200
ip netns exec inter ip route add 192.168.0.0/24 via 192.168.1.1

# 在 Gate 上面安裝 iptables
docker exec gate bash -c "apt update && apt install -y iptables"
# 設定FORWARD  
ip netns exec gate iptables -A FORWARD -j DROP
ip netns exec gate iptables -A FORWARD -j ACCEPT
# 設定 INPUT
ip netns exec gate iptables -A INPUT -j DROP
ip netns exec gate iptables -A INPUT -j ACCEPT
# 設定 OUTPUT
ip netns exec gate iptables -A OUTPUT -j DROP
ip netns exec gate iptables -A OUTPUT -j DROP
