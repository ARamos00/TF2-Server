###########################################################
# Dockerfile that builds a TF2 Gameserver
###########################################################
FROM cm2network/steamcmd:root AS build_stage

LABEL maintainer="walentinlamonos@gmail.com"

ENV STEAMAPPID 3557020
ENV STEAMAPP tf2classified
ENV STEAMAPPDIR "${HOMEDIR}/${STEAMAPP}-dedicated"

COPY "etc/entry_x64.sh" "${HOMEDIR}/entry_x64.sh"
COPY "etc/cfg" "${STEAMAPPDIR}/${STEAMAPP}/cfg/"

RUN set -x \
	# Install, update & upgrade packages
	&& apt-get update \
	&& apt-get install -y --no-install-recommends --no-install-suggests \
		wget \
		ca-certificates \
		zlib1g \
		libncurses5 \
		libbz2-1.0 \
		libtinfo5 \
		libcurl3-gnutls \
	&& mkdir -p "${STEAMAPPDIR}" \
	# Create autoupdate config
	&& { \
		echo '@ShutdownOnFailedCommand 1'; \
		echo '@NoPromptForPassword 1'; \
		echo 'force_install_dir '"${STEAMAPPDIR}"''; \
		echo 'login anonymous'; \
		echo 'app_update '"${STEAMAPPID}"' validate'; \
		echo 'quit'; \
	   } > "${HOMEDIR}/${STEAMAPP}_update.txt" \
	&& chmod +x "${HOMEDIR}/entry_x64.sh" \
	&& chown -R "${USER}:${USER}" "${HOMEDIR}/entry_x64.sh" "${STEAMAPPDIR}" "${HOMEDIR}/${STEAMAPP}_update.txt" \
	# Clean up
	&& rm -rf /var/lib/apt/lists/*

FROM build_stage AS bookworm-base

ENV SRCDS_FPSMAX=300 \
	SRCDS_TICKRATE=66 \
	SRCDS_PORT=27015 \
	SRCDS_TV_PORT=27020 \
	SRCDS_CLIENT_PORT=27005 \
        SRCDS_NET_PUBLIC_ADDRESS="0" \
        SRCDS_IP="0" \
	SRCDS_MAXPLAYERS=16 \
	SRCDS_TOKEN=0 \
	SRCDS_RCONPW="changeme" \
	SRCDS_PW="changeme" \
	SRCDS_STARTMAP="ctf_2fort" \
	SRCDS_REGION=3 \
        SRCDS_HOSTNAME="New \"${STEAMAPP}\" Server" \
        SRCDS_WORKSHOP_START_MAP=0 \
        SRCDS_HOST_WORKSHOP_COLLECTION=0 \
        SRCDS_WORKSHOP_AUTHKEY="" \
	SRCDS_CFG="server.cfg" \
	SRCDS_MAPCYCLE="mapcycle.txt" \
	SRCDS_SECURED=1 \
	SRCDS_SDR_FAKEIP=0 \
	SRCDS_REPLAY=0

# Switch to user
USER ${USER}

WORKDIR ${HOMEDIR}

CMD ["bash", "entry_x64.sh"]

# Expose ports
EXPOSE 27015/tcp \
	27015/udp \
	27020/udp

FROM bookworm-base AS bookworm-metamod

ENV METAMOD_VERSION 1.12

FROM bookworm-metamod AS bookworm-sourcemod

ENV SOURCEMOD_VERSION 1.12
