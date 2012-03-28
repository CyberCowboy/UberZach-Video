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
TEMP_DIR="`getconf DARWIN_USER_TEMP_DIR`/plexMonitor"
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
cd "${TEMP_DIR}"

# State
STATE="OFF"
LAST_STATE="OFF"
DIM_LAST=$DIM_PLAY
PLAYING=0
LAST_UPDATE=0
LAST_PLAYING=0

# Always force lights out at launch
"${EXEC_DIR}/setChannels.py" 0

# Loop forever
while [ 1 ]; do
	# Monitor the PLAY_STATUS file for changes and state
	LAST_PLAYING=$PLAYING
	UPDATE=$(checkForUpdates PLAY_STATUS.lastUpdate)
	if [ $UPDATE -gt $LAST_UPDATE ]; then
		LAST_UPDATE=$UPDATE
		PLAYING="`cat PLAY_STATUS`"
		PLAYING=$(( $PLAYING + 0 ))
	fi

	# Monitor the GUI file for changes only
	UPDATE=$(checkForUpdates GUI.lastUpdate)
	if [ $UPDATE -gt $LAST_UPDATE ]; then
		LAST_UPDATE=$UPDATE
	fi
	UPDATE=$(checkForUpdates PLAYING.lastUpdate)
	if [ $UPDATE -gt $LAST_UPDATE ]; then
		LAST_UPDATE=$UPDATE
	fi

	# Detect when we change states
	LAST_STATE=$STATE

	# If the play state has changed we must adjust
	if [ $PLAYING -ne $LAST_PLAYING ]; then
		if [ $PLAYING -gt 0 ]; then
			STATE="PLAYING"
		else
			STATE="PAUSED"
		fi

	# If we're not playing, check for timeouts
	elif [ $PLAYING -lt 1 ]; then
		TIME_SINCE_CHANGE=$(( `date '+%s'` - $LAST_UPDATE ))

		# Turn off when we reach the timeout
		if [ "${STATE}" != "OFF" ] && [ $TIME_SINCE_CHANGE -gt $OFF_TIMEOUT ]; then
			STATE="OFF"
		# But fire back up if anything changes
		elif [ "${STATE}" == "OFF" ] && [ $TIME_SINCE_CHANGE -lt $OFF_TIMEOUT ]; then
			STATE="PAUSED"
		fi
	fi


	# Set the lighting state
	if [ "${STATE}" != "${LAST_STATE}" ]; then
		if [ "${STATE}" == "PAUSED" ]; then
			"${EXEC_DIR}/dimChannels.py" $DIM_PAUSE_TIME $DIM_LAST $DIM_PAUSE
			DIM_LAST=$DIM_PAUSE
		elif [ "${STATE}" == "PLAYING" ]; then
			"${EXEC_DIR}/dimChannels.py" $DIM_PLAY_TIME $DIM_LAST $DIM_PLAY
			DIM_LAST=$DIM_PLAY
		else
			"${EXEC_DIR}/dimChannels.py" $DIM_OFF_TIME $DIM_LAST $DIM_OFF
			DIM_LAST=$DIM_OFF
		fi

		# Save the state to disk for external reference
		echo -e "State: ${STATE}\nValue: ${DIM_LAST}" > ROPE
		date '+%s' > ROPE.lastUpdate
	fi

	# Delay
	sleep $DELAY
done
