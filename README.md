[![Code Quality](https://img.shields.io/codacy/grade/5b35c73264f446c482d8076f53845f37)](https://hub.docker.com/r/cm2network/tf2/) [![Docker Build Status](https://img.shields.io/docker/cloud/build/cm2network/tf2.svg)](https://hub.docker.com/r/cm2network/tf2/) [![Docker Stars](https://img.shields.io/docker/stars/cm2network/tf2.svg)](https://hub.docker.com/r/cm2network/tf2/) [![Docker Pulls](https://img.shields.io/docker/pulls/cm2network/tf2.svg)](https://hub.docker.com/r/cm2network/tf2/) [![](https://img.shields.io/docker/image-size/cm2network/tf2)](https://microbadger.com/images/cm2network/tf2) [![Discord](https://img.shields.io/discord/747067734029893653)](https://discord.gg/7ntmAwM)
# Supported tags and respective `Dockerfile` links
-	[`base-x32`, `latest-x32`, `base`, `latest` (*bookworm/x32/Dockerfile*)](https://github.com/CM2Walki/TF2/blob/master/bookworm/x32/Dockerfile)
-	[`metamod-x32`, `metamod` (*bookworm/x32/Dockerfile*)](https://github.com/CM2Walki/TF2/blob/master/bookworm/x32/Dockerfile)
-	[`sourcemod-x32`, `sourcemod` (*bookworm/x32/Dockerfile*)](https://github.com/CM2Walki/TF2/blob/master/bookworm/x32/Dockerfile)
-	[`base-x64`, (*bookworm/x64/Dockerfile*)](https://github.com/CM2Walki/TF2/blob/master/bookworm/x64/Dockerfile)
-	[`metamod-x64` (*bookworm/x64/Dockerfile*)](https://github.com/CM2Walki/TF2/blob/master/bookworm/x64/Dockerfile)
-	[`sourcemod-x64` (*bookworm/x64/Dockerfile*)](https://github.com/CM2Walki/TF2/blob/master/bookworm/x64/Dockerfile)

# What is Team Fortress 2?
Nine distinct classes provide a broad range of tactical abilities and personalities. Constantly updated with new game modes, maps, equipment and, most importantly, hats!
This Docker image contains the dedicated server of the game.

>  [TF2](https://store.steampowered.com/app/440/Team_Fortress_2/)

<img src="https://1000logos.net/wp-content/uploads/2020/09/Team-Fortress-2-logo.png" alt="logo" width="300"/></img>

# How to use this image

## TF2 Classified x64 quickstart (this repo)

This repository's x64 image installs and runs **TF2 Classified dedicated server (AppID `3557020`)** from `/home/steam/tf2classified-dedicated` using `-game tf2classified`. It also installs **TF2 base dedicated content (AppID `232250`)** into `/home/steam/tf2-dedicated` and passes it via `-tf_path`; this is intentional because the TF2 Classified server reads shared base assets from that path.

Linux host example (host networking):
```console
$ docker build -t tf2classified:x64 -f bookworm/x64/Dockerfile .
$ docker run -d --name tf2classified --net=host \
  -e SRCDS_TOKEN={YOURTOKEN} \
  -v $(pwd)/tf2c-data:/home/steam/tf2classified-dedicated \
  tf2classified:x64
```

Windows Docker Desktop / PowerShell example (published ports, no host network mode):
```powershell
docker build -t tf2classified:x64 -f bookworm/x64/Dockerfile .
docker run -d --name tf2classified `
  -e SRCDS_TOKEN={YOURTOKEN} `
  -p 27015:27015/udp -p 27015:27015/tcp -p 27020:27020/udp -p 27005:27005/udp `
  -v ${PWD}/tf2c-data:/home/steam/tf2classified-dedicated `
  tf2classified:x64
```

### Local connection guidance
- Same host as Docker: connect to `127.0.0.1:27015`.
- Same LAN as Docker host: connect to the **host LAN IP** (for example `192.168.1.50:27015`).
- Do **not** assume public-IP-from-LAN works; many routers do not support NAT loopback/hairpin NAT, which causes local retries/timeouts while remote players can still join.

### Required ports
- `27015/udp` (game traffic, required)
- `27015/tcp` (queries/rcon compatibility, recommended)
- `27020/udp` (SourceTV, if used)
- `27005/udp` (client port configured by `SRCDS_CLIENT_PORT`)

### Corruption / pure-server remediation
If logs show `VPK chunk hash does not match`, run a one-time targeted repair on next start:
```console
$ docker stop tf2classified
$ docker run --rm -it --name tf2classified-repair \
  -e SRCDS_REPAIR_VPKS=1 -e STEAMAPP_VALIDATE=1 -e TF2_BASE_VALIDATE=1 \
  -v $(pwd)/tf2c-data:/home/steam/tf2classified-dedicated \
  tf2classified:x64
```
This deletes only the known-bad VPKs (`mb2_tf_content.vpk`, `mb2_shared_content.vpk`, `tf2c_overrides.vpk`), runs validate for appids `3557020` and `232250`, and fails start if files were not restored.

### Good startup log markers
```console
$ docker logs -f tf2classified
```
Confirm:
- `Configured .../addons/metamod.vdf to use addons/metamod/bin/linux64/server...`
- `Metamod loader ... contains IServerPluginCallbacks marker.`
- `SourceMod detected at .../addons/sourcemod` (sourcemod image)
- `Set SteamAppId=3557020, SteamGameId=3557020` (or your explicit overrides)
- no `SteamAPI_Init() failed; create pipe failed`
- no `Tried to access Steam interface ... before SteamAPI_Init succeeded`
- server reaches Steam secure mode (no insecure fallback unless explicitly requested)

If you do see `Tried to access Steam interface ... before SteamAPI_Init succeeded`, first verify `SRCDS_TOKEN` is a real GSLT (not `0`/`changeme`) when `SRCDS_SECURED=1`. The x64 entrypoint now fails fast with a clear startup error when a placeholder token is used in secure mode.

### Steamclient symlink validation + diagnostic mode
- The steam runtime commonly places `/home/steam/.steam/sdk64/steamclient.so` as a symlink to the SteamCMD copy. A plain `file /path/to/steamclient.so` check reports `symbolic link to ...`, which is not enough to validate architecture.
- The x64 entrypoint now validates the dereferenced file (`readlink -f` + `file -L`) and requires `ELF 64-bit` **and** `shared object`, then runs `ldd -r` and fails on any `not found`/`undefined symbol`.
- To collect startup evidence without changing default behavior, run with `SRCDS_DIAG=1`:

```console
$ docker run --rm -it --name tf2classified-diag \
  -e SRCDS_TOKEN={YOURTOKEN} \
  -e SRCDS_DIAG=1 \
  -v $(pwd)/tf2c-data:/home/steam/tf2classified-dedicated \
  tf2classified:x64
```

Expected `SRCDS_DIAG=1` markers:
- steamclient symlink path + resolved real path + `file -L` output + missing `ldd -r` lines (or `none`)
- `addons/metamod.vdf` contents
- chosen metamod loader path + binary info + missing `ldd -r` lines (or `none`)
- listing of `addons/metamod/bin/linux64`

When startup is healthy, logs should show steamclient validation success and no MetaMod interface load errors such as `Could not get IServerPluginCallbacks interface from plugin ...`.

### In-container verification checklist
```console
$ docker exec tf2classified bash -lc '
set -e
MMVDF=/home/steam/tf2classified-dedicated/tf2classified/addons/metamod.vdf
MMBIN=$(awk -F'"' '/"file"/ {print $4}' "$MMVDF")
echo "metamod.vdf -> $MMBIN"
file "/home/steam/tf2classified-dedicated/tf2classified/$MMBIN"
ldd -r "/home/steam/tf2classified-dedicated/tf2classified/$MMBIN"
file /home/steam/.steam/sdk64/steamclient.so
ldd -r /home/steam/.steam/sdk64/steamclient.so
echo "SteamAppId=$SteamAppId SteamGameId=$SteamGameId"
for f in mb2_tf_content.vpk mb2_shared_content.vpk tf2c_overrides.vpk; do
  test -f "/home/steam/tf2classified-dedicated/tf2classified/vpks/$f" && echo "present: $f"
done
'
```
The `ldd -r` checks must not show `not found` or `undefined symbol`.

## Hosting a simple game server

Running on the *host* interface (recommended):<br/>
```console
$ docker run -d --net=host --name=tf2-dedicated -e SRCDS_TOKEN={YOURTOKEN} cm2network/tf2
```

Running using a bind mount for data persistence on container recreation:
```console
$ mkdir -p $(pwd)/tf2-data
$ chmod 777 $(pwd)/tf2-data # Makes sure the directory is writeable by the unprivileged container user
$ docker run -d --net=host -v $(pwd)/tf2-data:/home/steam/tf-dedicated/ --name=tf2-dedicated -e SRCDS_TOKEN={YOURTOKEN} cm2network/tf2
```

Running multiple instances (increment SRCDS_PORT and SRCDS_TV_PORT):
```console
$ docker run -d --net=host --name=tf2-dedicated2 -e SRCDS_PORT=27016 -e SRCDS_TV_PORT=27021 -e SRCDS_TOKEN={YOURTOKEN} cm2network/tf2
```

`SRCDS_TOKEN` **is required to be listed & reachable. Generate one here using AppID `440`:**  
[https://steamcommunity.com/dev/managegameservers](https://steamcommunity.com/dev/managegameservers)<br/><br/>
`SRCDS_WORKSHOP_AUTHKEY` **is required to use workshop features:**  
[https://steamcommunity.com/dev/apikey](https://steamcommunity.com/dev/apikey)<br/>

**It's also recommended to use "--cpuset-cpus=" to limit the game server to a specific core & thread.**<br/>
**The container will automatically update the game on startup, so if there is a game update just restart the container.**

### Using docker compose
Instead of using `docker run`, you can use `docker compose` as well, which removes the need for manually running long commands or scripts, especially useful if you want multiple servers.
An example docker-compose.yml is provided below.
```yaml
services:
  tf2:
    # Allocates a stdin (docker run -i)
    stdin_open: true
    # Allocates a tty (docker run -t)
    tty: true
    # Max CPUs to allocate, float, so e.g. 3.5 can be set.
    cpus: 4
    # Specific CPUs to allocate, 0-3 is first 4 CPUs, "0,1,2,3" can be used as well
    cpuset: 0-3
    # Use the host network, RECOMMENDED.
    network_mode: host
    # Binds /srv/tf2-dir to /home/steam/tf-dedicated in the container
    volumes:
      - /srv/tf2-dir:/home/steam/tf-dedicated
    container_name: tf2-dedicated
    environment:
      SRCDS_TOKEN: "0123456789DEADB33F"
      SRCDS_PW: "examplepassword"
      # Rest of your env vars...
    image: cm2network/tf2:latest
```
This will create a container called `tf2-dedicated`, with a bind mount for persistent data. This is especially recommended with compose, as `docker compose down` ***removes*** the defined containers.<br/>
For environment variables, you can also use an `.env` file.

# Configuration
## Environment Variables
Feel free to overwrite these environment variables, using -e (--env): 
```dockerfile
SRCDS_TOKEN="changeme" (value is is required to be listed & reachable, retrieve token here (AppID 440): https://steamcommunity.com/dev/managegameservers)
SRCDS_RCONPW="changeme" (value can be overwritten by tf/cfg/server.cfg) 
SRCDS_PW="changeme" (value can be overwritten by tf/cfg/server.cfg) 
SRCDS_PORT=27015
SRCDS_TV_PORT=27020
SRCDS_CLIENT_PORT=27005
SRCDS_IP="0" (local ip to bind)
SRCDS_FPSMAX=300
SRCDS_TICKRATE=66
SRCDS_MAXPLAYERS=14
SRCDS_REGION=3
SRCDS_STARTMAP="ctf_2fort"
SRCDS_HOSTNAME="New TF Server" (first launch only)
SRCDS_WORKSHOP_AUTHKEY="" (required to load workshop maps)
SRCDS_CFG="server.cfg"
SRCDS_MAPCYCLE="mapcycle_default.txt" (value can be overwritten by tf/cfg/server.cfg)
SRCDS_SECURED=1 (0 to start the server as insecured)
SRCDS_SDR_FAKEIP=0 (1 to allow for the Steam Datagram Relay, hiding the server's IP)
SRCDS_REPLAY=0 (1 to enable replay support)
SRCDS_DIAG=0 (set to 1 for structured startup diagnostics: appids, paths, steam libs, metamod loader checks)
STEAMAPP_VALIDATE=1 (x64 images; validate TF2C files on startup to repair corrupted/mismatched VPKs)
TF2_BASE_VALIDATE=1 (x64 images; validate TF2 base content on startup)
SRCDS_STEAM_APPID=3557020 (x64 images; Steam runtime AppID written to steam_appid.txt and exported as SteamAppId)
SRCDS_STEAM_GAMEID=3557020 (x64 images; SteamGameId used for game identity/telemetry)
SRCDS_WIPE_APP_ON_CORRUPTION=0 (set to 1 to wipe app dir and force full reinstall if SteamCMD reports VPK/content corruption)
STEAMCMD_LOCK_WAIT_SECONDS=900 (wait time for SteamCMD update lock to prevent concurrent updates)
```

### TF2 Classified token / networking notes
- `SRCDS_TOKEN` is required when `SRCDS_SECURED=1`; entrypoint will fail fast on placeholder values and only pass `+sv_setsteamaccount` when a usable token is present.
- Generate your GSLT for the expected game branch used by your deployment; keep `SRCDS_STEAM_APPID`/`SRCDS_STEAM_GAMEID` aligned with your server runtime unless you intentionally override for troubleshooting.
- `--net=host` is recommended on Linux for Source-engine servers. If you cannot use host mode, publish `27015/udp`, `27015/tcp`, `27020/udp`, and `27005/udp` explicitly.

## Config
The image contains static copies of the competitive config files from [UGC League](https://www.ugcleague.com/files_tf26.cfm#) and [RGL.gg](https://rgl.gg/Public/About/Configs.aspx?r=24). 

You can edit the config using this command:
```console
$ docker exec -it tf2-dedicated nano /home/steam/tf-dedicated/tf/cfg/server.cfg
```
Or if you want to explicitly specify a server config file, use the `SRCDS_CFG` environment variable.

If you want to learn more about configuring a TF2 server check this [documentation](https://wiki.teamfortress.com/wiki/Dedicated_server_configuration).

# Image Variants:
The `tf2` images come in three flavors, each designed for a specific use case, with a 64-bit version if needed.

## `tf2:latest`
This is the defacto image. If you are unsure about what your needs are, you probably want to use this one. It is a bare-minimum TF2 dedicated server containing no 3rd party plugins.<br/>

## `tf2:metamod`
This is a specialized image. It contains the plugin environment [Metamod:Source](https://www.sourcemm.net) which can be found in the addons directory. You can find additional plugins [here](https://www.sourcemm.net/plugins).

## `tf2:sourcemod`
This is another specialized image. It contains both [Metamod:Source](https://www.sourcemm.net) and the popular server plugin [SourceMod](https://www.sourcemod.net) which can be found in the addons directory. [SourceMod](https://www.sourcemod.net) supports a wide variety of additional plugins that can be found [here](https://www.sourcemod.net/plugins.php).

## `tf2:[variant]-x64`
A 64-bit version of all three variants, i.e. `latest-x64`, `metamod-x64`, and `sourcemod-x64`. This will run a fully 64-bit server, `srcds_linux64`, with a 64-bit version of Metamod or SourceMod.

The x64 Metamod/SourceMod variants download the `linux64` builds when available.
### Which to use?
If you require SourceMod and aren't fully sure whether your plugins work on 64-bit servers, it's better to use the normal 32-bit variant, `tf2:sourcemod`. If you want to run a server without any plugins, `tf2:latest-x64` is preferred.

# Contributors
[![Contributors Display](https://badges.pufler.dev/contributors/CM2Walki/tf2?size=50&padding=5&bots=false)](https://github.com/CM2Walki/tf2/graphs/contributors)
