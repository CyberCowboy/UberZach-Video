#!/bin/bash

# Grab the input URLs
URLS="`cat -`"
# Move to the destination directory
DEST="${1}"
if [ -z "${DEST}" ]; then
        DEST=~/Desktop
fi
cd "${DEST}"
echo "${URLS}" | xargs -n1 transmission-remote -a
#transmission-remote -a "${URLS}"
