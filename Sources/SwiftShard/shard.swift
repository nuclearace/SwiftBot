// The MIT License (MIT)
// Copyright (c) 2017 Erik Little

// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
// documentation files (the "Software"), to deal in the Software without restriction, including without
// limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
// Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
// Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
// BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.

import Cleverbot
import Dispatch
import Foundation
import Shared
import SocksCore
import SwiftDiscord
import SwiftRateLimiter
#if os(macOS)
import ImageBrutalizer

let machTaskBasicInfoCount = MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
#endif

typealias QueuedVideo = (link: String, channel: String)

enum ShardCall : String {
    case connect
    case die
    case getStats
    case setup
}

class Shard : DiscordClientDelegate {
    var bot: Bot!
    let cleverbot = Cleverbot { print("Cleverbot is ready") }
    let client: DiscordClient
    let startTime = Date()
    let shardNum: Int
    let totalShards: Int

    var connected = false
    var inVoiceChannel = [String: Bool]()
    var orphaned = true
    var playingYoutube = [String: Bool]()
    var youtubeQueue = [String: [QueuedVideo]]()

    private var connectId = -1
    private var heartbeatInterval = -1
    private var pongsMissed = 0
    private var statsCallbacks = [([String: Any]) -> Void]()
    private var waitingForStats = false

    init(token: DiscordToken, shardNum: Int, totalShards: Int) {
        self.shardNum = shardNum
        self.totalShards = totalShards

        client = DiscordClient(token: token, configuration: [
            .log(.none),
            .singleShard(DiscordShardInformation(shardNum: shardNum, totalShards: totalShards)),
            .fillUsers,
            .pruneUsers
        ])
        client.delegate = self

        bot = Bot(shard: self, shardNum: shardNum)
    }

    func clearStats() {
        waitingForStats = false
        statsCallbacks.removeAll()
    }

    func client(_ client: DiscordClient, didConnect reason: Bool) {
        connected = true

        print("Shard #\(shardNum) connected")

        bot.sendResult(true, for: connectId)
    }

    func client(_ client: DiscordClient, didDisconnectWithReason reason: String) {
        print("Shard #\(shardNum) disconnected")

        connected = false

        do {
            try bot.socket?.close()
        } catch {
            print("Error closing #\(shardNum)")
        }

        exit(0)
    }

    func client(_ client: DiscordClient, didCreateMessage message: DiscordMessage) {
        handleMessage(message)
    }

    func client(_ client: DiscordClient, isReadyToSendVoiceWithEngine engine: DiscordVoiceEngine) {
        print("voice engine ready")

        inVoiceChannel[engine.voiceState.guildId] = true
        playingYoutube[engine.voiceState.guildId] = false

        guard var queue = youtubeQueue[engine.voiceState.guildId], !queue.isEmpty else {
            return
        }

        let video = queue.remove(at: 0)
        youtubeQueue[engine.voiceState.guildId] = queue

        client.sendMessage("Playing \(video.link)", to: video.channel)

        _ = playYoutube(channelId: video.channel, link: video.link)
    }

    func brutalizeImage(options: [String], channel: DiscordChannel) {
        #if os(macOS)
        let args = options.map(BrutalArg.init)
        var imagePath: String!

        loop: for arg in args {
            switch arg {
            case let .url(image):
                imagePath = image
                break loop
            default:
                continue
            }
        }

        guard imagePath != nil else {
            channel.sendMessage("Missing image url")

            return
        }

        guard let request = createGetRequest(for: imagePath) else {
            channel.sendMessage("Invalid url")

            return
        }

        getRequestData(for: request) {data in
            guard let data = data else {
                channel.sendMessage("Something went wrong with the request")

                return
            }

            guard let brutalizer = ImageBrutalizer(data: data) else {
                channel.sendMessage("Invalid image")

                return
            }

            for arg in args {
                arg.brutalize(with: brutalizer)
            }

            guard let outputData = brutalizer.outputData else {
                channel.sendMessage("Something went wrong brutalizing the image")

                return
            }

            channel.sendFile(DiscordFileUpload(data: outputData, filename: "brutalized.png", mimeType: "image/png"),
                content: "Brutalized:")
        }
        #else
        channel.sendMessage("Not available on Linux")
        #endif
    }

    func calculateStats() -> [String: Any] {
        var stats = [String: Any]()

        let guilds = client.guilds.map({ $0.value })
        let channels = guilds.flatMap({ $0.channels.map({ $0.value }) })
        let username = client.user!.username
        let guildNumber = guilds.count
        let numberOfTextChannels = channels.filter({ $0.type == .text }).count
        let numberOfVoiceChannels = channels.count - numberOfTextChannels
        let numberOfLoadedUsers = guilds.reduce(0, { $0 + $1.members.count })
        let totalUsers = guilds.reduce(0, { $0 + $1.memberCount })

        stats["name"] = username
        stats["numberOfGuilds"] = guildNumber
        stats["numberOfTextChannels"] = numberOfTextChannels
        stats["numberOfVoiceChannels"] = numberOfVoiceChannels
        stats["numberOfLoadedUsers"] = numberOfLoadedUsers
        stats["totalNumberOfUsers"] =  totalUsers
        stats["shardNum"] = shardNum
        stats["shards"] = totalShards
        stats["orphan"] = orphaned

        #if os(macOS)
        let name = mach_task_self_
        let flavor = task_flavor_t(MACH_TASK_BASIC_INFO)
        var size = mach_msg_type_number_t(machTaskBasicInfoCount)
        let infoPointer = UnsafeMutablePointer<mach_task_basic_info>.allocate(capacity: 1)

        task_info(name, flavor, unsafeBitCast(infoPointer, to: task_info_t!.self), &size)

        stats["memory"] = Double(infoPointer.pointee.resident_size) / 10e5

        infoPointer.deallocate(capacity: 1)
        #endif

        return stats
    }

    func connect(id: Int, waitTime wait: Int?) {
        guard !connected else { return }

        let wait = wait ?? 1
        connectId = id

        print("Shard #\(shardNum) got connect command, connecting in \(wait) seconds")

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(wait)) {
            self.client.connect()
        }
    }

    func disconnect() {
        client.disconnect()
    }

    func findChannelFromName(_ name: String, in guild: DiscordGuild? = nil) -> DiscordGuildChannel? {
        // We have a guild to narrow the search
        if guild != nil, let channels = client.guilds[guild!.id]?.channels {
            return channels.filter({ $0.value.name == name }).map({ $0.1 }).first
        }

        // No guild, go through all the guilds
        // Returns first channel in the first guild with a match if multiple channels have the same name
        return client.guilds.flatMap({_, guild in
            return guild.channels.reduce(DiscordGuildChannel?.none, {cur, keyValue in
                guard cur == nil else { return cur } // already found

                return keyValue.value.name == name ? keyValue.value : nil
            })
        }).first
    }

    func getFortune() -> String {
        guard fortuneExists else {
            return "This bot doesn't have fortune installed"
        }

        let fortune = EncoderProcess()
        let pipe = Pipe()
        var saying: String!

        fortune.launchPath = "/usr/local/bin/fortune"
        fortune.standardOutput = pipe
        fortune.terminationHandler = {process in
            guard let fortune = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
                return
            }

            saying = fortune
        }

        fortune.launch()
        fortune.waitUntilExit()

        return saying
    }

    func getRolesForUser(_ user: DiscordUser, on channelId: String) -> [DiscordRole] {
        for (_, guild) in client.guilds where guild.channels[channelId] != nil {
            guard let userInGuild = guild.members[user.id] else {
                print("This user doesn't seem to be in the guild?")

                return []
            }

            return guild.roles.filter({ userInGuild.roles.contains($0.key) }).map({ $0.1 })
        }

        return []
    }

    func getStats(callback: @escaping ([String: Any]) -> Void) {
        guard !orphaned else {
            callback(calculateStats())

            return
        }

        statsCallbacks.append(callback)

        guard !waitingForStats else { return }

        waitingForStats = true

        // Make a RPC to fetch the stats for the entire network
        bot.call("getStats") {stats in
            defer { self.clearStats() }

            guard let stats = stats as? [String: Any] else { return }

            for callback in self.statsCallbacks {
                callback(stats)
            }
        }
    }

    private func handleMessage(_ message: DiscordMessage) {
        guard message.content.hasPrefix("$") else { return }

        let commandArgs = String(message.content.characters.dropFirst()).components(separatedBy: " ")
        let command = commandArgs[0]

        handleCommand(command.lowercased(), with: Array(commandArgs.dropFirst()), message: message)
    }

    func handleRemoteCall(_ method: String, withParams params: [String: Any], id: Int?) throws {
        guard let event = ShardCall(rawValue: method) else { throw SwiftBotError.invalidCall }

        switch (event, id) {
        case (.die, _):               disconnect()
        case let (.connect, id?):     connect(id: id, waitTime: params["wait"] as? Int)
        case let (.getStats, id?):    bot.sendResult(calculateStats(), for: id)
        case (.setup, _):             setup(with: params)
        default:                      throw SwiftBotError.invalidCall
        }
    }

    func playYoutube(channelId: String, link: String) -> String {
        guard let guild = client.guildForChannel(channelId), inVoiceChannel[guild.id] ?? false else {
            return "Not in voice channel"
        }
        guard !(playingYoutube[guild.id] ?? true) else {
            youtubeQueue[guild.id]?.append((link, channelId))

            return "Video Queued. \(youtubeQueue[guild.id]?.count ?? -10000) videos in queue"
        }

        playingYoutube[guild.id] = true

        let youtube = EncoderProcess()
        youtube.launchPath = "/usr/local/bin/youtube-dl"
        youtube.arguments = ["-f", "bestaudio", "-q", "-o", "-", link]
        youtube.standardOutput = client.voiceEngines[guild.id]!.requestFileHandleForWriting()!

        youtube.terminationHandler = {[weak self] process in
            self?.client.voiceEngines[guild.id]?.encoder?.finishEncodingAndClose()
        }

        youtube.launch()

        return "Playing"
    }

    private func sendPing() {
        guard pongsMissed < 2, !orphaned else {
            setupOrphanedShard()

            return
        }

        pongsMissed += 1

        bot.call("ping") {alive in
            self.pongsMissed = 0
        }

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(heartbeatInterval), execute: sendPing)
    }

    /**
        Sets the shard into orphaned mode. All API requests fail, stats return only this shard, and the shard attempts
        to reestablish contanct with the Bot.
    */
    func setupOrphanedShard() {
        guard !orphaned else { return }

        print("Putting shard #\(shardNum) into orphaned mode")

        orphaned = true

        unorphan()
    }

    private func setup(with params: [String: Any]) {
        guard let heartbeatInterval = params["heartbeatInterval"] as? Int else {
            fatalError("Shard \(shardNum) didn't get a heartbeat")
        }

        self.heartbeatInterval = heartbeatInterval
        orphaned = false

        sendPing()
    }

    func unorphan() {
        guard orphaned else { return }

        do {
            try bot.identify()
        } catch let err {
            print("Error trying to unorphan shard #\(shardNum) \(err)")
        }

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 10, execute: unorphan)
    }
}
