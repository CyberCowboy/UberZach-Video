#!/bin/bash

# Command line
inFolder="${1}"
if [ -z "${inFolder}" ] || [ ! -e "${inFolder}" ]; then
	echo "Usage: `basename "${0}"` input_folder" 1>&2
	exit 1
fi

# Bail if we're already running a lot
me="`basename "${0}"`"
if [ `ps auwx | grep -v grep | grep "${me}" | wc -l` -gt 10 ]; then
	exit 0
fi

# Bail if the load average is high
LOAD="`uptime | awk -F ': ' '{print $2}' | cut -d '.' -f 1`"
CPU_COUNT="`sysctl -n hw.ncpu`"
if [ $LOAD -gt $(( 2 * $CPU_COUNT )) ]; then
	exit 0
fi

# Prefer recoding to rewrapping if the file is overrate
~/bin/video/findRecode0 "${inFolder}" | xargs -0 -n1 ~/bin/video/recode

# Move to the input folder
inFolder="`cd "${inFolder}" && pwd`"
cd "${inFolder}"

# Cycle through the folder looking for certain video files that should be converted to better containers
for i in *.[aA][vV][iI] *.[wW][mM][vV] *.[mM][kK][vV] *.[dD][iI][vV][xX] *.[fF][lL][vV]; do
	# Construct the full path
	file="${inFolder}/${i}"

	# Make sure the file is reasonable
	if [ ! -e "${file}" ]; then
		continue
	fi

	# Bail if WoW is running
	if ps auwx | grep -v grep | grep -q "World of Warcraft/World of Warcraft.app/Contents/MacOS/World of Warcraft"; then
		exit 0
	fi

	# Convert to M4V/MOV
	~/bin/video/toMov.sh "${file}"
done
