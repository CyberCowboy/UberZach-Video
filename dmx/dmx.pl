#!/usr/bin/python
import os
import sys
import array
import string
from ola.ClientWrapper import ClientWrapper

# ====================================
# Globals
# ====================================
wrapper = None
state = [ 0 ]
cmds = { 'value' : [ 0 ], 'ticks' : [ 0 ] }
sock = None

# ====================================
# Wrapper callback -- exit on errors
# ====================================
def DmxSent(state):
  # Stop on errors
  if not state.Succeeded():
    wrapper.Stop()

# ====================================
# Main calculation
# ====================================
def SendDMXFrame():
  # Re-schedule ourselves in interval ms (do this first to keep the timing consistent)
  wrapper.AddEvent(interval, SendDMXFrame)

  # Check for new commands
  global sock
  
  # Update values for each channel
  for i in range(len(cmds['value'])):
    if (cmds['value'][i] != state[i]):
      diff = cmds['value'][i] - state[i]
      delta = float(diff) / float(cmds['ticks'][i])
      state[i] += int(delta)
      cmd['ticks'][i] -= 1
  
  # Send all DMX channels
  data = array.array('B')
  for i in range(len(state)):
	data.append(state[i])
  wrapper.Client().SendDmx(universe, data, DmxSent)

# ====================================
# Main
# ====================================

# Pick a universe (0, or as specified in the environment)
universe = 0
if 'UNIVERSE' in os.environ:
  universe = int(os.environ['UNIVERSE'])

# Pick a tick interval (50ms, or as specified in the environment)
interval = 50
if 'INTERVAL' in os.environ:
  universe = int(os.environ['INTERVAL'])

# Pick a socket file ($TMPDIR/plexMonitor/DMX.socket, or as specified in the environment)
cmd_file = 'plexMonitor/DMX.socket'

# Open the socket

# Start the DMX loop
wrapper = ClientWrapper()
wrapper.AddEvent(interval, SendDMXFrame)
wrapper.Run()
