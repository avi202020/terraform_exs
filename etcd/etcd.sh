#!/bin/bash

set -euxo pipefail

sleep 30

AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | cut -b 10)

apt-get update
apt-get -y install wget python-pip

locale-gen en_GB.UTF-8
pip install --no-cache-dir awscli

VOLUME_ID=$(aws ec2 describe-volumes --filters "Name=status,Values=available"  Name=tag:Name,Values=ebs_etcd_$AVAILABILITY_ZONE --query "Volumes[].VolumeId" --output text --region eu-west-2)

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

aws ec2 attach-volume --region eu-west-2 \
              --volume-id "${VOLUME_ID}" \
              --instance-id "${INSTANCE_ID}" \
              --device "/dev/xvdf"

while [ -z $(aws ec2 describe-volumes --filters "Name=status,Values=in-use"  Name=tag:Name,Values=ebs_etcd_$AVAILABILITY_ZONE --query "Volumes[].VolumeId" --output text --region eu-west-2) ] ; do sleep 10; echo "ebs not ready"; done

sleep 5

if [[ -z $(blkid /dev/xvdf) ]]; then
  mkfs -t ext4 /dev/xvdf  
fi

mkdir -p /opt/etcd
mount /dev/xvdf /opt/etcd


ETCD_VERSION="v3.3.8"
# ETCD_VERSION="v3.3.10"
ETCD_URL="https://github.com/coreos/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz"
ETCD_CONFIG=/etc/etcd


apt-get update
apt-get -y install wget python-pip
pip install --no-cache-dir awscli

useradd etcd

wget ${ETCD_URL} -O /tmp/etcd-${ETCD_VERSION}-linux-amd64.tar.gz
tar -xzf /tmp/etcd-${ETCD_VERSION}-linux-amd64.tar.gz -C /tmp
install --owner root --group root --mode 0755     /tmp/etcd-${ETCD_VERSION}-linux-amd64/etcd /usr/bin/etcd
install --owner root --group root --mode 0755     /tmp/etcd-${ETCD_VERSION}-linux-amd64/etcdctl /usr/bin/etcdctl
install -d --owner root --group root --mode 0755 ${ETCD_CONFIG}

cat > /etc/systemd/system/etcd.service <<EOF
[Unit]
Description=etcd key-value store

[Service]
User=etcd
Type=notify
ExecStart=/usr/bin/etcd --config-file=/etc/etcd/etcd.conf
Restart=always
RestartSec=10s
LimitNOFILE=40000

[Install]
WantedBy=ready.target

EOF

chmod 0644 /etc/systemd/system/etcd.service


mkdir -p /opt/etcd/data
chown -R etcd:etcd /opt/etcd


cat > /etc/etcd/etcd.conf <<EOF

# This is the configuration file for the etcd server.

# Human-readable name for this member.
name: 'etcd-AZONE.k8s.ifritltd.co.uk'

# Path to the data directory.
data-dir: /opt/etcd/data

# Path to the dedicated wal directory.
wal-dir: /opt/etcd/wal

# Number of committed transactions to trigger a snapshot to disk.
snapshot-count: 10000

# Time (in milliseconds) of a heartbeat interval.
heartbeat-interval: 100

# Time (in milliseconds) for an election to timeout.
election-timeout: 1000

# Raise alarms when backend size exceeds the given quota. 0 means use the
# default quota.
quota-backend-bytes: 0

# List of comma separated URLs to listen on for peer traffic.
listen-peer-urls: https://0.0.0.0:2380

# List of comma separated URLs to listen on for client traffic.
listen-client-urls: https://0.0.0.0:2379

# Maximum number of snapshot files to retain (0 is unlimited).
max-snapshots: 5

# Maximum number of wal files to retain (0 is unlimited).
max-wals: 5

# Comma-separated white list of origins for CORS (cross-origin resource sharing).
cors:

# List of this member's peer URLs to advertise to the rest of the cluster.
# The URLs needed to be a comma-separated list.
initial-advertise-peer-urls: https://etcd-AZONE.k8s.ifritltd.co.uk:2380

# List of this member's client URLs to advertise to the public.
# The URLs needed to be a comma-separated list.
advertise-client-urls: https://etcd-AZONE.k8s.ifritltd.co.uk:2379

# Discovery URL used to bootstrap the cluster.
discovery:

# Valid values include 'exit', 'proxy'
discovery-fallback: 'proxy'

# HTTP proxy to use for traffic to discovery service.
discovery-proxy:

# DNS domain used to bootstrap initial cluster.
discovery-srv:

# Initial cluster configuration for bootstrapping.
initial-cluster: 'etcd-a.k8s.ifritltd.co.uk=https://etcd-a.k8s.ifritltd.co.uk:2380,etcd-b.k8s.ifritltd.co.uk=https://etcd-b.k8s.ifritltd.co.uk:2380,etcd-c.k8s.ifritltd.co.uk=https://etcd-c.k8s.ifritltd.co.uk:2380'
# initial-cluster: 'etcd-a.k8s.ifritltd.co.uk=https://etcd-a.k8s.ifritltd.co.uk:2380'

# Initial cluster token for the etcd cluster during bootstrap.
initial-cluster-token: 'etcd-cluster'

# Initial cluster state ('new' or 'existing').
initial-cluster-state: 'new'

# Reject reconfiguration requests that would cause quorum loss.
strict-reconfig-check: false

# Accept etcd V2 client requests
enable-v2: true

# Enable runtime profiling data via HTTP server
enable-pprof: true

# Valid values include 'on', 'readonly', 'off'
proxy: 'off'

# Time (in milliseconds) an endpoint will be held in a failed state.
proxy-failure-wait: 5000

# Time (in milliseconds) of the endpoints refresh interval.
proxy-refresh-interval: 30000

# Time (in milliseconds) for a dial to timeout.
proxy-dial-timeout: 1000

# Time (in milliseconds) for a write to timeout.
proxy-write-timeout: 5000

# Time (in milliseconds) for a read to timeout.
proxy-read-timeout: 0

client-transport-security:
  # Path to the client server TLS cert file.
  cert-file: /etc/ssl/server.pem

  # Path to the client server TLS key file.
  key-file: /etc/ssl/server-key.pem

  # Enable client cert authentication.
  client-cert-auth: false

  # Path to the client server TLS trusted CA cert file.
  trusted-ca-file: /etc/ssl/certs/ca.pem

  # Client TLS using generated certificates
  auto-tls: false

peer-transport-security:
  # Path to the peer server TLS cert file.
  cert-file: /etc/ssl/server.pem

  # Path to the peer server TLS key file.
  key-file: /etc/ssl/server-key.pem

  # Enable peer client cert authentication.
  peer-client-cert-auth: false

  # Path to the peer server TLS trusted CA cert file.
  trusted-ca-file: /etc/ssl/certs/ca.pem

  # Peer TLS using generated certificates.
  auto-tls: false

# Enable debug-level logging for etcd.
debug: false

logger: zap

# Specify 'stdout' or 'stderr' to skip journald logging even when running under systemd.
log-outputs: [stderr]

# Force to create a new one member cluster.
force-new-cluster: false

auto-compaction-mode: periodic
auto-compaction-retention: "1"


EOF


sed -i s~AZONE~$AVAILABILITY_ZONE~g /etc/etcd/etcd.conf


aws ssm get-parameters --names "etcd-ca" --query '[Parameters[0].Value]' --output text  --with-decryption --region eu-west-2 > /etc/ssl/certs/ca.pem 
aws ssm get-parameters --names "etcd-server" --query '[Parameters[0].Value]' --output text  --with-decryption --region eu-west-2 > /etc/ssl/server.pem
aws ssm get-parameters --names "etcd-server-key" --query '[Parameters[0].Value]' --output text  --with-decryption --region eu-west-2 > /etc/ssl/server-key.pem

chmod 0600  /etc/ssl/server-key.pem
chmod 0644 /etc/ssl/server.pem
chown etcd:etcd /etc/ssl/server-key.pem
chown etcd:etcd /etc/ssl/server.pem

systemctl enable etcd
systemctl start etcd


