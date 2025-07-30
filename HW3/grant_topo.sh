#!/bin/bash

docker run -d --name alice ubuntu:latest sleep infinity
docker run -d --name bob ubuntu:latest sleep infinity
docker run -d --name eve ubuntu:latest sleep infinity

mkdir -p /var/run/netns

ln -s /proc/`docker inspect -f  '{{ .State.Pid }}' alice`/ns/net \
/var/run/netns/alice
ln -s /proc/`docker inspect -f  '{{ .State.Pid }}' bob`/ns/net \
/var/run/netns/bob
ln -s /proc/`docker inspect -f  '{{ .State.Pid }}' eve`/ns/net \
/var/run/netns/eve

ip link add br0 type bridge
ip link set br0 up 

ip link add br0-alice master br0 type veth peer name alice-br0 netns alice
ip link add br0-bob master br0 type veth peer name bob-br0 netns bob
ip link add br0-eve master br0 type veth peer name eve-br0 netns eve

ip link set br0-alice up 
ip link set br0-bob up
ip link set br0-eve up 
ip netns exec alice ip link set alice-br0 up
ip netns exec bob ip link set bob-br0 up
ip netns exec eve ip link set eve-br0 up

ip netns exec alice ip addr add 192.168.1.254/24 dev alice-br0
ip netns exec eve ip addr add 192.168.1.250/24 dev eve-br0

docker exec alice /bin/sh -c 'apt update -y && apt install -y iproute2'

docker exec alice /bin/sh -c 'apt update -y && apt install -y isc-dhcp-server'

docker exec alice /bin/sh -c 'touch /var/lib/dhcp/dhcpd.leases && cat <<EOF > /etc/dhcp/dhcpd.conf

subnet 192.168.1.0 netmask 255.255.255.0 {
  range 192.168.1.100 192.168.1.149;
  option subnet-mask 255.255.255.0;
  option routers 192.168.1.254;
  ping-check true;
  default-lease-time 259200;
  max-lease-time 604800;
}

EOF'

docker exec alice /usr/sbin/dhcpd -f
ip netns exec bob /usr/sbin/dhclient -w -v -I bob-br0
