# apps-deployment



## Set privileged ports

As hosting something that require privileged ports, you have to allow it:
- add `net.ipv4.ip_unprivileged_port_start=80` to `/etc/sysctl.conf`
- enforce new settings with `sysctl -p /etc/sysctl.conf`

## Define network quadlet

[Unit]
Description=Stacknet network
# This is systemd syntax to wait for the network to be online before starting this service:
After=network-online.target
 
[Network]
NetworkName=stacknet
# These are optional, podman will just create it randomly otherwise.
Subnet=10.10.0.0/24
Gateway=10.10.0.1
DNS=9.9.9.9
 
[Install]
WantedBy=default.target

## Set correct UID for SELinux

:U tells podman to chown the source volume to match the default UID+GID within the container.
SELinux; :z sets the shared content label while :Z is a private, unshared label that only this container can read.

## Copy symlinks to where needed

```
cd /opt/
cp -s /home/egissi/Documenti/Git/apps-deployment .
cd /etc/containers/systemd/
cp -s /home/egissi/Documenti/Git/apps-deployment/systemd/*.container .
```

## Reload all containers

## Set /etc/hosts

Add line to `/etc/hosts`: 
```
127.0.0.1   apps.local grist.local dex.local n8n.local minio.local
```

## Download all images

podman pull docker.io/caddy:2.8
podman pull docker.io/n8nio/n8n:2.6.4
podman pull docker.io/redis:7-bookworm
podman pull docker.io/minio/minio:RELEASE.2025-09-07T16-13-09Z-cpuv1
podman pull ghcr.io/ict-vvf-genova/dex-smtp:master
podman pull docker.io/gristlabs/grist:1.7.10

## Root should read all

sudo chown -R root:root /opt/apps-deployment
sudo chmod 700 /opt/apps-deployment/
sudo restorecon -Rv /etc/apps-secrets.env


sudo mkdir -p /opt/apps-deployment/persist/dex
sudo systemctl daemon-reload
sudo systemctl restart dex
sudo journalctl -u dex -n 80 --no-pager

