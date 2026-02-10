# apps-deployment

# Chatgpt prompt, to be improved

Please, write a markdown page explaining how to install apps-deployment from scratch on a just installed Debian 13 server.
Do not forget to:
- Create the user that is going to run the rootless podman quadlets
- git clone the apps-deployment repository in the user home
- Install all the requirements: podman, rsync, git, ...
- Download all images with:
podman pull docker.io/caddy:2.8
podman pull docker.io/n8nio/n8n:2.6.4
podman pull docker.io/redis:7-bookworm
podman pull docker.io/minio/minio:RELEASE.2025-09-07T16-13-09Z-cpuv1
podman pull ghcr.io/ict-vvf-genova/dex-smtp:master
podman pull docker.io/gristlabs/grist:1.7.10
- set with sudo nano /etc/sysctl.conf:
 - Allow rootless Caddy expose privileged port 80: net.ipv4.ip_unprivileged_port_start=80
 - Memory overcommit must be enabled for Minio: vm.overcommit_memory = 1
- Enforce new settings with `sysctl -p /etc/sysctl.conf`
- Get the domain name (eg. local) and set the lan dns for apps.local grist.local dex.local n8n.local minio.local
- or get the serve ip and add line to `/etc/hosts`: `192.168.2.200   apps.local grist.local dex.local n8n.local minio.local`
- run the install.sh script
- update the secrets, especially set the correct DOMAIN
- reboot and start the services

# apps-deployment — Debian 13 (rootless Podman Quadlets) install from scratch

This guide installs **Caddy, Dex, Grist, MinIO, n8n, Redis** as **rootless Podman Quadlets** on a freshly installed **Debian 13** server.

It assumes:

* You have **sudo** access.
* The server is on a **LAN** (no public internet exposure required, but it does need to pull images at install time).
* You will run everything as a **dedicated non-root user** (recommended).

---

## 0) Choose a domain and ensure name resolution

Pick a local domain you control on your LAN, for example:

* `local` (so you will use `apps.local`, `grist.local`, etc.)

You must ensure these names resolve to your server’s IP:

* `apps.<domain>`
* `grist.<domain>`
* `dex.<domain>`
* `n8n.<domain>`
* `minio.<domain>`

### Option A — Preferred: configure LAN DNS

Create A/AAAA records pointing to the server IP for:

* `apps.local`
* `grist.local`
* `dex.local`
* `n8n.local`
* `minio.local`

### Option B — Quick test: edit `/etc/hosts`

If you don’t have DNS yet, add an entry on **clients** (and optionally on the server too):

```bash
sudo nano /etc/hosts
```

Add (example IP `192.168.2.200`):

```text
192.168.2.200   apps.local grist.local dex.local n8n.local minio.local
```

---

## 1) Create the dedicated user for rootless Podman

Create a user (example: `apps`) that will own the repository and run the services:

```bash
sudo adduser apps
sudo usermod -aG sudo apps
```

Log in as that user (recommended: start a fresh shell):

```bash
su - apps
```

---

## 2) Install requirements (system packages)

On Debian 13, install the required tools:

```bash
sudo apt update
sudo apt install -y \
  podman uidmap slirp4netns fuse-overlayfs containernetworking-plugins \
  systemd systemd-userdbd \
  rsync git curl jq
```

---

## 3) Apply required sysctl settings

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

---

## 4) Enable “linger” for the service user

This allows the user’s systemd services to run at boot without needing an interactive login:

```bash
sudo loginctl enable-linger apps
```

(Replace `apps` if you chose a different username.)

---

## 5) Clone the `apps-deployment` repository into the user home

As the service user (`apps`):

```bash
cd ~
git clone <YOUR_GIT_URL_HERE> apps-deployment
cd ~/apps-deployment
```

> Replace `<YOUR_GIT_URL_HERE>` with your repo URL.

---

## 6) Pull all required container images

As the service user (`apps`), run:

```bash
podman pull docker.io/caddy:2.8
podman pull docker.io/n8nio/n8n:2.6.4
podman pull docker.io/redis:7-bookworm
podman pull docker.io/minio/minio:RELEASE.2025-09-07T16-13-09Z-cpuv1
podman pull ghcr.io/ict-vvf-genova/dex-smtp:master
podman pull docker.io/gristlabs/grist:1.7.10
```

---

## 7) Install Quadlets, config links, tools links, persist directories

From inside the repo (`~/apps-deployment`), run:

```bash
./install.sh
```

What this does (high level):

* Creates the app directories under:

  * `~/.config/apps-deployment/` (config + secrets)
  * `~/.local/share/apps-deployment/` (persist + backups, etc.)
* Symlinks:

  * quadlets → `~/.config/containers/systemd/`
  * config → `~/.config/apps-deployment/config` (points to repo `config/`)
  * tools → `~/.local/bin/` (points to repo `tools/`)
* Creates `~/.config/apps-deployment/secrets/apps-secrets.env` if missing and sets it to `0600`

---

## 8) Configure secrets (especially `DOMAIN`)

Edit the secrets file:

```bash
nano ~/.config/apps-deployment/secrets/apps-secrets.env
```

Set at least:

```bash
DOMAIN=local
```

(Use your chosen domain: `local`, `fritz.box`, etc.)

Add any other variables your Quadlets/containers require (OIDC, passwords, tokens, etc.).

**Important:** keep this file private (the installer sets permissions to `0600`).

---

## 9) Reboot

Reboot the server to validate boot-time behavior (linger + user services):

```bash
sudo reboot
```

After reboot, you do **not** need to log in to start services if linger is enabled, but for the first verification it’s easiest to log in as `apps`.

---

## 10) Start and enable the services

Log in as the service user again:

```bash
su - apps
```

Reload systemd user units (Quadlets are generated into services):

```bash
apps-reload
```

Enable and start everything:

```bash
apps-enable
```

Check status:

```bash
apps-status
```

Follow logs (example):

```bash
apps-follow caddy.service
apps-follow grist.service
```

If you prefer viewing logs by unit (non-follow):

```bash
apps-journal caddy.service
```

---

## 11) Verify access

From a client machine (or from the server), open:

* `https://apps.local`
* `https://grist.local`
* `https://dex.local`
* `https://n8n.local`
* `https://minio.local`

> If you use Caddy internal/self-signed TLS, you may need to trust its root CA on your client devices (depending on how your deployment is configured).

---

## 12) Backup persist + secrets

A backup helper is provided:

* Backup (optionally stop/start services around it):

```bash
apps-backup --stop
```

Backups are saved under:

```text
~/.local/share/apps-deployment/backups/
```

Restore from an archive:

```bash
apps-restore --file ~/.local/share/apps-deployment/backups/<archive>.tar.gz --stop
```

---

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

* If Caddy cannot bind port 80, re-check:

```bash
sysctl net.ipv4.ip_unprivileged_port_start
```

It must be `80` (or lower).

* If you changed Quadlets in the repo, reload + restart:

```bash
apps-reload
apps-restart
```

