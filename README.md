# Quake II Server (Docker)

This repository provides a Dockerized **Quake II** dedicated server. It runs [Q2PRO](https://github.com/q2pro/q2pro)'s dedicated server (`q2proded`) and its deathmatch/co-op game library, both built from source into the image, plus the [Threewave CTF](https://github.com/yquake2/ctf) game library. You supply the game data. Mods with a Linux game library are supported.
The image builds on [`lancommander/base`](https://github.com/LANCommander/LANCommander.Servers.Base). It supports file overlaying using OverlayFS.

---

## Features

- Q2PRO for Linux, built from a pinned commit of the Q2PRO source (or one you pick)
- Deathmatch, co-op and Capture the Flag (`QUAKE2_GAME=ctf`) game libraries built in
- The server's name, map, map rotation, game mode, limits and passwords are environment variables, written into a config file the server execs at startup
- Accepts Q2PRO, R1Q2 and original (protocol 34) Quake II clients
- Optional HTTP file server for Q2PRO/R1Q2 clients' HTTP downloads
- Supports file overlaying using OverlayFS (no file copying required)

## Docker Compose Example

```yaml
services:
  quake2:
    image: lancommander/quake2:latest
    container_name: quake2

    ports:
      - "27910:27910/udp"

    volumes:
      - ./config:/config

    environment:
      QUAKE2_SERVER_NAME: "My Quake II Server"
      QUAKE2_MAP: "q2dm1"
      QUAKE2_MAP_LIST: "q2dm1 q2dm2 q2dm3 q2dm8"
      QUAKE2_RCON_PASSWORD: "changeme"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

The in-game LAN browser (Multiplayer → Join Network Server → Refresh) finds servers by broadcasting to port 27910. That needs the container on the LAN itself (macvlan/ipvlan, or `network_mode: host`) and the default `QUAKE2_PORT`; with port mapping, clients join by IP (`connect <ip>` in the console).

---

## Game Files

The image contains only the server binary and game libraries. Copy the `baseq2/` folder of a Quake II install (`pak0.pak`, `pak1.pak`, `pak2.pak`, and any extra paks or `.pkz` files) into `config/Server/`. For CTF, also copy the `ctf/` folder (`ctf/pak0.pak`). The server stops with an error if `baseq2/pak0.pak` is missing.

The Windows `gamex86.dll` files in an install aren't used. The game library comes from `/opt/q2pro/<game>/gamex86_64.so` (`baseq2` and `ctf` are built in), or from `<QUAKE2_GAME>/gamex86_64.so` in `Server/` or `Overlay/` for another mod. A mod without a Linux game library runs on the `baseq2` game.

Quake II on Linux opens files by their lowercase names, which is how the game data is shipped. Rename any files with capitals.

## Directory Layout (Host)

```text
.
└── config/
    ├── Server/            # Game data: baseq2/pak*.pak, ctf/pak0.pak, mod folders
    ├── Overlay/           # Your files, layered on top of Server/ (<game>/server.cfg, generated lancommander.cfg, logs)
    ├── Merged/            # Overlayfs merged view (auto-created, the server runs here)
    └── Scripts/
        └── Hooks/         # PowerShell scripts run at container lifecycle hooks
```

---

## Environment Variables

These are in addition to the [base image's variables](https://github.com/LANCommander/LANCommander.Servers.Base#environment).
The settings are written into `<QUAKE2_GAME or baseq2>/lancommander.cfg` on every start. Settings left empty are left out, so you can set them in `server.cfg` next to it instead.

| Variable | Description | Default |
|----------|-------------|---------|
| `QUAKE2_GAME` | Game folder (`game`): empty for `baseq2`, `ctf` for Capture the Flag, or a mod folder | |
| `QUAKE2_PORT` | `net_port` (game port) | `27910` |
| `QUAKE2_MAX_PLAYERS` | `maxclients`, the player slots (fixed at startup) | `16` |
| `QUAKE2_SERVER_NAME` | `hostname` | `Quake II Server` |
| `QUAKE2_MAP` | First map (`q2dm1` to `q2dm8`, `base1`, `q2ctf1` to `q2ctf5`, ...). Empty leaves starting a map to `server.cfg` | `q2dm1` |
| `QUAKE2_MAP_LIST` | `sv_maplist`, maps to cycle through when a limit is hit, separated by spaces or commas | |
| `QUAKE2_DEATHMATCH` | `deathmatch`: `1` on, `0` off | `1` |
| `QUAKE2_COOP` | `coop`: `1` for co-op. Turning it on also sets `deathmatch 0` | `0` |
| `QUAKE2_DMFLAGS` | `dmflags`, the deathmatch options bit field (see below) | |
| `QUAKE2_FRAG_LIMIT` | `fraglimit` (0 = none) | `20` |
| `QUAKE2_TIME_LIMIT` | `timelimit` in minutes (0 = none) | `15` |
| `QUAKE2_CAPTURE_LIMIT` | `capturelimit`, flag captures that end a CTF map (0 = none) | |
| `QUAKE2_SKILL` | `skill`, monster difficulty for co-op: `0` easy to `3` hard+ | `1` |
| `QUAKE2_PASSWORD` | `sv_password`, required to join | |
| `QUAKE2_RCON_PASSWORD` | `rcon_password`; empty disables remote console | |
| `QUAKE2_ALLOW_DOWNLOAD` | `allow_download`: clients may download missing maps, models and sounds from the server | `1` |
| `QUAKE2_DOWNLOAD_URL` | `sv_downloadserver`, base URL for Q2PRO/R1Q2 HTTP downloads (e.g. `http://<server ip>/`) | |
| `HTTP_FILESERVER_ENABLED` | Serve `Merged/` on port 80 for `QUAKE2_DOWNLOAD_URL` | `false` |
| `HTTP_FILESERVER_WEB_ROOT` | Directory served by the HTTP file server | `/config/Merged` |
| `HTTP_FILESERVER_FILE_PATTERN` | Regex of paths the HTTP file server allows | maps, models, sound, sprites, textures, pics, players, env |
| `START_EXE` | Launcher | `/usr/local/bin/quake2-server` |
| `START_ARGS` | Extra command line, inserted before `+map` (e.g. `+set sv_fps 20`) | |

Common `dmflags` values are `16` (instant items, the default), `20` (adds weapons stay), and `280084`, the CTF default from `ctf/server.cfg` (weapons stay, instant items, spawn farthest, force respawn, quad drop, armor protect).

See [Documentation/Docker.md](Documentation/Docker.md) for more detail.

---

## Building

The image is built `FROM lancommander/base:latest` by default. A build stage compiles Q2PRO and the CTF game:

| Build arg | Description | Default |
|-----------|-------------|---------|
| `Q2PRO_REF` | Commit or tag of [q2pro/q2pro](https://github.com/q2pro/q2pro) to build | `601a8df8` (r3834) |
| `CTF_REF` | Commit or tag of [yquake2/ctf](https://github.com/yquake2/ctf) to build | `8927dcbf` |
| `BASE_IMAGE` | Runtime base image | `lancommander/base:latest` |

The versions built are in `/opt/q2pro/VERSION`, and the Q2PRO version is in the server's startup log and its `status` reply.

```bash
docker build --build-arg BASE_IMAGE=lancommander/base:local -t lancommander/quake2:local .
```

---

## License

Quake II is a trademark of id Software. Its game data is not included and is distributed under its own license. Q2PRO and the CTF game source are GPLv2.
This repository contains only Docker build logic and helper scripts licensed under MIT.
