max carico su minio
n8n e auto download personale
rimuovere eccesso di log

The fastest way to debug a Quadlet that won’t start is to treat it as **two layers**:

1. **Quadlet generation problem** (your `.container/.network/...` file is invalid or not being picked up)
2. **Generated systemd service / Podman runtime problem** (the service starts but fails)

## 1) Check the right systemd scope first

Use `systemctl --user ...` and put files in `~/.config/containers/systemd/` (or another rootless Quadlet path). Quadlet-generated units are created by the systemd generator (typically under the user runtime generator dir). ([Podman Documentazione][1])

```bash
systemctl --user daemon-reload
systemctl --user list-unit-files | grep -E 'yourname|container|network'
systemctl --user status yourapp.service
```

## 2) Verify the generated service exists and maps to your Quadlet file

This tells you whether Quadlet was parsed at all.

```bash
systemctl --user show yourapp.service | grep -E 'FragmentPath|SourcePath'
```

If `SourcePath` points to your `.container` file, Quadlet generation is working. (Generated units are often under the runtime generator path, not a permanent file you created manually.) ([GitHub][2])

## 3) Read the logs (most useful step)

### Service logs (systemd/journald)

```bash
journalctl --user -u yourapp.service -b --no-pager -n 200
# rootful:
sudo journalctl -u yourapp.service -b --no-pager -n 200
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

---

## 4) Run the Quadlet generator manually (great for silent parse issues)

If `daemon-reload` doesn’t produce what you expect, run the generator manually in verbose / dry-run mode to catch unsupported keys or syntax mistakes.

Typical commands vary by distro/package layout, but commonly:

```bash
/usr/libexec/podman/quadlet --user --dryrun
# or (rootful)
sudo /usr/libexec/podman/quadlet --dryrun
```

This is often the easiest way to spot “I used a field not supported” problems. (This exact class of issue is commonly reported.) ([Podman Documentazione][1])

---

## 5) Inspect the generated unit (what systemd is actually running)

```bash
systemctl --user cat yourapp.service
# rootful:
sudo systemctl cat yourapp.service
```

This shows:

* generated `ExecStart`
* dependency translation (`After=`, `Wants=`, `Requires=`)
* whether your `[Service]` directives were included

Very useful when a `.container` setting didn’t become what you expected.

---

## 6) Check Podman/container-level logs and state

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

---

## 7) Common Quadlet gotchas (very common in practice)

### A) Rootless service not starting at boot: lingering not enabled

For rootless services to keep running without login:

```bash
loginctl enable-linger <username>
```

### B) Rootless trying to bind port 80/443

Rootless Podman cannot bind privileged ports by default. You’ll see errors like permission denied / `rootlessport`.
Options:

* use high ports (e.g. 8080/8443), or
* change kernel sysctl (`net.ipv4.ip_unprivileged_port_start`), if appropriate.

### C) Volume permissions / SELinux labeling

A very common reason for startup failure:

* mounted directory not writable by container user
* SELinux label missing (`:Z` / `:z`) on SELinux systems

### D) Wrong `EnvironmentFile` path

`systemd` reads `EnvironmentFile` in the **host context**, not inside the container.

### E) Dependencies/order confusion

`Requires=` does **not** mean “wait until the other service is fully ready.”
Use a combination of:

* `After=`
* health checks / readiness
* app retry logic
* explicit startup scripts if needed

### F) Pull/build timeout on first start

Quadlet docs note that image pull/build can exceed systemd’s default startup timeout. Consider pre-pulling images or increasing `TimeoutStartSec`. ([Podman Documentazione][1])

---

## 8) Minimal debug workflow I use (copy/paste)

```bash
systemctl --user daemon-reload
systemctl --user status myapp.service -l --no-pager
journalctl --user -u myapp.service -b --no-pager -n 200
systemctl --user cat myapp.service
systemctl --user show myapp.service | grep -E 'FragmentPath|SourcePath'
podman ps -a
podman logs myapp
```

---

## 9) If you want a deeper trace

You can increase Podman verbosity in the Quadlet (for troubleshooting) using `PodmanArgs=--log-level=debug` in the relevant section, then reload and retry. (Remove afterward.) This is a common technique in Quadlet debugging reports and examples. ([GitHub][3])

---

If you want, paste your `.container` file and the output of:

```bash
systemctl --user status <name>.service -l --no-pager
journalctl --user -u <name>.service -b --no-pager -n 100
```

(and I’ll help pinpoint the failure quickly).

[1]: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html?utm_source=chatgpt.com "podman-systemd.unit"
[2]: https://github.com/containers/podman/discussions/25672?utm_source=chatgpt.com "Quadlet are not working exactly as in the documentation in ..."
[3]: https://github.com/containers/podman/issues/23990?utm_source=chatgpt.com "[Quadlet][Rootless] The generated systemd service exits ..."
