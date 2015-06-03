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
for m in chat.Members:
    if m == skype.CurrentUser:
        continue
    members.append(m.Handle)
    fakeirc("add", m.Handle+"["+SUFFIX+"]", PROVIDER)
    if m.OnlineStatus != "ONLINE":
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
                fakeirc("message", message.Sender.Handle+"["+SUFFIX+"]", CHANNEL, unicode.encode(message.Body, 'utf-8'))
            elif message.Type == "EMOTED":
                fakeirc("action", message.Sender.Handle+"["+SUFFIX+"]", CHANNEL, unicode.encode(message.Body, 'utf-8'))
        else:
            print(message, status)

def on_online_status(user, status):
    if user.Handle in members:
        if status != "ONLINE":
            fakeirc("away", user.Handle+"["+SUFFIX+"]")
        else:
            fakeirc("unaway", user.Handle+"["+SUFFIX+"]")

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
