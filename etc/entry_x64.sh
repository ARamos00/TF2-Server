#!/bin/bash
set -euo pipefail

log() {
        echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

fatal() {
        log "ERROR: $*"
        exit 1
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

require_command() {
        local cmd="$1"
        command -v "${cmd}" >/dev/null 2>&1 || fatal "Required command '${cmd}' is missing from the container image."
}

run_ldd_check() {
        local target="$1"
        local label="$2"
        local ldd_output=""

        if [ ! -f "${target}" ]; then
                fatal "${label} missing at '${target}'."
        fi

        ldd_output="$(ldd -r "${target}" 2>&1 || true)"
        echo "${ldd_output}" | sed 's/^/[ldd] /'

        if echo "${ldd_output}" | grep -Eq 'not found|undefined symbol'; then
                fatal "${label} failed dependency resolution (ldd -r)."
        fi
}

binary_contains_token() {
        local target="$1"
        local token="$2"

        if grep -aFq "${token}" "${target}"; then
                return 0
        fi

        return 1
}

choose_metamod_loader_target() {
        local mm_root="$1"
        local game_dir="$2"
        local candidate
        local relative
        local selected=""

        for candidate in \
                "${mm_root}/bin/linux64/server" \
                "${mm_root}/bin/linux64/server.so"; do
                if [ ! -f "${candidate}" ]; then
                        continue
                fi

                if ! file "${candidate}" | grep -q 'ELF 64-bit'; then
                        log "Skipping Metamod loader candidate (not ELF 64-bit): ${candidate}"
                        continue
                fi

                if binary_contains_token "${candidate}" "IServerPluginCallbacks"; then
                        selected="${candidate}"
                        break
                fi
        done

        if [ -z "${selected}" ]; then
                selected="$(find_metamod_linux64_binary "${mm_root}" || true)"
        fi

        if [ -z "${selected}" ]; then
                return 1
        fi

        relative="${selected#"${game_dir}/"}"
        if [ "${relative}" = "${selected}" ]; then
                fatal "Metamod binary '${selected}' is not under game dir '${game_dir}'."
        fi

        echo "${relative}"
}

steamcmd_app_update_with_retry() {
        local install_dir="$1"
        local appid="$2"
        local validate_mode="$3"
        local label="$4"
        local max_attempts="${5:-3}"
        local attempt=1
        local args=(+force_install_dir "${install_dir}" +login anonymous +app_update "${appid}")
        local log_file

        if [ "${validate_mode}" -eq 1 ]; then
                args+=(validate)
        fi
        args+=(+quit)

        while [ "${attempt}" -le "${max_attempts}" ]; do
                log_file="$(mktemp)"
                log "SteamCMD ${label}: attempt ${attempt}/${max_attempts} (appid=${appid}, validate=${validate_mode}, dir=${install_dir})"

                set +e
                bash "${STEAMCMDDIR}/steamcmd.sh" "${args[@]}" | tee "${log_file}"
                local steamcmd_rc=${PIPESTATUS[0]}
                set -e

                if [ "${steamcmd_rc}" -eq 0 ] \
                        && ! grep -Fq 'Timed out waiting for update to start' "${log_file}" \
                        && grep -Fq 'Success! App' "${log_file}"; then
                        rm -f "${log_file}"
                        return 0
                fi

                log "SteamCMD ${label} failed health checks (rc=${steamcmd_rc}); retrying."
                if grep -Fq 'Timed out waiting for update to start' "${log_file}"; then
                        log "SteamCMD ${label} reported timeout waiting for update start."
                fi
                if ! grep -Fq 'Success! App' "${log_file}"; then
                        log "SteamCMD ${label} did not emit a success marker."
                fi

                rm -f "${log_file}"
                attempt=$((attempt + 1))
        done

        fatal "SteamCMD ${label} failed after ${max_attempts} attempts."
}

ensure_writable_dir() {
        local dir="$1"
        mkdir -p "${dir}"
        if [ ! -w "${dir}" ]; then
                fatal "Directory '${dir}' is not writable."
        fi
}

ensure_steamclient_sdk64() {
        local sdk64_dir="${HOMEDIR}/.steam/sdk64"
        local target="${sdk64_dir}/steamclient.so"
        local source=""

        mkdir -p "${sdk64_dir}"

        for candidate in \
                "${STEAMCMDDIR}/linux64/steamclient.so" \
                "${HOMEDIR}/.steam/steamcmd/linux64/steamclient.so" \
                "${HOMEDIR}/.local/share/Steam/steamcmd/linux64/steamclient.so"; do
                if [ -f "${candidate}" ]; then
                        source="${candidate}"
                        break
                fi
        done

        if [ -z "${source}" ]; then
                fatal "Unable to find a steamclient.so source from steamcmd runtime."
        fi

        if [ ! -f "${target}" ] || ! cmp -s "${source}" "${target}"; then
                cp -f "${source}" "${target}"
                log "Installed steamclient runtime: ${source} -> ${target}"
        fi

        mkdir -p "${HOMEDIR}/.steam/steamcmd/linux64"
        cp -f "${source}" "${HOMEDIR}/.steam/steamcmd/linux64/steamclient.so"

        if ! file "${target}" | grep -q 'ELF 64-bit'; then
                fatal "${target} is not an ELF 64-bit shared library: $(file "${target}")"
        fi

        run_ldd_check "${target}" "steamclient.so"
}

repair_vpks_if_requested() {
        if [ "${SRCDS_REPAIR_VPKS:-0}" -ne 1 ]; then
                return
        fi

        local vpk_dir="${STEAMAPPDIR}/${STEAMAPP}/vpks"
        local repaired=0
        local file_name

        if [ ! -d "${vpk_dir}" ]; then
                log "VPK repair requested, but '${vpk_dir}' does not exist yet. Skipping delete phase."
        else
                for file_name in mb2_tf_content.vpk mb2_shared_content.vpk tf2c_overrides.vpk; do
                        if [ -f "${vpk_dir}/${file_name}" ]; then
                                rm -f "${vpk_dir}/${file_name}"
                                repaired=1
                                log "Removed VPK for repair: ${vpk_dir}/${file_name}"
                        fi
                done
        fi

        if [ "${repaired}" -eq 0 ]; then
                log "VPK repair requested; no targeted VPK files were removed. Continuing with validate anyway."
        fi

        log "Re-validating TF2 Classified DS (${CLASSIFIED_APPID}) after VPK repair request."
        steamcmd_app_update_with_retry "${STEAMAPPDIR}" "${CLASSIFIED_APPID}" 1 "TF2 Classified DS validate"

        log "Re-validating TF2 base (${TF2_BASE_APPID:-232250}) after VPK repair request."
        steamcmd_app_update_with_retry "${TF2_BASE_DIR:-${HOMEDIR}/tf2-dedicated}" "${TF2_BASE_APPID:-232250}" 1 "TF2 base validate"

        for file_name in mb2_tf_content.vpk mb2_shared_content.vpk tf2c_overrides.vpk; do
                if [ -f "${vpk_dir}/${file_name}" ]; then
                        log "VPK repair verified replacement: ${vpk_dir}/${file_name}"
                else
                        fatal "VPK repair validate did not restore expected file: ${vpk_dir}/${file_name}"
                fi
        done
}

mkdir -p "${STEAMAPPDIR}" || true
mkdir -p "${TF2_BASE_DIR:-${HOMEDIR}/tf2-dedicated}" || true
ensure_writable_dir /tmp
ensure_writable_dir "${HOMEDIR}/.steam"

CLASSIFIED_APPID="${STEAMAPPID:-3557020}"
TF2_BASE_APPID_VALUE="${TF2_BASE_APPID:-232250}"

log "Updating TF2 Classified DS (${CLASSIFIED_APPID}) into ${STEAMAPPDIR} (gamedir ${STEAMAPP})."
steamcmd_app_update_with_retry "${STEAMAPPDIR}" "${CLASSIFIED_APPID}" "${STEAMAPP_VALIDATE:-1}" "TF2 Classified DS update"

log "Updating TF2 base (${TF2_BASE_APPID_VALUE}) into ${TF2_BASE_DIR:-${HOMEDIR}/tf2-dedicated} for -tf_path."
steamcmd_app_update_with_retry "${TF2_BASE_DIR:-${HOMEDIR}/tf2-dedicated}" "${TF2_BASE_APPID_VALUE}" "${TF2_BASE_VALIDATE:-1}" "TF2 base update"

repair_vpks_if_requested

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
        MM64_TARGET="$(choose_metamod_loader_target "${MM_ROOT}" "${STEAMAPPDIR}/${STEAMAPP}" || true)"
        if [ -z "${MM64_TARGET}" ]; then
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
        MM64_TARGET="$(choose_metamod_loader_target "${MM_ROOT}" "${STEAMAPPDIR}/${STEAMAPP}" || true)"
        MM32_BIN="${MM_ROOT}/bin/server.so"
        MM_VDF="${STEAMAPPDIR}/${STEAMAPP}/addons/metamod.vdf"
        if [ -n "${MM64_TARGET}" ]; then
                cat > "${MM_VDF}" <<VDF
"Plugin"
{
        "file"  "${MM64_TARGET}"
}
VDF
                MM64_BIN="${STEAMAPPDIR}/${STEAMAPP}/${MM64_TARGET}"
                log "Configured ${MM_VDF} to use ${MM64_TARGET}"
                MM64_FILE_INFO="$(file "${MM64_BIN}")"
                log "Metamod binary info: ${MM64_FILE_INFO}"
                if ! echo "${MM64_FILE_INFO}" | grep -q 'ELF 64-bit'; then
                        fatal "${MM64_BIN} is not 64-bit; refusing to start x64 server."
                fi
                if ! echo "${MM64_FILE_INFO}" | grep -q 'shared object'; then
                        fatal "${MM64_BIN} is not a shared object; refusing to start."
                fi
                if binary_contains_token "${MM64_BIN}" "IServerPluginCallbacks"; then
                        log "Metamod loader '${MM64_TARGET}' contains IServerPluginCallbacks marker."
                else
                        log "WARNING: IServerPluginCallbacks marker not found in '${MM64_TARGET}'."
                fi
                run_ldd_check "${MM64_BIN}" "Metamod loader ${MM64_TARGET}"
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

require_command file
require_command ldd

ensure_steamclient_sdk64
export SteamAppId="${CLASSIFIED_APPID}"
export SteamGameId="${CLASSIFIED_APPID}"
printf '%s\n' "${CLASSIFIED_APPID}" > "${STEAMAPPDIR}/steam_appid.txt"
printf '%s\n' "${CLASSIFIED_APPID}" > "${STEAMAPPDIR}/${STEAMAPP}/steam_appid.txt"
printf '%s\n' "${CLASSIFIED_APPID}" > "$(pwd)/steam_appid.txt"
log "Steam runtime check: $(file "${HOMEDIR}/.steam/sdk64/steamclient.so")"
run_ldd_check "${HOMEDIR}/.steam/sdk64/steamclient.so" "steamclient runtime"
if [ ! -s "${STEAMAPPDIR}/${STEAMAPP}/steam_appid.txt" ]; then
        fatal "Missing steam_appid.txt in game directory ${STEAMAPPDIR}/${STEAMAPP}."
fi
export LD_LIBRARY_PATH="${HOMEDIR}/.steam/sdk64:${STEAMCMDDIR}/linux64:${LD_LIBRARY_PATH:-}"
log "Set SteamAppId=${SteamAppId}, SteamGameId=${SteamGameId}, LD_LIBRARY_PATH=${LD_LIBRARY_PATH}"
log "Wrote steam_appid.txt in ${STEAMAPPDIR}, ${STEAMAPPDIR}/${STEAMAPP}, and $(pwd)."

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
