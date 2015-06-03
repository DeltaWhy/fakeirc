#!/usr/bin/env python2
from __future__ import print_function
import Skype4Py
import os
import sys
import subprocess
import signal

FAKEIRC = os.path.join(os.path.dirname(__file__), '..', 'fakeirc.rb')
def fakeirc(*args):
    cmd = [FAKEIRC]
    cmd += args
    subprocess.call(cmd)

if len(sys.argv) != 5:
    print(os.path.basename(__file__)+" <chatname> <provider> <channel> <suffix>")
    sys.exit(0)
CHATNAME = sys.argv[1]
PROVIDER = sys.argv[2]
CHANNEL = sys.argv[3]
SUFFIX = sys.argv[4]

skype = Skype4Py.Skype()
skype.Attach()
my_nick = skype.CurrentUser.Handle
chat = skype.Chat(CHATNAME)

members = []
online_members = []
for m in chat.Members:
    #if m == skype.CurrentUser:
        #continue
    members.append(m.Handle)
    if m.OnlineStatus == "INVISIBLE" or m.OnlineStatus == "OFFLINE":
        continue
    online_members.append(m.Handle)
    fakeirc("add", m.Handle+"["+SUFFIX+"]", PROVIDER)
    if m.OnlineStatus == "AWAY" or m.OnlineStatus == "DND":
        fakeirc("away", m.Handle+"["+SUFFIX+"]")
    fakeirc("join", m.Handle+"["+SUFFIX+"]", CHANNEL)

def cleanup():
    for m in members:
        fakeirc("remove", m+"["+SUFFIX+"]")

def on_interrupt(signo, stackframe):
    cleanup()
    sys.exit(0)

def on_message_status(message, status):
    if message.Chat == chat:
        if status == "RECEIVED":
            if message.Type == "SAID":
                fakeirc("message", message.Sender.Handle+"["+SUFFIX+"]", CHANNEL, message.Body)
            elif message.Type == "EMOTED":
                fakeirc("action", message.Sender.Handle+"["+SUFFIX+"]", CHANNEL, message.Body)
        else:
            print(message, status)

def on_online_status(user, status):
    if user.Handle in online_members:
        if status == "INVISIBLE" or status == "OFFLINE":
            fakeirc("remove", user.Handle+"["+SUFFIX+"]")
            online_members.remove(user.Handle)
        elif status == "AWAY" or status == "DND":
            fakeirc("away", user.Handle+"["+SUFFIX+"]")
        elif status == "ONLINE":
            fakeirc("unaway", user.Handle+"["+SUFFIX+"]")
    elif user.Handle in members:
        if status != "INVISIBLE" and status != "OFFLINE":
            online_members.append(user.Handle)
            fakeirc("add", user.Handle+"["+SUFFIX+"]", PROVIDER)
            fakeirc("join", user.Handle+"["+SUFFIX+"]", CHANNEL)

signal.signal(signal.SIGINT, on_interrupt)
skype.OnMessageStatus = on_message_status
skype.OnOnlineStatus = on_online_status

listener = subprocess.Popen([FAKEIRC, "listen", CHANNEL, PROVIDER], stdout=subprocess.PIPE)
message_buffer = ""
def main_loop():
    global message_buffer
    while True:
        stdout_data = listener.stdout.read(1)
        message_buffer += stdout_data
        while "\n" in message_buffer:
            line, _, message_buffer = message_buffer.partition("\n")
            print(line)
            chat.SendMessage(line)

if __name__ == "__main__":
    main_loop()
