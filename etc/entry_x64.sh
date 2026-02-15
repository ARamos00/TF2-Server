#!/bin/bash
mkdir -p "${STEAMAPPDIR}" || true

bash "${STEAMCMDDIR}/steamcmd.sh" +force_install_dir "${STEAMAPPDIR}" \
				+login anonymous \
				+app_update "${STEAMAPPID}" \
				+quit

# Are we in a metamod container and is the metamod folder missing?
if  [ ! -z "$METAMOD_VERSION" ] && [ ! -d "${STEAMAPPDIR}/${STEAMAPP}/addons/metamod" ]; then
        LATESTMM=$(wget -qO- https://mms.alliedmods.net/mmsdrop/"${METAMOD_VERSION}"/mmsource-latest-linux)
        wget -qO- https://mms.alliedmods.net/mmsdrop/"${METAMOD_VERSION}"/"${LATESTMM}" | tar xvzf - -C "${STEAMAPPDIR}/${STEAMAPP}"
fi

# Are we in a sourcemod container and is the sourcemod folder missing?
if  [ ! -z "$SOURCEMOD_VERSION" ] && [ ! -d "${STEAMAPPDIR}/${STEAMAPP}/addons/sourcemod" ]; then
        LATESTSM=$(wget -qO- https://sm.alliedmods.net/smdrop/"${SOURCEMOD_VERSION}"/sourcemod-latest-linux)
        wget -qO- https://sm.alliedmods.net/smdrop/"${SOURCEMOD_VERSION}"/"${LATESTSM}" | tar xvzf - -C "${STEAMAPPDIR}/${STEAMAPP}"
fi

# Is the config missing?
if [ -f "${STEAMAPPDIR}/${STEAMAPP}/cfg/server.cfg" ]; then
        # Change hostname on first launch (you can comment this out if it has done its purpose)
        sed -i -e 's/{{SERVER_HOSTNAME}}/'"${SRCDS_HOSTNAME}"'/g' "${STEAMAPPDIR}/${STEAMAPP}/cfg/server.cfg"
fi

# Believe it or not, if you don't do this srcds_run shits itself
cd "${STEAMAPPDIR}"

if [ ! -d "${STEAMAPPDIR}/${STEAMAPP}" ]; then
        DETECTED_GAMEINFO=$(find "${STEAMAPPDIR}" -maxdepth 4 -type f -name gameinfo.txt | head -n 1)
        if [ -n "${DETECTED_GAMEINFO}" ]; then
                STEAMAPP=$(basename "$(dirname "${DETECTED_GAMEINFO}")")
                echo "Detected game directory '${STEAMAPP}' from ${DETECTED_GAMEINFO}"
        fi
fi

SERVER_SECURITY_FLAG="";

if [ "$SRCDS_SECURED" -eq 0 ]; then
        SERVER_SECURITY_FLAG="-insecure";
fi

SERVER_FAKEIP_FLAG="";

if [ "$SRCDS_SDR_FAKEIP" -eq 1 ]; then
        SERVER_FAKEIP_FLAG="-enablefakeip";
fi

REPLAY_FLAG="";

if [ "$SRCDS_REPLAY" -eq 1 ]; then
        REPLAY_FLAG="-replay";
fi

SRCDS_BINARY="${STEAMAPPDIR}/srcds_run_64"
if [ ! -x "${SRCDS_BINARY}" ]; then
        SRCDS_BINARY="${STEAMAPPDIR}/srcds_run"
fi

if [ ! -x "${SRCDS_BINARY}" ]; then
        DETECTED_SRCDS_BINARY=$(find "${STEAMAPPDIR}" -maxdepth 4 -type f \( -name srcds_run_64 -o -name srcds_run \) | head -n 1)
        if [ -n "${DETECTED_SRCDS_BINARY}" ]; then
                SRCDS_BINARY="${DETECTED_SRCDS_BINARY}"
                echo "Detected Source dedicated server launcher at '${SRCDS_BINARY}'"
        else
                echo "Could not find srcds_run or srcds_run_64 under '${STEAMAPPDIR}'."
                echo "Contents of install directory:"
                find "${STEAMAPPDIR}" -maxdepth 2 -mindepth 1 -print
                exit 1
        fi
fi

cd "$(dirname "${SRCDS_BINARY}")"

bash "${SRCDS_BINARY}" -game "${STEAMAPP}" -console -autoupdate \
                        -steam_dir "${STEAMCMDDIR}" \
                        -steamcmd_script "${HOMEDIR}/${STEAMAPP}_update.txt" \
                        -usercon \
                        +fps_max "${SRCDS_FPSMAX}" \
                        -tickrate "${SRCDS_TICKRATE}" \
                        -port "${SRCDS_PORT}" \
                        +tv_port "${SRCDS_TV_PORT}" \
                        +clientport "${SRCDS_CLIENT_PORT}" \
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
