#!/bin/bash

for file in /home/bjames/ted/*.torrent

do
if [ "$file" != "/home/bjames/ted/*.torrent" ]; then
echo [`date`] "$file" added to queue. >> /home/bjames/uberzach/toradd.log
transmission-remote -a "$file"
rm "$file"
sleep 1
fi
done

exit 0
