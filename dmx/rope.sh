#!/bin/bash

# Config
DIM_OFF=0
DIM_OFF_TIME=10000
DIM_PLAY=64
DIM_PLAY_TIME=250
DIM_PAUSE=192
DIM_PAUSE_TIME=1000
OFF_TIMEOUT=600
DELAY=0.5

# App Config
TEMP_DIR="`getconf DARWIN_USER_TEMP_DIR`"
EXEC_DIR="${HOME}/bin/video/dmx"
export PYTHONPATH="${PYTHONPATH}:/opt/local/lib/python2.7/site-packages:/opt/local/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/site-packages"

cleanup() {
	exit 0
}
trap cleanup SIGINT

checkForUpdates() {
	UPDATE=0
	if [ -r "${1}" ]; then
		UPDATE="`cat "${1}"`"
	fi
	if [ -z "${UPDATE}" ]; then
		UPDATE=0
	fi
	UPDATE=$(( $UPDATE + 0 ))
	echo $UPDATE
}

# Sanity check
if [ ! -d "${EXEC_DIR}" ] || [ ! -d "${TEMP_DIR}" ]; then
	echo "Bad config" 1>&2
	exit 1
fi

# Move into position
cd "${TEMP_DIR}/plexMonitor"

# State
STATE="PLAYING"
DIM_LAST=$DIM_PLAY
PLAYING=0
LAST_UPDATE=0
LAST_PLAYING=0

# Loop forever
while [ 1 ]; do
	# Reset
	CHANGED=0

	# Monitor the playing file for changes
	UPDATE=$(checkForUpdates PLAY_STATUS.lastUpdate)
	if [ $UPDATE -gt $LAST_UPDATE ]; then
		LAST_UPDATE=$UPDATE
		CHANGED=1
	fi

	# Grab the new play state
	LAST_PLAYING=$PLAYING
	if [ $CHANGED -gt 0 ]; then
		PLAYING="`cat PLAY_STATUS`"
		PLAYING=$(( $PLAYING + 0 ))
	fi

	# Turn off when we reach the timeout
	if [ $PLAYING -lt 1 ] && [ "${STATE}" != "OFF" ] && [ $(( LAST_UPDATE + $OFF_TIMEOUT )) -lt `date '+%s'` ]; then
		STATE="OFF"
		"${EXEC_DIR}/dimChannels.py" $DIM_OFF_TIME $DIM_LAST $DIM_OFF
		DIM_LAST=$DIM_OFF

	# If something has changed, check the actual play state
	elif [ $PLAYING -ne $LAST_PLAYING ]; then
		if [ $PLAYING -gt 0 ]; then
			STATE="PLAYING"
			"${EXEC_DIR}/dimChannels.py" $DIM_PLAY_TIME $DIM_LAST $DIM_PLAY
			DIM_LAST=$DIM_PLAY
		else
			STATE="PAUSED"
			"${EXEC_DIR}/dimChannels.py" $DIM_PAUSE_TIME $DIM_LAST $DIM_PAUSE
			DIM_LAST=$DIM_PAUSE
		fi
	fi

	# Delay
	sleep $DELAY
done
