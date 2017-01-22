# SwiftBot
A bot to showcase [SwiftDiscord](https://github.com/nuclearace/SwiftDiscord)

SwiftBot is designed to be used in many large guilds, and as such, is a distributed bot. That is, there are multiple shard processes created for one "bot". The number of processes spawned is controlled by `numberOfShards` in config.swift located in `Shared`. This can be set to one if you only want a single shard instance running.

The bot is made of one module, and two executables.

Shared
------
Contains the config file, and a set of utilities.

SwiftShard
--------
Is an actual shard executable, and contains the logic for commands, guilds, etc. This executable is not meant to be launched directly. Instead `SwiftBot` should be used.

SwiftBot
-------------------
Is the controller for all of the shards. It is responsible for keeping the shards alive, should one of them die. It also responsible for global api rate limits, such as the Wolfram-Alpha limit. If a shard wishes to remove a token from one of the limiters, it makes a RMI to see if it can make the request.
