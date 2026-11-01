---
sidebar_label: Docker
---

# Quake II Docker Container

This Docker container runs a Quake II dedicated server. It is built on the base image and runs [Q2PRO](https://github.com/q2pro/q2pro)'s dedicated server, `q2proded`. The image compiles `q2proded`, Q2PRO's `baseq2` game library and the [Threewave CTF](https://github.com/yquake2/ctf) game library from pinned source commits at build time (`Q2PRO_REF` and `CTF_REF` change them). You supply the game data.

## Quick Start

```yaml
services:
  quake2:
    image: lancommander/quake2:latest
    container_name: quake2

    ports:
      - 27910:27910/udp

    volumes:
      - "/data/Servers/Quake II/Deathmatch:/config"

    environment:
      QUAKE2_SERVER_NAME: "My Quake II Server"
      QUAKE2_MAP: "q2dm1"
      QUAKE2_RCON_PASSWORD: "changeme"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

Before the first start, copy the `baseq2/` folder (`pak0.pak`, `pak1.pak`, `pak2.pak`) into `Server/`, and `ctf/` or any mod folders next to it.

## How It Starts

1. `PostInitialization/30-ConfigureQuake2.ps1` checks for `baseq2/pak0.pak` and writes the non-empty `QUAKE2_*` settings into `<QUAKE2_GAME or baseq2>/lancommander.cfg` as `set` commands. When `QUAKE2_MAP` is set, that file starts with `exec server.cfg`, so your own `server.cfg` runs first and the `QUAKE2_*` settings override it. Any `map` command in `server.cfg` is then commented out (the stock `ctf/server.cfg` ends with `map q2ctf1`), because it would start the server before the other settings apply and Q2PRO would ignore the launcher's `+map`. When `QUAKE2_MAP` is empty, `exec server.cfg` comes last instead, so `server.cfg` can override everything and has to start a map itself. The hook writes through `Merged/`, so its files land in `Overlay/`.
2. `START_EXE` (`/usr/local/bin/quake2-server`) runs from `Merged/`:

   ```text
   /opt/q2pro/q2proded +set basedir /config/Merged +set libdir /opt/q2pro +set homedir ""
       +set sys_forcegamelib <mod library or empty> +set net_port 27910 +set maxclients 16
       +set game <QUAKE2_GAME> +exec lancommander.cfg <START_ARGS> +map q2dm1
   ```

   `basedir` is `Merged/` and `homedir` is empty, so logs, demos and anything else the server writes land in `Overlay/`. The game library is loaded from `/opt/q2pro/<game>/gamex86_64.so`, falling back to `/opt/q2pro/baseq2/`. If `Merged/<QUAKE2_GAME>/gamex86_64.so` exists, it is loaded instead (`sys_forcegamelib`).

## Configuration Options

### Ports

- **27910/udp**: game, server info queries and LAN browser (`QUAKE2_PORT`).
- **27910/tcp**: MVD/GTV spectator relay connections, only used when you turn on MVD in `server.cfg` (`sv_mvd_enable`).
- **80/tcp**: HTTP downloads (optional, `HTTP_FILESERVER_ENABLED`).

### Environment Variables

See the [README](../README.md#environment-variables) for the full table.

### server.cfg

`Overlay/<QUAKE2_GAME or baseq2>/server.cfg` is yours to create and edit. Any console command works there, for example `set sv_fps 20` (Q2PRO's higher tick rate, for clients that support it), `set sv_iplimit 0` (allow many clients from one address), `set public 0` or `set logfile 2`. Use `set` for game settings (`fraglimit`, `dmflags`, `sv_maplist`, ...), because the game doesn't create those until the first map loads. `QUAKE2_*` variables that are set override the same settings in it; clear a variable (set it to `""`) to control that setting from `server.cfg` instead.

### Game modes

| Mode | Settings |
|------|----------|
| Deathmatch | `QUAKE2_DEATHMATCH=1`, a `q2dm1` to `q2dm8` map |
| Capture the Flag | `QUAKE2_GAME=ctf`, `QUAKE2_MAP=q2ctf1` (to `q2ctf5`), `QUAKE2_CAPTURE_LIMIT=8`, `QUAKE2_DMFLAGS=280084`. Needs `ctf/pak0.pak` |
| Co-op | `QUAKE2_COOP=1` (sets `deathmatch 0`), `QUAKE2_MAP=base1`, `QUAKE2_SKILL` for difficulty, `QUAKE2_FRAG_LIMIT=0`, `QUAKE2_TIME_LIMIT=0` |

### Maps

When the frag, time or capture limit is reached, the server moves to the next map in `QUAKE2_MAP_LIST` (`sv_maplist`), wrapping around at the end; this works in both the `baseq2` and CTF games. A map that isn't in the list, or no list at all, goes to the map's own exit (`target_changelevel`), or replays the same map when it has none. `QUAKE2_DMFLAGS` with `32` (same level) always replays the map. Admins can change the map in game with `rcon gamemap <map>`, and in CTF also with the `admin` menu and `warp` command.

### Remote console

With `QUAKE2_RCON_PASSWORD` set, run console commands from a client with `rcon_password <password>` and `rcon <command>` (for example `rcon gamemap q2dm3` or `rcon status`).

### HTTP downloads

Q2PRO and R1Q2 clients can download missing maps and models over HTTP instead of the slow in-game download. Set `HTTP_FILESERVER_ENABLED=true` and `QUAKE2_DOWNLOAD_URL=http://<server address>/`. The file server serves `Merged/`, so a client asking for `<game>/maps/x.bsp` gets `Merged/<game>/maps/x.bsp`. `HTTP_FILESERVER_FILE_PATTERN` limits it to content folders, so paks, configs and logs aren't served. Only loose files can be downloaded: a map inside a `.pak` must be extracted to `<game>/maps/` to be served.

### Hooks

Put `.ps1` scripts in `config/Scripts/Hooks/<HookName>/` to run at the base image's lifecycle hooks (`PreInitialization`, `PostInitialization`, `ServerStarted`, `ServerStopped`).

## Troubleshooting

- **`baseq2/pak0.pak not found`**: the game data isn't in `Server/`, or the folder or file names have capitals. Copy `baseq2/` from a Quake II install and use lowercase names.
- **The server starts on a different map than `QUAKE2_MAP`, with "Using 'map' will cause full server restart"**: a config ran a `map` command before the launcher's `+map`. The hook comments out `map` lines in `<game>/server.cfg`; look for one in another config that `server.cfg` execs.
- **`Couldn't exec server.cfg`** in the log is harmless: there's no `server.cfg` for the game yet.
- **A mod runs the deathmatch game instead of its own**: the mod has only a Windows `gamex86.dll`. Put a Linux `gamex86_64.so` built for it in `Overlay/<mod>/`.
- **Settings in `server.cfg` like `fraglimit 30` do nothing, or print "Unknown command"**: use `set fraglimit 30`. The game's cvars don't exist yet when `server.cfg` runs.
- **Server not in the LAN browser**: the browser finds servers by UDP broadcast to port 27910, so the container needs its own LAN address (macvlan/ipvlan) or host networking, and `QUAKE2_PORT` must stay `27910`. With port mapping, clients join by IP (`connect <ip>:27910` in the console).
- **Everyone behind one address can't join**: Q2PRO limits connections per IP (`sv_iplimit`, default 3). Add `set sv_iplimit 0` to `server.cfg` for LAN parties behind NAT.
