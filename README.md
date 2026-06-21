<div align="center">

```
██╗  ██╗ █████╗  ██████╗██╗  ██╗██╗      █████╗ ██████╗     ██╗   ██╗██████╗
██║  ██║██╔══██╗██╔════╝██║ ██╔╝██║     ██╔══██╗██╔══██╗    ██║   ██║╚════██╗
███████║███████║██║     █████╔╝ ██║     ███████║██████╔╝    ██║   ██║ █████╔╝
██╔══██║██╔══██║██║     ██╔═██╗ ██║     ██╔══██║██╔══██╗    ╚██╗ ██╔╝██╔═══╝
██║  ██║██║  ██║╚██████╗██║  ██╗███████╗██║  ██║██████╔╝     ╚████╔╝ ███████╗
╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝       ╚═══╝  ╚══════╝
```

**A boot-time pentest environment for Android, built on Termux.**
Service supervisor · live TUI dashboard · web control panel · headless root mode · lazy-installed tool arsenal

🐧 Termux&nbsp;&nbsp;·&nbsp;&nbsp;🔓 root optional&nbsp;&nbsp;·&nbsp;&nbsp;🧰 9 tool modules&nbsp;&nbsp;·&nbsp;&nbsp;🖥️ 7 desktop distros&nbsp;&nbsp;·&nbsp;&nbsp;📡 SSH + 🌐 web panel&nbsp;&nbsp;·&nbsp;&nbsp;⚡ hardware-aware

🛑 **For systems you own or have explicit permission to test.** See [Disclaimer](#-disclaimer).

</div>

---

## 📋 Table of contents

[🧩 What this is](#-what-this-is)
[✨ Features](#-features)
[📦 Requirements](#-requirements)
[⚙️ Installation](#-installation)
[🚀 First run](#-first-run)
[🕹️ Using hacklab day to day](#-using-hacklab-day-to-day)
[▶️⏹️ Starting & stopping services](#-starting--stopping-services)
[🧰 Tool modules](#-tool-modules)
[🖥️ GUI desktop](#-gui-desktop)
[🏗️ Architecture](#-architecture)
[🗂️ Project layout](#-project-layout)
[🗑️ Uninstalling](#-uninstalling)
[🩹 Troubleshooting / FAQ](#-troubleshooting--faq)
[⚠️ Disclaimer](#-disclaimer)

---

## 🧩 What this is

hacklab turns a Termux install into a small, self-contained pentest
environment that can boot itself up, manage its own services, and grow
its toolset on demand. It runs two ways, and you can have both at once:

- 📱 **No-root:** everything runs inside Termux's own sandbox, triggered at
  boot by the Termux:Boot companion app.
- 🔐 **Root (optional):** a real `chroot` into a minimal Alpine Linux
  filesystem, brought up by a Magisk module independent of Termux
  entirely — gets you raw sockets, SYN scans, and per-service namespace
  isolation that the no-root path can't do.

Out of the box, three services come up automatically: 📡 SSH (`dropbear`),
📊 a metrics writer, and 🌐 a web control panel. Everything else — nmap,
aircrack-ng, metasploit, a graphical desktop, all of it — installs only
the first time you actually select it. Nothing heavy is bundled upfront.

## ✨ Features

- 🧵 **Real service supervisor**, not a flat list of backgrounded
  processes — services are directories with explicit dependencies,
  resolved with a topological sort and cycle detection.
- 🧱 **Per-service namespace isolation** on rooted devices (`mountns` /
  `netns` / `full`), probed for actual kernel support rather than
  assumed from root alone.
- 🧭 **One unified command** (`hacklab`) that works identically whether
  you're in a plain Termux session or SSH'd into the root-mode chroot.
- 📺 **Live terminal dashboard** — a three-pane `tmux` session: status,
  aggregated logs, and a free shell.
- 🌐 **Web control panel**, not just a status page — start/stop/restart
  services, install tool modules, and tail logs from a browser, bound to
  loopback by default.
- 🧰 **Nine lazy-installed tool modules** spanning recon, network, web,
  wireless, password, exploitation, forensics, and reverse engineering.
- ⚡ **Hardware-aware install** — probes CPU (cores, big.LITTLE split,
  NEON/AES/SHA/SVE flags), GPU (Adreno/Mali/PowerVR/Xclipse, OpenCL/Vulkan),
  NPU/DSP, RAM, storage, and thermal headroom with no root required,
  writes the result to `hw-profile.env`, and uses it: GPU compute tooling
  (hashcat, clinfo) only installs when OpenCL is actually present, and
  `net-tools`/`password-tools`/`wireless-tools` print device-tuned flags
  (nmap parallelism, hashcat device type, CPU thread count) when you run
  them.
- 🖥️ **Optional graphical desktop**, two ways: a lightweight style (XFCE,
  LXQt, or i3) running directly over Termux:X11, or a full Linux distro —
  **🐉 Kali Linux**, 🟠 Ubuntu, 🌀 Debian, ⚔️ Arch, 🎩 Fedora, 🦎 openSUSE, or
  🏔️ Alpine — pulled via `proot-distro` with its own desktop installed
  inside, picked at install time and switchable later (`gui-x11.sh
  switch`). The distro path checks free storage and warns if RAM is tight
  before pulling anything heavy.
- 🎛️ **Modern interaction layer** — `gum`/`fzf`/`tmux` instead of plain
  `read` menus, with `gum confirm` gating anything large before it
  downloads.
- 🔑 **Headless root mode** reachable over SSH, so the same interactive
  tooling (gum/fzf/tmux) that only installs cleanly in Termux is still
  available against the chroot's services.

## 📦 Requirements

| | Required for |
|---|---|
| 📲 **Termux**, installed from F-Droid or GitHub releases (not Google Play — the Play Store build is outdated and missing APIs this project relies on) | everything |
| 🥾 **Termux:Boot** app (F-Droid / GitHub releases) | no-root boot-on-startup |
| 🔐 **Root + Magisk** | root-mode chroot, raw sockets, namespace isolation |
| 🖼️ **Termux:X11** app (GitHub releases) | the optional GUI desktop module |
| 📦 `proot-distro` (auto-installed by `gui-x11.sh` on first use) | only the full-distro desktop path (Kali/Ubuntu/Debian/Arch/Fedora/openSUSE/Alpine); ~1–3GB free storage per distro+desktop |
| 🌐 Internet access on first use of each piece | installer bootstraps `gum`/`fzf`/`tmux`; each tool module fetches its own packages on first selection |

Nothing else is required upfront. Root and the GUI app are both fully
optional — the no-root path is a complete, working setup on its own.

### 📲 App download links

Grab these directly — don't search the Play Store, the listings there
are outdated builds with missing APIs this project relies on:

| App | Get it from | Why |
|---|---|---|
| 📲 **Termux** | [F-Droid](https://f-droid.org/packages/com.termux/) · [GitHub Releases](https://github.com/termux/termux-app/releases) | the base terminal — required |
| 🥾 **Termux:Boot** | [F-Droid](https://f-droid.org/packages/com.termux.boot/) | no-root boot-on-startup trigger |
| 🖼️ **Termux:X11** | [GitHub Releases](https://github.com/termux/termux-x11/releases) (`app-universal-debug.apk` if unsure of your CPU arch) | the optional GUI desktop |

⚠️ Install **Termux and Termux:Boot from the same source** (both
F-Droid, or both GitHub) — mixing sources causes a signature mismatch
and Android will refuse to install one of them. GitHub builds of
`termux-app`/`termux-boot` are signed with a shared **test key**, not an
official one — fine for personal use, just don't treat a GitHub APK
from anywhere *other than* `github.com/termux/...` as trustworthy.

## ⚙️ Installation

### ⚡ Fastest way — one line, no zip, no browser

Paste this directly into Termux — it installs `git` if needed, pulls the
whole project in one shot, and runs the installer:

```bash
pkg install -y git && git clone https://github.com/bradleyatieli-prog/Hacklab-v2.git && cd Hacklab-v2 && bash install.sh
```

No `git`? This works too, using just `curl`/`tar` (both ship with Termux):

```bash
curl -L https://github.com/bradleyatieli-prog/Hacklab-v2/archive/refs/heads/main.tar.gz | tar xz && cd Hacklab-v2-main && bash install.sh
```

> 💡 Why `git clone` rather than a single `curl install.sh | bash` pipe:
> `install.sh` copies sibling files (`lib/`, `core/`, `modules/`,
> `services/`, `webdash/`, `boot/`) off disk during the core-install
> phase — piping just the one script's text into `bash` would leave it
> with nothing to copy. `git clone` gets the whole tree in the same
> single command instead.

Updating later, once it's cloned:

```bash
cd Hacklab-v2 && git pull && bash install.sh
```

### 🐢 Or, the manual way

1️⃣ **Install Termux** from F-Droid or GitHub (see [Requirements](#-requirements)).

2️⃣ **Get this project onto the device** — `git clone`, or unzip a
   downloaded copy — into any directory inside Termux.

3️⃣ **Run the installer:**

   ```bash
   cd hacklab-v2
   bash install.sh
   ```

   This probes the device's hardware, installs the core into
   `~/.hacklab`, bootstraps `gum`/`fzf`/`tmux`, detects whether the
   device is rooted, and then asks which boot path you want:

   ```
   Boot-time path:
     1) No-root  — Termux:Boot trigger, service graph runs in Termux sandbox
     2) Root     — Magisk module, real chroot, independent of Termux
     3) Both
   ```

4️⃣ **Finish whichever path(s) you picked** — these are manual by
   Android/Magisk design and can't be scripted around:

   **📱 No-root:**
   - Install the Termux:Boot app and open it once (Android holds it
     "stopped" until you do).
   - Exempt both Termux and Termux:Boot from battery optimization, or
     the boot trigger may get killed before it runs.

   **🔐 Root:**
   - The installer packages a Magisk module zip at
     `~/.hacklab/hacklab-root-module.zip`.
   - In the Magisk app: **Modules → Install from storage** → select that
     zip → reboot. Magisk requires this manual confirmation by design.
   - First boot after install extracts a fresh Alpine rootfs and copies
     the service graph into it — give it a minute before expecting
     `dropbear` to answer on `:8022`.

## 🚀 First run

You don't have to wait for a reboot to try it:

```bash
bash ~/.hacklab/lib/svc-engine.sh up   # bring services up right now
hacklab                                 # the unified launcher
```

`hacklab` is symlinked onto Termux's `PATH` by the installer, so it's
just a bare command from any session afterward. From here on, it's the
only entrypoint you need — the menu adapts depending on whether you're
in Termux or SSH'd into the root chroot.

## 🕹️ Using hacklab day to day

Running `hacklab` from a normal Termux session gives you:

- 📺 **Dashboard** — opens the TUI (status / logs / shell panes). Re-attaches
  if it's already running instead of starting a duplicate.
- 🧰 **Tool modules** — the `fzf`-searchable module picker; install or run
  any of the [nine tool modules](#-tool-modules).
- 🎚️ **Service control** — pick a service, then start / stop / restart / view
  its logs. (Full reference: [Starting & stopping services](#-starting--stopping-services) below.)
- 🌐 **Web dashboard URL** — a reminder of where the browser control panel
  lives (`http://127.0.0.1:8080`).
- 📡 **SSH into root-mode chroot** — only shown if dropbear on the chroot
  side is actually reachable; jumps straight into an SSH session.

SSH into the chroot (or run `hacklab` from inside it) and you land
directly in the same TUI dashboard — no extra menu layer, since the
chroot is headless and SSH is already the interactive session.

## ▶️⏹️ Starting & stopping services

Three services are already managed for you: 📡 `dropbear` (SSH),
📊 `metrics` (the status feed both dashboards read from), and 🌐 `webdash`
(the browser panel, which depends on `metrics`). They come up
automatically at boot — this section is for controlling them by hand:
checking what's running, restarting one that's misbehaving, or shutting
everything down before you put the device away.

**Three ways to do it, same underlying engine:**

### 🅰️ The menu (easiest — no typing commands)

```bash
hacklab
```
→ **Service control** → pick a service → pick **start / stop / restart /
logs**. This is just a friendlier face on the exact commands below.

### 🅱️ Direct commands (fastest if you already know the name)

```bash
bash ~/.hacklab/lib/svc-engine.sh status              # 👀 what's running right now
bash ~/.hacklab/lib/svc-engine.sh up                   # ▶️  start EVERYTHING, dependency-ordered
bash ~/.hacklab/lib/svc-engine.sh down                 # ⏹️  stop EVERYTHING, reverse order
bash ~/.hacklab/lib/svc-engine.sh start   <name>       # ▶️  start one service (+ its deps)
bash ~/.hacklab/lib/svc-engine.sh stop    <name>       # ⏹️  stop just one service
bash ~/.hacklab/lib/svc-engine.sh restart <name>       # 🔁 stop then start one service
bash ~/.hacklab/lib/svc-engine.sh logs    <name>       # 📜 tail -f that service's log
```

Spelled out for each shipped service — copy/paste exactly:

| Service | ▶️ Start | ⏹️ Stop | 🔁 Restart | 📜 Logs |
|---|---|---|---|---|
| 📡 `dropbear` (SSH, `:8022`) | `bash ~/.hacklab/lib/svc-engine.sh start dropbear` | `bash ~/.hacklab/lib/svc-engine.sh stop dropbear` | `bash ~/.hacklab/lib/svc-engine.sh restart dropbear` | `bash ~/.hacklab/lib/svc-engine.sh logs dropbear` |
| 📊 `metrics` (status feed) | `bash ~/.hacklab/lib/svc-engine.sh start metrics` | `bash ~/.hacklab/lib/svc-engine.sh stop metrics` | `bash ~/.hacklab/lib/svc-engine.sh restart metrics` | `bash ~/.hacklab/lib/svc-engine.sh logs metrics` |
| 🌐 `webdash` (web panel, `:8080`) | `bash ~/.hacklab/lib/svc-engine.sh start webdash` | `bash ~/.hacklab/lib/svc-engine.sh stop webdash` | `bash ~/.hacklab/lib/svc-engine.sh restart webdash` | `bash ~/.hacklab/lib/svc-engine.sh logs webdash` |

> 💡 `start webdash` also brings up `metrics` first automatically, since
> `webdash` depends on it — you don't need to start dependencies
> yourself. `stop` only stops the one you named, not its dependents.

### 🅲️ The web panel (point-and-click, once `webdash` is up)

Open **http://127.0.0.1:8080** in a browser on the same device → each
service has its own **Start / Stop / Restart** buttons and a live log
tail. Same engine underneath as the other two methods, just a browser
instead of a terminal.

---

**Quick troubleshooting while controlling services:**

```bash
bash ~/.hacklab/lib/svc-engine.sh status
```
…shows a live table of every service, its type, PID, and health —
check this first if something seems down before trying to restart it
blindly.

## 🧰 Tool modules

All lazy-installed — nothing here is pulled in until you select it from
`core/menu.sh` (or `hacklab` → tool modules) for the first time.

| Module | Installs | Notes |
|---|---|---|
| 🕵️ `recon-osint` | `whois`, `dnsutils`, theHarvester | OSINT & DNS enumeration |
| 🌍 `net-tools` | `nmap`, `net-tools`, `traceroute`, `mtr` | auto-detects root and tells you which nmap scan types are actually available, instead of failing silently mid-scan; prints CPU-tuned `nmap` parallelism flags |
| 🕸️ `web-tools` | `sqlmap`, `nikto` | web app testing |
| 📡 `wireless-tools` | `aircrack-ng` | monitor mode is blocked by almost all stock Android Wi-Fi firmware — packet injection will likely fail regardless of root. Chipset/driver limitation, not something a script can route around |
| 🔑 `password-tools` | `hydra`, `john`, + `hashcat`/`clinfo` if OpenCL GPU detected | password auditing; prints GPU-tuned `hashcat` flags when available |
| 💣 `exploit-tools` | `metasploit` (~1.5GB+) | `gum confirm` gates this explicitly, so the download size is a deliberate choice, not a surprise |
| 🔬 `forensics-tools` | `binwalk`, `exiftool`, `foremost` | forensics |
| 🔁 `reverse-eng` | `radare2`, `apktool` | reverse engineering, `apktool` useful for Android APK analysis |
| 🖥️ `gui-x11` | `x11-repo`, `termux-x11-nightly`, plus your chosen desktop style/distro | see [GUI desktop](#-gui-desktop) |

## 🖥️ GUI desktop

`gui-x11` gives you a real graphical Linux desktop over Termux:X11 — not
a status page, an actual windowed environment. It asks which **path**
first, then which style/distro within that path:

**🏃 Path 1 — light:** the desktop runs directly in Termux's own userland.
Fastest, smallest, no second OS.

| Style | What you get | Footprint |
|---|---|---|
| 🟦 `xfce` | Full desktop — panel, file manager, settings, the works | Heaviest, most familiar |
| 🟪 `lxqt` | Full desktop, same shape as XFCE (panel + `pcmanfm-qt` file manager) | Noticeably lighter than XFCE |
| ⬛ `i3` | Tiling window manager, keyboard-driven, no taskbar/icons by default | Lightest — no panel daemon, no compositor, no settings daemon |

**🐳 Path 2 — distro:** a complete, unmodified Linux distribution pulled as
an OCI image via `proot-distro` (ptrace-based, no root needed), with a
desktop installed inside it. This is how **🐉 Kali Linux** gets onto the
device — alongside Ubuntu, Debian, Arch, Fedora, openSUSE, and Alpine.
Heavier and slower than the light path (proot adds syscall overhead),
but it's a real distro: full package manager, no Termux-specific
package divergence.

| Distro | Notes |
|---|---|
| 🐉 Kali Linux | The curated pentest distro itself — biggest download |
| 🟠 Ubuntu | Widest package availability, most tutorials |
| 🌀 Debian | Stable, minimal — what Kali is built on |
| ⚔️ Arch Linux | Rolling release, smallest base, more setup work |
| 🎩 Fedora | Current upstream packages, `dnf` |
| 🦎 openSUSE | `zypper`, Tumbleweed rolling |
| 🏔️ Alpine | musl-based, tiny — lightest of the full distros |

Each gets the same `xfce`/`lxqt`/`i3` style choice for its desktop,
installed with that distro's own package manager (`apt`/`pacman`/`dnf`/
`zypper`/`apk`) — package names can drift between releases, so the
module warns rather than failing silently if a particular combo doesn't
have a known package set yet.

Before pulling a distro it checks free storage under `$HOME` (a distro +
desktop needs roughly 2.5GB+) and, using the hardware profile from
`install.sh`, warns if the device's RAM makes `xfce` a bad fit — `i3` or
the light path will run noticeably better under ~3GB RAM.

**To use it:**

1️⃣ Install the **Termux:X11** app separately (GitHub releases, not Play
   Store) and open it once.

2️⃣ `hacklab` → tool modules → `gui-x11` → confirm install.

3️⃣ Pick light or distro, then the style (and distro, if applicable).

4️⃣ Open the Termux:X11 app, then select `gui-x11` again — this time it
   just launches.

Once a distro is installed, you also get a normal shell into it any
time: `proot-distro login kali` (or `ubuntu`, `debian`, etc.).

Switch path/style/distro later without reinstalling the rest of the project:

```bash
bash ~/.hacklab/modules/gui-x11.sh switch
```

## 🏗️ Architecture

### 🧵 The service engine

`lib/svc-engine.sh` is the core. Services are directories, not scripts:

```
services/<name>/run          the actual process
services/<name>/type         "longrun" or "oneshot"
services/<name>/depends      newline list of prerequisite services
services/<name>/isolate      "none" | "mountns" | "netns" | "full"
services/<name>/healthcheck  exit 0 = healthy (optional)
```

`up` resolves start order with a DFS topological sort and detects
dependency cycles before starting anything — e.g. `webdash` depends on
`metrics`, so metrics always comes up first regardless of directory
iteration order. `down` stops everything in reverse order. `start
<name>` / `stop <name>` act on just one service (`start` walks that
service's own dependency chain only, not the full graph).

Shipped services: `dropbear` (SSH on `:8022`, no deps), `metrics`
(writes `~/.hacklab/status.json` every 2s — the single source both
dashboards read from), `webdash` (depends on `metrics`, serves the
control panel on `127.0.0.1:8080`).

### 🧱 Namespace isolation (root only)

If a service's `isolate` file says `mountns`/`netns`/`full`, and the
device is rooted with namespace support actually available
(`ns_available` probes this with `unshare`, never assumed), the engine
wraps that service's launch command in `unshare` before starting it. No
root or no namespace support → logged warning, runs unisolated. Stock
Android kernels vary a lot here; this is checked, not assumed.

### ⚡ Hardware profile

`install.sh`'s detection phase probes CPU (cores, big.LITTLE split,
NEON/AES/SHA/SVE), GPU (Adreno/Mali/PowerVR/Xclipse, OpenCL/Vulkan),
NPU/DSP presence, RAM, storage, and thermal zones — all without root —
and writes the result to `~/.hacklab/hw-profile.env`. `lib/hw.sh` is the
runtime half: any module sources it to get `HW_*` variables plus
`hw_best_hashcat_args` / `hw_best_nmap_args` / `hw_apply_cpu_governor` /
`hw_apply_gpu_governor`. If the profile hasn't been written yet (e.g. a
module run standalone before `install.sh` completes), `hw.sh` falls back
to safe defaults instead of erroring.

### 🧯 Subprocess error handling

`install.sh` runs under `set -uo pipefail`, deliberately **not** `-e` —
every external command goes through `step()`/`tick()`, which capture
the exit code and decide what to do with it, instead of an unrelated
failure silently killing a 20-phase install partway through.
`bin/hacklab` does use `set -e` (it's interactive and short-lived, so a
genuinely broken state should stop it), which is why every optional
tool check (`ensure_gum`, `ensure_tmux`, ...) and every interactive
picker (`choose()`) is explicitly guarded with `|| true` — cancelling a
menu (Esc/Ctrl-C) returns you to the previous screen, it doesn't crash
the launcher.

### 🥾 Two boot paths

| | No-root | Root (Magisk) |
|---|---|---|
| Trigger | `Termux:Boot` → `BOOT_COMPLETED` | `service.sh`, before any app |
| Execution | service graph runs in Termux's sandbox | real `chroot`, no proot overhead |
| Raw sockets / SYN scans | ❌ | ✅ |
| Per-service isolation | ❌ (no namespaces without root) | ✅ where kernel allows |

Both run the *same* `svc-engine.sh up` — the root path just chroots into
an Alpine rootfs first and runs the engine inside it.

**Where gum/fzf/tmux actually run:** from Termux, where they install
cleanly via `pkg`. The root-mode chroot is headless by design — it runs
the background services, not the interactive menu, since `apk`'s
package set diverges from Termux's. To manage it interactively, SSH in
over dropbear from a Termux session, or run `hacklab` once SSH'd in.

### 🧭 Unified launcher

`bin/hacklab` checks the filesystem to tell which context it's in —
`/etc/alpine-release` plus the chroot's known install path means
root-mode chroot, otherwise Termux — and adapts accordingly (see
[Using hacklab day to day](#-using-hacklab-day-to-day)). Installed on
`PATH` as `hacklab` by `install.sh` (Termux side) and symlinked into the
chroot's `/usr/local/bin` by `customize.sh` (root side) — same command,
same behavior shape, different context underneath.

### 🌐 Web control panel internals

`webdash/server.py` backs the browser control panel. Every name coming
from a request is checked against the real `services/`/`modules/`
directories before touching `subprocess`; calls always pass an argument
list, never `shell=True` with interpolated strings — no
command-injection surface from request bodies. Heavy module installs run
in a background thread and require an explicit `confirm: true` in the
request, mirroring `gum confirm` in the CLI menu. Interactive tools
(`msfconsole` etc.) are deliberately **not** exposed over HTTP — a
stateless request can't usefully drive an interactive terminal program;
those stay in the TUI.

Bound to loopback (`127.0.0.1`) by default. The control-panel actions
aren't inherently more dangerous than local shell access — but that's
only true while it stays off the LAN. Change `HACKLAB_WEBDASH_BIND` in
`services/webdash/run` to `0.0.0.0` only if you understand that means
anyone on the same network can start/stop your services from there.

## 🗂️ Project layout

```
hacklab-v2/
├── install.sh                  installer — hardware detection, core, boot path setup
├── uninstall.sh                 stop services, remove boot triggers, optional full wipe
├── bin/
│   └── hacklab                  unified launcher (Termux + chroot, same command)
├── lib/
│   ├── common.sh                 shared helpers: logging, root/namespace detection,
│   │                              gum/fzf/tmux bootstrap, lazy-install tracking
│   ├── svc-engine.sh              the dependency-graph service supervisor
│   └── hw.sh                      hardware-profile loader + hashcat/nmap/governor helpers
├── core/
│   ├── menu.sh                    fzf-searchable tool-module picker
│   ├── dashboard-tui.sh            tmux 3-pane live dashboard
│   └── status-loop.sh              status pane refresh loop (used by dashboard-tui.sh)
├── services/
│   ├── dropbear/                   SSH, :8022, no dependencies
│   ├── metrics/                    writes status.json every 2s
│   └── webdash/                    web control panel, depends on metrics
├── webdash/
│   ├── index.html, style.css, app.js    the control panel frontend
│   └── server.py                         its API backend
├── modules/                       nine lazy-installed tool modules (see table above)
└── boot/
    ├── noroot/
    │   └── hacklab-boot            Termux:Boot entrypoint
    └── root/
        ├── module.prop              Magisk module metadata
        ├── service.sh                Magisk late_start: chroot + bring services up
        └── customize.sh              runs once at Magisk install: builds the Alpine rootfs
```

## 🗑️ Uninstalling

```bash
bash uninstall.sh
```

Stops all services, removes the no-root boot trigger, and asks whether
to delete `~/.hacklab` entirely. If you flashed the root-mode Magisk
module, that part has to come out through Magisk's own UI — **Magisk app
→ Modules → HackLab v2 Core → trash icon → reboot** — direct deletion of
its files while running can leave dangling chroot mounts behind.

## 🩹 Troubleshooting / FAQ

**❓ Termux:Boot trigger never fires after reboot.**
Open the Termux:Boot app at least once after installing it — Android
holds it "stopped" until you do — and make sure both Termux and
Termux:Boot are exempted from battery optimization.

**❓ Magisk module install seems to hang / asks for confirmation.**
That's expected — Magisk requires manual confirmation through its own
UI for module installs, by design. It isn't scriptable around.

**❓ Web dashboard says "disconnected."**
The `metrics` service is down. Check it with `hacklab` → service
control → `metrics` → logs, or directly:
`bash ~/.hacklab/lib/svc-engine.sh logs metrics`. To bring it back:
`bash ~/.hacklab/lib/svc-engine.sh start metrics`.

**❓ SSH'd into the chroot, but `hacklab` complains tmux/gum are missing.**
Expected — Alpine's `apk` package set diverges from Termux's, and the
chroot is headless by design. It falls back to a plain status print plus
a shell. The full interactive layer is meant to run from a Termux
session connected over SSH, not inside the chroot itself.

**❓ Wireless monitor mode / packet injection doesn't work.**
Near-universal limitation of stock Android Wi-Fi firmware, not something
`wireless-tools` (or any script) can patch around — root doesn't change
this.

**❓ nmap scans fail partway through.**
Run `net-tools` from the menu rather than calling `nmap` directly first —
it checks root and tells you up front which scan types are actually
available (e.g. `-sS`/`-sO` need root; otherwise stick to `-sT`).

**❓ I want the web panel reachable from another device on my network.**
Change `HACKLAB_WEBDASH_BIND` to `0.0.0.0` in `services/webdash/run` —
but understand that exposes start/stop/install control to anyone on the
same network, not just you.

**❓ How do I know if a service is running before I try to (re)start it?**
`bash ~/.hacklab/lib/svc-engine.sh status` — live table of every
service, type, PID, and health. See [Starting & stopping services](#-starting--stopping-services).

## ⚠️ Disclaimer

This project installs and manages real security tooling (port scanners,
password crackers, an exploitation framework, wireless auditing tools,
and more). Use it only against systems you own or have explicit
authorization to test. Nothing here is intended for, or should be used
for, accessing systems without permission.
