#!/usr/bin/python
import os
import sys
import array
import socket
import string
import subprocess
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
cmd_file = None
data_dir = None
if 'SOCKET' in os.environ:
  cmd_file = os.environ['SOCKET']
  data_dir = os.dirname(cmd_file)
else:
  proc = subprocess.Popen(['getconf', 'DARWIN_USER_TEMP_DIR'], stdout=subprocess.PIPE, shell=False)
  (tmp_dir, err) = proc.communicate()
  tmp_dir = tmp_dir.strip()
  data_dir = tmp_dir + 'plexMonitor/'
  cmd_file = data_dir + 'DMX.socket'

# Sanity checks
if (not os.path.isdir(data_dir)):
  raise Exception('Bad config: ' + data_dir)

# Open the socket
if (os.path.exists(cmd_file)):
  os.unlink(cmd_file)
sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
sock.bind(cmd_file)

# Start the DMX loop
wrapper = ClientWrapper()
wrapper.AddEvent(interval, SendDMXFrame)
wrapper.Run()
