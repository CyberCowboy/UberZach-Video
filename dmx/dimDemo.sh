#!/bin/bash

# Defaults
DELAY=0
INTERVAL=4
MIN=0
MAX=255

# Allow ctrl-c to exit even when we're in setChannels.py
end() {
	EXIT=1
}
trap end SIGINT

# Bounce back and forth
UP=1
i=$MIN
EXIT=0
while [ $EXIT -lt 1 ]; do
	if [ $UP -gt 0 ]; then
		i=$(( $i + $INTERVAL ))
		if [ $i -ge $MAX ]; then
			UP=0
			i=$MAX
		fi
	else
		i=$(( $i - $INTERVAL ))
		if [ $i -le $MIN ]; then
			UP=1
			i=$MIN
		fi
	fi
	./setChannels.py $i
	if [ $DELAY ]; then
		sleep $DELAY
	fi
done
