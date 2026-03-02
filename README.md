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

After reboot, set the network connection.
Get the network name with:

```bash
nmcli connection show
```

And set it with:

```bash
nmcli con mod "enps0n1" ipv4.addresses 192.168.2.200/16
nmcli con mod "enps0n1" ipv4.gateway 192.168.0.1
nmcli con mod "enps0n1" ipv4.dns "8.8.8.8,8.8.4.4"
nmcli con mod "enps0n1" ipv4.method manual
nmcli con mod "enps0n1" ipv6.method disabled
```

Pick a local domain you control on your LAN, for example:
`example.com` (so you will use `apps.example.com`, `grist.example.com`, etc.) 

You must ensure that the following names resolve to your server’s IP (eg. 192.168.2.200):
`apps.example.com`, `grist.example.com`, `dex.example.com`, `n8n.example.com`, and `minio.example.com`.

Check with: `nslookup apps.example.com`

Create A/AAAA records pointing to the server IP for:
`apps.example.com`, `grist.example.com`, `dex.example.com`, `n8n.example.com`, and `minio.example.com`.

Then set the hostname of your server with:

```bash
sudo hostnamectl set-hostname apps
```

Now you can ssh into your server with:
```bash
ssh admin@apps.example.com
```

Copy your ssh public key for passwordless login into the `~/.ssh/authorized_keys` file:

```bash
mkdir .ssh
vi .ssh/authorized_keys
```

If your server is behind a proxy, crete the `/etc/proxy.env` file
If needed, encode the backslash in the username with `%5c`:

```text
http_proxy=http://username:password@proxy.example.com:3128
HTTP_PROXY=http://username:password@proxy.example.com:3128
https_proxy=http://username:password@proxy.example.com:3128
HTTPS_PROXY=http://username:password@proxy.example.com:3128
no_proxy=localhost,127.0.0.1,example.com,*.example.com
NO_PROXY=localhost,127.0.0.1,example.com,*.example.com
```

Then call it from the systemd services that need it:

```bash
sudo -i

# rpm-ostree upgrades
mkdir -p /etc/systemd/system/rpm-ostreed.service.d
cat > /etc/systemd/system/rpm-ostreed.service.d/99-proxy.conf << EOF
[Service]
EnvironmentFile=/etc/proxy.env
EOF

# rpm-ostree-countme service
mkdir -p /etc/systemd/system/rpm-ostree-countme.service.d
cat > /etc/systemd/system/rpm-ostree-countme.service.d/99-proxy.conf << EOF
[Service]
EnvironmentFile=/etc/proxy.env
EOF

# fwupd-refresh service
mkdir -p /etc/systemd/system/fwupd-refresh.service.d
cat > /etc/systemd/system/fwupd-refresh.service.d/99-proxy.conf << EOF
[Service]
EnvironmentFile=/etc/proxy.env
EOF

systemctl daemon-reload
systemctl restart rpm-ostreed.service rpm-ostree-countme fwupd-refresh.service
```

and set it for the bash console, too:

```bash
sudo -i
mkdir -p /etc/profile.d
cat > /etc/profile.d/proxy.sh << EOF
# Systemwide proxy
set -a
. /etc/proxy.env
set +a
EOF
```

Upgrade the server now:

```bash
rpm-ostree upgrade
```

Install cockpit and some other tools:

```bash
sudo -i
rpm-ostree install cockpit-system cockpit-ws cockpit-files cockpit-networkmanager cockpit-ostree cockpit-podman cockpit-selinux cockpit-storaged nano git bind-utils rsync
systemctl reboot
```

after the reboot, enable cockpit:

```bash
sudo systemctl enable --now cockpit.socket
sudo firewall-cmd --add-service=cockpit
sudo firewall-cmd --add-service=cockpit --permanent
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
podman pull docker.io/minio/mc:RELEASE.2025-07-21T05-28-08Z-cpuv1
podman pull ghcr.io/ict-vvf-genova/dex-smtp:master
podman pull docker.io/gristlabs/grist:1.7.11
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

## Configure secrets

Edit the secrets file:

```bash
nano ~/apps-secrets/apps-secrets.env
```

Set at least:

```bash
DOMAIN=example.com
```

Adjust any other variables your quadlets require (OIDC, passwords, tokens, etc.).

Keep this file **private**, the installer sets permissions to `0600`.

## Reboot

Reboot the server to validate boot-time behavior (linger + user services):

```bash
sudo systemctl reboot
```

After reboot, you do not need to log in to start services, because linger is enabled.

## Init minio bucket

Run the `~/apps-deployment/tools/apps-init-bucket.sh` script.

The script is going read the following variables from your `apps-secret.env` file:
ADMIN_EMAIL, DEFAULT_PASSWORD, MINIO_DEFAULT_BUCKET

Reboot the server to check the services are ok:

```bash
sudo systemctl reboot
```

## Verify access

From a client machine, open:

* `https://apps.example.com`
* `https://grist.example.com`
* `https://dex.example.com`
* `https://n8n.example.com`
* `https://minio.example.com`

> If you use Caddy internal/self-signed TLS, you may need to trust its root CA on your client devices
> (depending on how your deployment is configured).

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
curl -k -svo /dev/null https://apps.example.com
```

## Debugging a service

The fastest way to debug a Quadlet that won’t start is to treat it as **two layers**:

1. **Quadlet generation problem** (your `.container/.network/...` file is invalid or not being picked up)
2. **Generated systemd service / Podman runtime problem** (the service starts but fails)

### Check the right systemd scope first

Use `systemctl --user ...` and put files in `~/.config/containers/systemd/` (or another rootless Quadlet path). Quadlet-generated units are created by the systemd generator (typically under the user runtime generator dir).

```bash
systemctl --user daemon-reload
systemctl --user list-unit-files | grep -E 'yourname|container|network'
systemctl --user status yourapp.service
```

### Verify the generated service exists and maps to your Quadlet file

This tells you whether Quadlet was parsed at all.

```bash
systemctl --user show yourapp.service | grep -E 'FragmentPath|SourcePath'
```

If `SourcePath` points to your `.container` file, Quadlet generation is working.
(Generated units are often under the runtime generator path, not a permanent file you created manually.)

### Read the logs (most useful step)

Service logs (systemd/journald):

```bash
journalctl --user -u yourapp.service -b --no-pager -n 200
```

Also check status with full lines:

```bash
systemctl --user status yourapp.service -l --no-pager
```

This usually reveals:

* syntax/parsing errors
* image pull failures
* permission denied on bind mounts
* wrong `EnvironmentFile`
* dependency startup ordering issues
* privileged port errors (rootless port 80/443)

### Run the Quadlet generator manually (great for silent parse issues)

If `daemon-reload` doesn’t produce what you expect, run the generator manually in verbose / dry-run mode to catch unsupported keys or syntax mistakes.

Typical commands vary by distro/package layout, but commonly:

```bash
/usr/libexec/podman/quadlet --user --dryrun
```

This is often the easiest way to spot “I used a field not supported” problems. (This exact class of issue is commonly reported.)

### Inspect the generated unit (what systemd is actually running)

```bash
systemctl --user cat yourapp.service
```

This shows:

* generated `ExecStart`
* dependency translation (`After=`, `Wants=`, `Requires=`)
* whether your `[Service]` directives were included

Very useful when a `.container` setting didn’t become what you expected.

### Check Podman/container-level logs and state

If the service starts but exits/fails quickly:

```bash
podman ps -a
podman logs <container-name>
podman inspect <container-name> --format '{{.State.Status}} {{.State.ExitCode}}'
```

Common findings:

* app inside container crashes
* wrong command/entrypoint
* bad env vars
* config file missing
* volume permission mismatch

### Common Quadlet gotchas (very common in practice)

#### Rootless service not starting at boot: lingering not enabled

For rootless services to keep running without login:

```bash
loginctl enable-linger <username>
```

#### Rootless trying to bind port 80/443

Rootless Podman cannot bind privileged ports by default. You’ll see errors like permission denied / `rootlessport`.
Options:

* use high ports (e.g. 8080/8443), or
* change kernel sysctl (`net.ipv4.ip_unprivileged_port_start`), if appropriate.

#### Volume permissions / SELinux labeling

A very common reason for startup failure:

* mounted directory not writable by container user
* SELinux label missing (`:Z` / `:z`) on SELinux systems

#### Wrong `EnvironmentFile` path

`systemd` reads `EnvironmentFile` in the **host context**, not inside the container.

#### Dependencies/order confusion

`Requires=` does **not** mean “wait until the other service is fully ready.”
Use a combination of:

* `After=`
* health checks / readiness
* app retry logic
* explicit startup scripts if needed

#### Pull/build timeout on first start

Quadlet docs note that image pull/build can exceed systemd’s default startup timeout. Consider pre-pulling images or increasing `TimeoutStartSec`. ([Podman Documentazione][1])

### Minimal debug workflow for copy/paste

```bash
systemctl --user daemon-reload
systemctl --user status myapp.service -l --no-pager
journalctl --user -u myapp.service -b --no-pager -n 200
systemctl --user cat myapp.service
systemctl --user show myapp.service | grep -E 'FragmentPath|SourcePath'
podman ps -a
podman logs myapp
```

### If you want a deeper trace

You can increase Podman verbosity in the Quadlet (for troubleshooting) using `PodmanArgs=--log-level=debug` in the relevant section, then reload and retry. (Remove afterward.) This is a common technique in Quadlet debugging reports and examples.
