# FakeIRC
Transparent anything-to-IRC bridge for ngircd

## Usage
```
fakeirc <name> <host> <port> <password>
fakeirc add <user> [<provider>]
fakeirc remove <user>
fakeirc join <user> <channel>
fakeirc part <user> <channel>
fakeirc away <user>
fakeirc unaway <user>
fakeirc message <user> <channel> <message>
fakeirc action <user> <channel> <action>
fakeirc listen <channel> [<provider>]
```

## Included bridges
* Docker-Minecraft
* Skype group chat
