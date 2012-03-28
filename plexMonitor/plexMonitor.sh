#!/bin/bash

# Config
EXEC_DIR="${HOME}/bin/video"
TEMP_DIR="`getconf DARWIN_USER_TEMP_DIR`"

# Compare the current state to the last one
compareState() {
	CHANGED=1
	"${EXEC_DIR}/${CMD}" > "${TEMP_FILE}" 2>/dev/null
	if [ -r "${MODE}" ]; then
		diff "${TEMP_FILE}" "${MODE}" > /dev/null
		if [ $? -eq 0 ]; then
			CHANGED=0
		fi
	fi

	# If anything changed, note the update time and store the current state for future reference
	if [ $CHANGED -gt 0 ]; then
		date '+%s' > "${MODE}.lastUpdate"
		mv "${TEMP_FILE}" "${MODE}"
	fi

	# Special case for PLAYING mode -- it's a bit of a hack, but it saves a lot of code other places
	if [ $CHANGED -gt 0 ] && [ "${MODE}" == "PLAYING" ]; then
		LAST_PLAYING=$PLAYING
		PLAYING=0
		if grep -q 'PlayStatus\:Playing' "${MODE}"; then
			PLAYING=1
		fi
		if [ -z "${LAST_PLAYING}" ] || [ $LAST_PLAYING -ne $PLAYING ]; then
			echo $PLAYING > "PLAY_STATUS"
			cp "${MODE}.lastUpdate" "PLAY_STATUS.lastUpdate"
		fi
	fi
}

# Sanity check
if [ ! -d "${EXEC_DIR}" ] || [ ! -d "${TEMP_DIR}" ]; then
	echo "Bad config" 1>&2
	exit 1
fi

# Allow use in daemon mode
LOOP_DELAY=0
if [ -n "${1}" ] && [ "${1}" -gt 0 ]; then
	LOOP_DELAY=$1
fi

# Determine who we are
MODE="PLAYING"
CMD="plex-playing"
if basename "${0}" | grep -qi GUI; then
	MODE="GUI"
	CMD="plex-gui"
fi

# Construct our runtime paths
DATA_DIR="${TEMP_DIR}/plexMonitor"
TEMP_FILE="`mktemp -t plexMonitor.XXXXXXXX`"

# Get into position
if [ ! -d "${DATA_DIR}" ]; then
	mkdir -p "${DATA_DIR}"
fi
cd "${DATA_DIR}"

# Compare
compareState

# Sleep and repeat (if requested)
if [ -n "${LOOP_DELAY}" ]; then
	while [ 1 ]; do
		sleep $LOOP_DELAY
		compareState
	done
fi

# Cleanup
rm -f "${TEMP_FILE}"
exit 0
