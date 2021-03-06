#!/usr/bin/env python2
from __future__ import print_function
import Skype4Py
import os
import re
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

def irc_nick(skype_handle):
    return skype_handle.replace(".", "") + "[" + SUFFIX + "]"

skype = Skype4Py.Skype()
skype.Attach()
my_nick = skype.CurrentUser.Handle
chat = skype.Chat(CHATNAME)
old_topic = chat.Topic

members = []
for m in chat.Members:
    if m == skype.CurrentUser:
        continue
    members.append(m.Handle)
    fakeirc("add", irc_nick(m.Handle), PROVIDER)
    if m.OnlineStatus != "ONLINE":
        fakeirc("away", irc_nick(m.Handle))
    fakeirc("join", irc_nick(m.Handle), CHANNEL)

def cleanup():
    for m in members:
        fakeirc("remove", irc_nick(m))

def on_interrupt(signo, stackframe):
    cleanup()
    sys.exit(0)

def on_message_status(message, status):
    if message.Chat == chat:
        if status == "RECEIVED":
            if message.Type == "SAID":
                for line in message.Body.split('\n'):
                    fakeirc("message", irc_nick(message.Sender.Handle), CHANNEL, unicode.encode(line, 'utf-8'))
            elif message.Type == "EMOTED":
                fakeirc("action", irc_nick(message.Sender.Handle), CHANNEL, unicode.encode(message.Body, 'utf-8'))
            elif message.Type == "SETTOPIC":
                fakeirc("topic", irc_nick(message.Sender.Handle), CHANNEL, unicode.encode(message.Body, 'utf-8'))
        else:
            print(message, status)

def on_online_status(user, status):
    if user.Handle in members:
        if status != "ONLINE":
            fakeirc("away", irc_nick(user.Handle))
        else:
            fakeirc("unaway", irc_nick(user.Handle))

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
            if re.match('^\<([^>]+)> (.+)$', line):
                chat.SendMessage(line)
            elif re.match('^\* ([^ ]+) (.+)$', line):
                chat.SendMessage(line)
            elif re.match('^TOPIC (.+)$', line):
                m = re.match('^TOPIC (.+)$', line)
                chat.Topic = m.group(1)

if __name__ == "__main__":
    main_loop()
