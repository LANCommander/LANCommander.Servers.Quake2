# syntax=docker/dockerfile:1.7

# Override to build against a locally built base, e.g. lancommander/base:local
ARG BASE_IMAGE=lancommander/base:latest

# ----------------------------
# Build Q2PRO's dedicated server (q2proded) and its baseq2 game library, and the Threewave CTF
# game library, from source. Neither project publishes Linux binaries.
#   - Q2PRO_REF is a commit or tag of https://github.com/q2pro/q2pro, the preserved Q2PRO
#     source. Q2PRO servers accept Q2PRO, R1Q2 and original (protocol 34) Quake II clients
#   - CTF_REF is a commit or tag of https://github.com/yquake2/ctf, id's CTF 1.52 source kept
#     buildable by the Yamagi Quake II project
#   - Only q2proded and the game library are built; the client and its libraries are skipped
# ----------------------------
FROM debian:bookworm-slim AS build

ARG Q2PRO_REF=601a8df8433b0c50dbbe37c0716c3793fff140a7
ARG CTF_REF=8927dcbf85d7aea8c1f660eaa4d9a5a0d263bace

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        make \
        gcc \
        libc6-dev \
        pkg-config \
        python3 \
        meson \
        ninja-build \
        zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

# Full clone: Q2PRO's version string (r<commit count>~<sha>) comes from git history
RUN git clone https://github.com/q2pro/q2pro.git /src/q2pro && \
    git -C /src/q2pro checkout --detach "${Q2PRO_REF}" && \
    cd /src/q2pro && \
    meson setup build \
        --buildtype=release \
        --wrap-mode=nodownload \
        -Dsystem-wide=false \
        -Dzlib=enabled \
        -Dsdl2=disabled \
        -Dx11=disabled \
        -Dwayland=disabled \
        -Dopenal=disabled \
        -Dlibcurl=disabled \
        -Dlibpng=disabled \
        -Dlibjpeg=disabled \
        -Davcodec=disabled && \
    meson compile -C build q2proded gamex86_64 && \
    mkdir -p /opt/q2pro/baseq2 && \
    cp build/q2proded /opt/q2pro/ && \
    cp build/gamex86_64.so /opt/q2pro/baseq2/ && \
    python3 version.py > /opt/q2pro/VERSION

RUN git clone https://github.com/yquake2/ctf.git /src/ctf && \
    git -C /src/ctf checkout --detach "${CTF_REF}" && \
    make -C /src/ctf -j"$(nproc)" && \
    mkdir -p /opt/q2pro/ctf && \
    cp /src/ctf/release/game.so /opt/q2pro/ctf/gamex86_64.so && \
    echo "ctf $(git -C /src/ctf rev-parse --short HEAD)" >> /opt/q2pro/VERSION

# ----------------------------
# Runtime
# ----------------------------
FROM ${BASE_IMAGE}

# ----------------------------
# Server settings
#   - Quake II needs the game data: baseq2/pak0.pak (and pak1.pak, pak2.pak) in /config/Server,
#     plus ctf/pak0.pak for CTF. q2proded and the Linux game libraries are in /opt/q2pro
#   - The QUAKE2_* settings are written into <QUAKE2_GAME or baseq2>/lancommander.cfg on every
#     start, which the server execs before +map. Empty settings are left out
#   - The optional HTTP file server serves Merged/ for Q2PRO/R1Q2 clients' HTTP downloads
#     (QUAKE2_DOWNLOAD_URL), limited to content folders so paks and configs aren't served
# ----------------------------
ENV QUAKE2_GAME="" \
    QUAKE2_PORT="27910" \
    QUAKE2_MAX_PLAYERS="16" \
    QUAKE2_SERVER_NAME="Quake II Server" \
    QUAKE2_MAP="q2dm1" \
    QUAKE2_MAP_LIST="" \
    QUAKE2_DEATHMATCH="1" \
    QUAKE2_COOP="0" \
    QUAKE2_DMFLAGS="" \
    QUAKE2_FRAG_LIMIT="20" \
    QUAKE2_TIME_LIMIT="15" \
    QUAKE2_CAPTURE_LIMIT="" \
    QUAKE2_SKILL="1" \
    QUAKE2_PASSWORD="" \
    QUAKE2_RCON_PASSWORD="" \
    QUAKE2_ALLOW_DOWNLOAD="1" \
    QUAKE2_DOWNLOAD_URL="" \
    HTTP_FILESERVER_ENABLED="false" \
    HTTP_FILESERVER_WEB_ROOT="/config/Merged" \
    HTTP_FILESERVER_FILE_PATTERN="^/[^/]+/(maps|models|sound|sprites|textures|pics|players|env)/.*\.(bsp|md2|sp2|wal|pcx|tga|png|jpg|wav|ogg)$" \
    START_EXE="/usr/local/bin/quake2-server" \
    START_ARGS=""

COPY --from=build /opt/q2pro/ /opt/q2pro/

COPY Scripts/quake2-server /usr/local/bin/quake2-server
RUN chmod +x /usr/local/bin/quake2-server

COPY Hooks/ "${BASE_HOOKS}/"

# 27910/udp: game, server info queries and LAN browser (QUAKE2_PORT)
# 27910/tcp: MVD/GTV spectator relay connections, only used when MVD is enabled in server.cfg
# 80/tcp:    HTTP downloads, when HTTP_FILESERVER_ENABLED=true
EXPOSE 27910/udp
EXPOSE 27910/tcp
EXPOSE 80/tcp

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.ps1"]
