# apps-deployment

This guide explains how to install **Caddy, Dex, Grist, MinIO, n8n, Redis** as **rootless Podman Quadlets**
on a freshly installed server.

It assumes:

* You have **sudo** access.
* The server is on a **LAN**: no public internet exposure required, but it does need to pull images at install time.
* You will run everything as a **dedicated non-root user** named `admin`.

This repository contains all the tools that you need.

---

## Install your server

Use Fedora IoT, and create the `admin` user.

Copy your ssh public key for passwordless login:
FIXME
```bash

```

Set the proxy for the bash console:

```bash
sudo -i
mkdir -p /etc/profile.d
cat > /etc/profile.d/proxy.sh << EOF
# Systemwide proxy
export http_proxy="http://username:password@proxy.example.com:3128"
export https_proxy="http://username:password@proxy.example.com:3128"
export HTTP_PROXY="http://username:password@proxy.example.com:3128"
export HTTPS_PROXY="http://username:password@proxy.example.com:3128"
EOF
```

Set the proxy for rpm-ostree upgrades:

```bash
sudo -i
mkdir -p /etc/systemd/system/rpm-ostreed.service.d
cat > /etc/systemd/system/rpm-ostreed.service.d/http-proxy.conf << EOF
[Service]
Environment="http_proxy=http://username:password@proxy.example.com:3128"
Environment="https_proxy=http://username:password@proxy.example.com:3128"
Environment="HTTP_PROXY=http://username:password@proxy.example.com:3128"
Environment="HTTPS_PROXY=http://username:password@proxy.example.com:3128"
EOF
systemctl daemon-reload
systemctl restart rpm-ostreed.service
rpm-ostree upgrade
```

Install cockpit and some other tools:

```bash
sudo -i
rpm-ostree install cockpit-system cockpit-ws cockpit-files cockpit-networkmanager cockpit-ostree cockpit-podman cockpit-selinux cockpit-storaged nano git bind-utils nss-tools
systemctl reboot
systemctl enable --now cockpit.socket
firewall-cmd --add-service=cockpit
firewall-cmd --add-service=cockpit --permanent
```

Clone the apps deployment repository locally:
```bash
git clone https://github.com/emanuelegissi/apps-deployment.git
```

## Choose a domain and ensure name resolution

Pick a local domain you control on your LAN, for example:
 `local` (so you will use `apps.local`, `grist.local`, etc.)
 or `example.com` (so you will use `apps.example.com`, `grist.example.com`, etc.) 

You must ensure that the following names resolve to your server’s IP (eg. 192.168.2.200):
`apps.<domain>`, `grist.<domain>`, `dex.<domain>`, `n8n.<domain>`, and `minio.<domain>`.

### Option A — Preferred: configure LAN DNS

Create A/AAAA records pointing to the server IP for:
`apps.<domain>`, `grist.<domain>`, `dex.<domain>`, `n8n.<domain>`, and `minio.<domain>`.

### Option B — Quick test: edit `/etc/hosts`

If you don’t have DNS yet, or for development purposes, add an entry on the server:

```bash
sudo nano /etc/hosts
```

Add the line:

```text
192.168.2.200   apps.local grist.local dex.local n8n.local minio.local
```

## Apply required sysctl settings

Edit `/etc/sysctl.conf`:

```bash
sudo nano /etc/sysctl.conf
```

Add (or ensure) these lines exist:

```text
# Allow rootless Caddy expose privileged port 80
net.ipv4.ip_unprivileged_port_start=80

# Memory overcommit must be enabled for MinIO
vm.overcommit_memory = 1
```

Apply them immediately:

```bash
sudo sysctl -p /etc/sysctl.conf
```

## Open the firewall ports

```bash
sudo firewall-cmd --permanent --zone=public --add-service=http
sudo firewall-cmd --permanent --zone=public --add-service=https
sudo firewall-cmd --reload
```

## Enable `linger` for the `admin` user

This allows the user’s systemd services to run at boot without needing an interactive login:

```bash
sudo loginctl enable-linger admin
```

## Clone the `apps-deployment` repository

Log as the `admin` user, and run:

```bash
cd ~
git clone https://github.com/emanuelegissi/apps-deployment.git
cd ~/apps-deployment
```

## Pull all required container images

Log as the `admin` user, and run:

```bash
podman pull docker.io/caddy:2.8
podman pull docker.io/n8nio/n8n:2.6.4
podman pull docker.io/redis:7-bookworm
podman pull docker.io/minio/minio:RELEASE.2025-09-07T16-13-09Z-cpuv1
podman pull ghcr.io/ict-vvf-genova/dex-smtp:master
podman pull docker.io/gristlabs/grist:1.7.10
```

## Install quadlets, config links, tools links, persist directories

From inside the repo (`~/apps-deployment`), run:

```bash
./install.sh
```

The local deployment directories are:

~/apps-config/
~/apps-secrets/
~/apps-persist/
~/.config/containers/systemd/
~/.local/bin/

## Configure secrets

Edit the secrets file:

```bash
nano ~/.config/apps-deployment/secrets/apps-secrets.env
```

Set at least:

```bash
DOMAIN=local
```

Use your chosen domain: `local`, `example.com`, etc.

Adjust any other variables your quadlets require (OIDC, passwords, tokens, etc.).

Keep this file **private**, the installer sets permissions to `0600`.

## Reboot

Reboot the server to validate boot-time behavior (linger + user services):

```bash
sudo sysctl reboot
```

After reboot, you do **not** need to log in to start services if linger is enabled, but for the first verification it’s easiest to log in as the `admin` user.

## Init minio bucket

FIXME

## Use the tools to manage quadlets

Reload systemd user units and quadlets are generated into systemd services:

```bash
apps-reload
```

Check status:

```bash
apps-status
```

Follow logs:

```bash
apps-follow caddy.service
apps-follow grist.service
```

If you prefer viewing logs by unit (non-follow):

```bash
apps-journal caddy.service
```

## Verify access

From a client machine (or from the server), open:

* `https://apps.local`
* `https://grist.local`
* `https://dex.local`
* `https://n8n.local`
* `https://minio.local`

> If you use Caddy internal/self-signed TLS, you may need to trust its root CA on your client devices (depending on how your deployment is configured).

## Troubleshooting quick tips

* List Quadlet-generated units (detected by tools):

```bash
apps-reload
```

* Check failed units:

```bash
apps-health
```

* Show user services:

```bash
systemctl --user list-units --type=service --all
```

* If you changed Quadlets in the repo, reload + restart:

```bash
apps-reload
apps-restart
```

* Test your webservers with:

```bash
curl -k -svo /dev/null https://apps.local
```