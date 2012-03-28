#!/usr/bin/python
import sys
import array
from ola.ClientWrapper import ClientWrapper

def DmxSent(state):
  wrapper.Stop()

universe = 0
data = array.array('B')
for i in range(1, len(sys.argv)):
   data.append(int(sys.argv[i]))
wrapper = ClientWrapper()
client = wrapper.Client()
client.SendDmx(universe, data, DmxSent)
wrapper.Run()
