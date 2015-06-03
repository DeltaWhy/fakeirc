# FakeIRC
Transparent anything-to-IRC bridge for ngircd

## Usage
```
fakeirc -c <config_file>
fakeirc add <user> [<provider>]
fakeirc remove <user>
fakeirc join <user> <channel>
fakeirc part <user> <channel>
fakeirc message <user> <channel> <message>
fakeirc action <user> <channel> <action>
fakeirc listen ALL [<channel>]
fakeirc listen <provider> [<channel>]
```

## Config
```
name = bridge.irc.your.domain
host = irc.your.domain
port = 6667
password = your_server_password
pidfile = fakeirc.pid
socket = fakeirc.sock
```
