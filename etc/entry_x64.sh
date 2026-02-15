#!/bin/bash
set -euo pipefail

log() {
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

find_metamod_linux64_binary() {
        local mm_root="$1"
        local candidate

        for candidate in \
                "${mm_root}/bin/linux64/server.so" \
                "${mm_root}/bin/linux64/server"; do
                if [ -f "${candidate}" ]; then
                        echo "${candidate}"
                        return 0
                fi
        done

        return 1
}

mkdir -p "${STEAMAPPDIR}" || true
mkdir -p "${TF2_BASE_DIR:-${HOMEDIR}/tf2-dedicated}" || true

APP_VALIDATE_ARGS=("${STEAMAPPID}")
if [ "${STEAMAPP_VALIDATE:-1}" -eq 1 ]; then
        APP_VALIDATE_ARGS+=(validate)
fi

TF2_BASE_VALIDATE_ARGS=("${TF2_BASE_APPID:-232250}")
if [ "${TF2_BASE_VALIDATE:-1}" -eq 1 ]; then
        TF2_BASE_VALIDATE_ARGS+=(validate)
fi

log "Updating primary app ${STEAMAPPID} into ${STEAMAPPDIR} (gamedir ${STEAMAPP})."
bash "${STEAMCMDDIR}/steamcmd.sh" +force_install_dir "${STEAMAPPDIR}" \
                                +login anonymous \
                                +app_update "${APP_VALIDATE_ARGS[@]}" \
                                +quit

log "Updating TF2 base content app ${TF2_BASE_APPID:-232250} into ${TF2_BASE_DIR:-${HOMEDIR}/tf2-dedicated} for -tf_path."
bash "${STEAMCMDDIR}/steamcmd.sh" +force_install_dir "${TF2_BASE_DIR:-${HOMEDIR}/tf2-dedicated}" \
                                +login anonymous \
                                +app_update "${TF2_BASE_VALIDATE_ARGS[@]}" \
                                +quit

# Are we in a metamod container and is the metamod folder missing?
if [ -n "${METAMOD_VERSION:-}" ] && [ ! -d "${STEAMAPPDIR}/${STEAMAPP}/addons/metamod" ]; then
        log "Installing Metamod ${METAMOD_VERSION} (linux64 preferred)."
        LATESTMM=""
        if LATESTMM=$(wget -qO- "https://mms.alliedmods.net/mmsdrop/${METAMOD_VERSION}/mmsource-latest-linux64") && [ -n "${LATESTMM}" ]; then
                log "Using Metamod linux64 drop ${LATESTMM}"
        else
                log "WARNING: linux64 Metamod drop lookup failed for ${METAMOD_VERSION}; falling back to linux drop"
                LATESTMM=$(wget -qO- "https://mms.alliedmods.net/mmsdrop/${METAMOD_VERSION}/mmsource-latest-linux")
                log "Using fallback Metamod drop ${LATESTMM}"
        fi
        wget -qO- "https://mms.alliedmods.net/mmsdrop/${METAMOD_VERSION}/${LATESTMM}" | tar xvzf - -C "${STEAMAPPDIR}/${STEAMAPP}"

        MM_ROOT="${STEAMAPPDIR}/${STEAMAPP}/addons/metamod"
        MM64_BIN="$(find_metamod_linux64_binary "${MM_ROOT}" || true)"
        if [ -z "${MM64_BIN}" ]; then
                log "ERROR: Metamod install did not include a linux64 binary."
                log "Checked: ${MM_ROOT}/bin/linux64/server.so, ${MM_ROOT}/bin/linux64/server"
                if [ -d "${MM_ROOT}/bin" ]; then
                        log "Metamod bin tree:"
                        find "${MM_ROOT}/bin" -maxdepth 3 -type f -print
                fi
                exit 1
        fi
fi

# Ensure metamod.vdf points at the x64 binary when available.
if [ -d "${STEAMAPPDIR}/${STEAMAPP}/addons/metamod" ]; then
        MM_ROOT="${STEAMAPPDIR}/${STEAMAPP}/addons/metamod"
        MM64_BIN="$(find_metamod_linux64_binary "${MM_ROOT}" || true)"
        MM32_BIN="${MM_ROOT}/bin/server.so"
        MM_VDF="${STEAMAPPDIR}/${STEAMAPP}/addons/metamod.vdf"
        if [ -n "${MM64_BIN}" ]; then
                cat > "${MM_VDF}" <<'VDF'
"Plugin"
{
        "file"  "addons/metamod/bin/linux64/server"
}
VDF
                log "Configured ${MM_VDF} to use addons/metamod/bin/linux64/server"
                log "Metamod binary info: $(file "${MM64_BIN}")"
                if file "${MM64_BIN}" | grep -q 'ELF 32-bit'; then
                        log "ERROR: ${MM64_BIN} is 32-bit; refusing to start x64 server."
                        exit 1
                fi
        elif [ -f "${MM32_BIN}" ]; then
                log "ERROR: only 32-bit Metamod binary found at addons/metamod/bin/server.so"
                log "Binary info: $(file "${MM32_BIN}")"
                log "Checked linux64 candidates: ${MM_ROOT}/bin/linux64/server.so, ${MM_ROOT}/bin/linux64/server (missing or not regular files)"
                exit 1
        else
                log "WARNING: Metamod directory exists but no loader binary was found."
                log "Checked linux64 candidates: ${MM_ROOT}/bin/linux64/server.so, ${MM_ROOT}/bin/linux64/server"
        fi
fi

# Are we in a sourcemod container and is the sourcemod folder missing?
if [ -n "${SOURCEMOD_VERSION:-}" ] && [ ! -d "${STEAMAPPDIR}/${STEAMAPP}/addons/sourcemod" ]; then
        log "Installing SourceMod ${SOURCEMOD_VERSION} (linux64 preferred)."
        LATESTSM=$(wget -qO- "https://sm.alliedmods.net/smdrop/${SOURCEMOD_VERSION}/sourcemod-latest-linux64" \
                || wget -qO- "https://sm.alliedmods.net/smdrop/${SOURCEMOD_VERSION}/sourcemod-latest-linux")
        wget -qO- "https://sm.alliedmods.net/smdrop/${SOURCEMOD_VERSION}/${LATESTSM}" | tar xvzf - -C "${STEAMAPPDIR}/${STEAMAPP}"
fi

if [ -d "${STEAMAPPDIR}/${STEAMAPP}/addons/sourcemod" ]; then
        log "SourceMod detected at ${STEAMAPPDIR}/${STEAMAPP}/addons/sourcemod"
fi

# Is the config missing?
if [ -f "${STEAMAPPDIR}/${STEAMAPP}/cfg/server.cfg" ]; then
        sed -i -e 's/{{SERVER_HOSTNAME}}/'"${SRCDS_HOSTNAME}"'/g' "${STEAMAPPDIR}/${STEAMAPP}/cfg/server.cfg"
fi

cd "${STEAMAPPDIR}"

if [ ! -d "${STEAMAPPDIR}/${STEAMAPP}" ]; then
        DETECTED_GAMEINFO=$(find "${STEAMAPPDIR}" -maxdepth 4 -type f -name gameinfo.txt | head -n 1)
        if [ -n "${DETECTED_GAMEINFO}" ]; then
                STEAMAPP=$(basename "$(dirname "${DETECTED_GAMEINFO}")")
                log "Detected game directory '${STEAMAPP}' from ${DETECTED_GAMEINFO}"
        fi
fi

SERVER_SECURITY_FLAG=""
if [ "${SRCDS_SECURED:-1}" -eq 0 ]; then
        SERVER_SECURITY_FLAG="-insecure"
fi

SERVER_FAKEIP_FLAG=""
if [ "${SRCDS_SDR_FAKEIP:-0}" -eq 1 ]; then
        SERVER_FAKEIP_FLAG="-enablefakeip"
fi

REPLAY_FLAG=""
if [ "${SRCDS_REPLAY:-0}" -eq 1 ]; then
        REPLAY_FLAG="-replay"
fi

SRCDS_BINARY=""
for CANDIDATE in \
        "${STEAMAPPDIR}/srcds_run_64" \
        "${STEAMAPPDIR}/srcds_run" \
        "${STEAMAPPDIR}/srcds.sh" \
        "${STEAMAPPDIR}/srcds_linux64"; do
        if [ -x "${CANDIDATE}" ]; then
                SRCDS_BINARY="${CANDIDATE}"
                break
        fi
done

if [ -z "${SRCDS_BINARY}" ]; then
        DETECTED_SRCDS_BINARY=$(find "${STEAMAPPDIR}" -maxdepth 4 -type f \( -name srcds_run_64 -o -name srcds_run -o -name srcds.sh -o -name srcds_linux64 \) | head -n 1)
        if [ -n "${DETECTED_SRCDS_BINARY}" ]; then
                SRCDS_BINARY="${DETECTED_SRCDS_BINARY}"
                log "Detected Source dedicated server launcher at '${SRCDS_BINARY}'"
        else
                log "Could not find srcds_run_64, srcds_run, srcds.sh, or srcds_linux64 under '${STEAMAPPDIR}'."
                find "${STEAMAPPDIR}" -maxdepth 2 -mindepth 1 -print
                exit 1
        fi
fi

log "Using Source dedicated server launcher '${SRCDS_BINARY}'"
log "Runtime settings: game=${STEAMAPP} tf_path=${SRCDS_TF_PATH:-${TF2_BASE_DIR:-${HOMEDIR}/tf2-dedicated}} ip=${SRCDS_IP} port=${SRCDS_PORT} tv_port=${SRCDS_TV_PORT} client_port=${SRCDS_CLIENT_PORT:-27005}"
log "Local host connect hint: connect 127.0.0.1:${SRCDS_PORT}"

cd "$(dirname "${SRCDS_BINARY}")"

exec "${SRCDS_BINARY}" -game "${STEAMAPP}" -console -autoupdate \
                        -steam_dir "${STEAMCMDDIR}" \
                        -steamcmd_script "${HOMEDIR}/${STEAMAPP}_update.txt" \
                        -tf_path "${SRCDS_TF_PATH:-${TF2_BASE_DIR:-${HOMEDIR}/tf2-dedicated}}" \
                        -usercon \
                        +fps_max "${SRCDS_FPSMAX}" \
                        -tickrate "${SRCDS_TICKRATE}" \
                        -port "${SRCDS_PORT}" \
                        +tv_port "${SRCDS_TV_PORT}" \
                        +clientport "${SRCDS_CLIENT_PORT:-27005}" \
                        +maxplayers "${SRCDS_MAXPLAYERS}" \
                        +map "${SRCDS_STARTMAP}" \
                        +sv_setsteamaccount "${SRCDS_TOKEN}" \
                        +rcon_password "${SRCDS_RCONPW}" \
                        +sv_password "${SRCDS_PW}" \
                        +sv_region "${SRCDS_REGION}" \
                        -ip "${SRCDS_IP}" \
                        -authkey "${SRCDS_WORKSHOP_AUTHKEY}" \
                        +servercfgfile "${SRCDS_CFG}" \
                        +mapcyclefile "${SRCDS_MAPCYCLE}" \
                        ${SERVER_SECURITY_FLAG} \
                        ${SERVER_FAKEIP_FLAG} \
                        ${REPLAY_FLAG}
