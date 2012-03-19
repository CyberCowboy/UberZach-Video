#!/bin/bash

# Command line
inFile="${1}"
outFile="${2}"
movLength="${3}"
if [ -z "${inFile}" ] || [ ! -e "${inFile}" ]; then
	echo "Usage: `basename "${0}"` input_file [output_file] [mov_length]" 1>&2
	exit 1
fi

# Exclude files with DTS soundtracks
ACODECS="`~/bin/video/movInfo.pl "${inFile}" | grep AUDIO_CODEC`"
if [ -z "${ACODECS}" ]; then
	echo "`basename "${0}"`: Could not determine audio codec" 1>&2
	exit 2
fi
if echo "${ACODECS}" | grep -q ffdca; then
	exit 1
fi

# Construct the output file name
if [ -z "${outFile}" ]; then
	# Use the input file name with a .mov extension
	outFile="`basename "${inFile}"`"
	outFile="`echo "${outFile}" | sed 's%\.[A-Za-z0-9]*$%%'`"
	outFile="`dirname "${inFile}"`/${outFile}"
fi

# Convert to MOV or MKV
tmpFile="`mktemp -t toMov`"
if which catmovie > /dev/null 2>&1; then
	catmovie -q -self-contained -o "${tmpFile}" "${inFile}" 2>/dev/null
	outfile="${outfile}.mov"
elif which mkvmerge > /dev/null 2>&1; then
	mkvmerge -o "${tmpFile}" "${inFile}"
	outfile="${outfile}.mkv"
fi

# Check for errors
if [ ! -e "${tmpFile}" ] || [ `stat -f '%z' "${tmpFile}"` -lt 1000 ]; then
	echo "`basename "${0}"`: Error creating output file for input: ${inFile}" 1>&2

	# Try to recode (with Handbrake/ffmpeg) if catmovie/mkvmerge fails
	echo "`basename "${0}"`: Attempting recode instead..." 1>&2
	~/bin/video/recode "${inFile}"
	exit "${?}"
fi

# Move into place, dropping the original
tmpOut="`mktemp "${outFile}.XXXXXXXX"`"
cp -X "${tmpFile}" "${tmpOut}" && rm "${inFile}" && mv "${tmpOut}" "${outFile}"
rm -f "${tmpFile}"

# Exit cleanly
exit 0
