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
import NIO
import Shared
import SwiftDiscord
import SwiftRateLimiter
#if os(macOS)
let machTaskBasicInfoCount = MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
#endif

typealias QueuedVideo = (link: String, channel: ChannelID)

enum ShardCall : String {
    case connect
    case die
    case getStats
    case setup
}

class Shard : DiscordClientDelegate {
    var bot: Bot!
    let cleverbot = Cleverbot(apiKey: cleverbotKey)
    var client: DiscordClient!
    let startTime = Date()
    let adoptLimiter = RateLimiter(tokensPerInterval: 15, interval: .minute, firesImmediatly: true)
    let shardingInfo: DiscordShardInformation

    var connected = false
    var orphaned = true
    var voiceChannels = [GuildID: VoiceChannelInfo]()

    var shardNum: Int {
        return shardingInfo.shardRange.first!
    }

    var totalShards: Int {
        return shardingInfo.totalShards
    }

    private var connectId = -1
    private var heartbeatInterval = -1
    private var pongsMissed = 0
    private var statsCallbacks = [([String: Any]) -> ()]()
    private var waitingForStats = false

    init(token: DiscordToken, shardingInfo: DiscordShardInformation) {
        self.shardingInfo = shardingInfo

        client = DiscordClient(token: token, delegate: self, configuration: [
            .log(.trace),
            .shardingInfo(shardingInfo),
            .fillUsers,
            .pruneUsers,
            .voiceConfiguration(DiscordVoiceEngineConfiguration(captureVoice: false, decodeVoice: false))
        ])

        bot = Bot(
            shard: self,
            shardNum: shardNum,
            shardCount: shardingInfo.shardRange.count,
            runloop: MultiThreadedEventLoopGroup.currentEventLoop!
        )
    }

    func clearStats() {
        waitingForStats = false
        statsCallbacks.removeAll()
    }

    func client(_ client: DiscordClient, didConnect reason: Bool) {
        connected = true

        guard connectId >= 0 else {
            print("Jump started shard connected. Shard #\(shardNum)")

            return
        }

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

        guard let channelInfo = voiceChannels[engine.guildId] else { return }

        channelInfo.playingYoutube = false

        guard !channelInfo.queue.isEmpty else { return }

        let video = channelInfo.queue.remove(at: 0)

        client.sendMessage(playYoutube(channelId: video.channel, link: video.link), to: video.channel)
    }

    func client(_ client: DiscordClient, needsDataSourceForEngine engine: DiscordVoiceEngine) throws -> DiscordVoiceDataSource {
        let encoder = try DiscordOpusEncoder(bitrate: 128_000)
        var source = DiscordBufferedVoiceDataSource(opusEncoder: encoder)

        DispatchQueue.main.sync {
            guard let channelInfo = voiceChannels[engine.guildId] else { return }

//            source = DiscordBufferedVoiceDataSource(opusEncoder: encoder,
//                                                    bufferSize: channelInfo.bufferMax,
//                                                    drainThreshold: channelInfo.drainThreshold)

              let url = URL(fileURLWithPath: ("~/Desktop/out.raw" as NSString).expandingTildeInPath)
              source = try! DiscordVoiceFileDataSource(opusEncoder: encoder, file: url)
        }

        return source
    }

    func calculateStats() -> [String: Any] {
        var stats = [String: Any]()

        let guilds = client.guilds.map({ $0.value })
        let channels = guilds.flatMap({ $0.channels.map({ $0.value }) })
        let username = client.user!.username
        let guildNumber = guilds.count
        let numberOfTextChannels = channels.compactMap({ $0 as? DiscordTextChannel }).count
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

        let _ = infoPointer.withMemoryRebound(to: Int32.self, capacity: 1) {p in
            task_info(name, flavor, p, &size)
        }

        stats["memory"] = Double(infoPointer.pointee.resident_size) / 10e5

        infoPointer.deallocate()
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

    func findChannel(from name: String, in guild: DiscordGuild? = nil) -> DiscordGuildChannel? {
        // We have a guild to narrow the search
        guard guild == nil else {
            if let channels = client.guilds[guild!.id]?.channels {
                return channels.filter({ $0.value.name == name }).map({ $0.1 }).first
            } else {
                return nil
            }
        }

        // No guild, go through all the guilds
        // Returns first channel in the first guild with a match if multiple channels have the same name
        return client.guilds.compactMap({_, guild in
            return guild.channels.reduce(DiscordGuildChannel?.none, {cur, keyValue in
                guard cur == nil else { return cur } // already found

                return keyValue.value.name == name ? keyValue.value : nil
            })
        }).first
    }

    func findVoiceChannel(from name: String, in guild: DiscordGuild?) -> DiscordGuildChannel? {
        guard let channel = findChannel(from: name, in: guild), channel is DiscordGuildVoiceChannel else {
            return nil
        }

        return channel
    }

    func getFortune() -> String {
        guard fortuneExists else {
            return "This bot doesn't have fortune installed"
        }

        let fortune = Process()
        let pipe = Pipe()
        var saying = "The Fortune does not look good"

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

    func getRolesForUser(_ user: DiscordUser, on channelId: ChannelID) -> [DiscordRole] {
        for (_, guild) in client.guilds where guild.channels[channelId] != nil {
            guard let member = guild.members[user.id] else {
                print("This user doesn't seem to be in the guild?")

                return []
            }

            return member.roles ?? guild.roles(for: member)
        }

        return []
    }

    func getStats(callback: @escaping ([String: Any]) -> ()) {
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

        let commandArgs = String(message.content.dropFirst()).components(separatedBy: " ")
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

    func playYoutube(channelId: ChannelID, link: String, playNext: Bool = false) -> DiscordMessage {
        guard let guild = client.guildForChannel(channelId),
              var channelInfo = voiceChannels[guild.id],
              let voiceEngine = client.voiceManager.voiceEngines[guild.id] else {
            return "Not in voice channel"
        }

        defer { voiceChannels[guild.id] = channelInfo }

        guard !channelInfo.playingYoutube else {
            let insertLocation = playNext ? 0 : channelInfo.queue.count

            channelInfo.queue.insert((link, channelId), at: insertLocation)

            return DiscordMessage(content: "Video Queued\(playNext ? " Next" : ""). " +
                                           "\(channelInfo.queue.count) videos in queue")
        }

        channelInfo.playingYoutube = true

        let youtube = Process()
        youtube.launchPath = "/usr/local/bin/youtube-dl"
        youtube.arguments = ["-f", "bestaudio", "--no-cache-dir", "--no-part", "--no-continue", "-q", "-o", "-", link]

        voiceEngine.setupMiddleware(youtube) {
            print("youtube died")
        }

        return DiscordMessage(content: "Playing \(link)")
    }

    private func sendPing() {
        guard pongsMissed < 2, !orphaned else {
            print("Missed too many pings. Shard #\(shardNum)")
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

        adoptLimiter.removeTokens(1) {tokens in
            guard tokens > 0 else { fatalError("Trying to unorphan too quickly") }

            print("Putting shard #\(self.shardNum) into orphaned mode. Tokens left: \(tokens)")

            self.orphaned = true

            self.unorphan()
        }
    }

    private func setup(with params: [String: Any]) {
        guard let heartbeatInterval = params["heartbeatInterval"] as? Int else {
            fatalError("Shard \(shardNum) didn't get a heartbeat")
        }

        self.heartbeatInterval = heartbeatInterval
        orphaned = false
        pongsMissed = 0

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

class VoiceChannelInfo {
    var bufferMax = 15_000
    var drainThreshold = 13_500
    var playingYoutube = false
    var queue = [QueuedVideo]()

    init(bufferMax: Int, drainThreshold: Int) {
        self.bufferMax = bufferMax
        self.drainThreshold = drainThreshold
    }
}
