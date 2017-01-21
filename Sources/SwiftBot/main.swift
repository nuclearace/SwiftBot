// The MIT License (MIT)
// Copyright (c) 2016 Erik Little

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

import CoreFoundation
import Dispatch
import Foundation
import Shared
import Socks
import SocksCore
import struct SwiftDiscord.DiscordToken

guard CommandLine.arguments.count == 6 else { fatalError("Not enough information to start") }

let token = DiscordToken(stringLiteral: CommandLine.arguments[1])
let shardNum = Int(CommandLine.arguments[2])!
let totalShards = Int(CommandLine.arguments[3])!
let weather = CommandLine.arguments[4]
let wolfram = CommandLine.arguments[5]

let authorImage = URL(string: "https://avatars1.githubusercontent.com/u/1211049?v=3&s=460")
let authorUrl = URL(string: "https://github.com/nuclearace")
let sourceUrl = URL(string: "https://github.com/nuclearace/SwiftBot")!
let ignoreGuilds = ["81384788765712384"]
let userOverrides = ["104753987663712256"]
let fortuneExists = FileManager.default.fileExists(atPath: "/usr/local/bin/fortune")

let bot = DiscordBot(token: token, shardNum: shardNum, totalShards: totalShards)

enum BotEvent : String {
    case die
    case getStats
    case stat
}

class ShardManager {
    let botId = UUID()
    let queue = DispatchQueue(label: "Async Read")
    let slaveClient: TCPClient

    var stats = [[String: Any]]()
    var statsCallbacks = [([String: Any]) -> Void]()
    var waitingForStats = false

    init() throws {
        slaveClient = try TCPClient(address: InternetAddress(hostname: "127.0.0.1", port: 42343))
    }

    func die() {
        do {
            try slaveClient.close()
        } catch {
            print("Error closing #\(shardNum)")
        }

        exit(0)
    }

    func getStats() {
        let data: [String: Any] = [
            "method": "stat",
            "params": bot.calculateStats(),
            "id": shardNum
        ]

        do {
            try dispatchToMaster(object: data)
        } catch {
            print("Error trying to send stats")
        }
    }

    func handleMasterEvent(socket: TCPInternetSocket) throws {
        let messageData = try getDataFromSocket(socket)

        guard let stringJSON = String(data: Data(bytes: messageData), encoding: .utf8),
              let json = decodeJSON(stringJSON) as? [String: Any],
              let eventString = json["method"] as? String,
              let event = BotEvent(rawValue: eventString) else { return }

        switch event {
        case .die:          killBot()
        case .getStats:     getStats()
        case .stat:         handleStat(stat: json)
        }
    }

    func handleStat(stat: [String: Any]) {
        guard waitingForStats else { return }
        guard let jsonStats = stat["params"] as? [String: Any] else {
            stats.append([:])

            if stats.count == totalShards {
                sendStats()
            }

            return
        }

        stats.append(jsonStats)

        guard stats.count == totalShards else { return }

        sendStats()
    }

    func identify() throws {
        let buf = UnsafeMutableRawBufferPointer.allocate(count: 4)
        buf.storeBytes(of: UInt32(shardNum).bigEndian, as: UInt32.self)

        try slaveClient.send(bytes: Array(buf))
        try slaveClient.socket.startWatching(on: DispatchQueue.main) {
            do {
               try self.handleMasterEvent(socket: self.slaveClient.socket)
            } catch {
                print("Error reading on bot \(shardNum)")
            }
        }
    }

    func killBot() {
        print("Got notification that we should die")

        bot.disconnect()
    }

    func requestStats(withCallback callback: @escaping ([String: Any]) -> Void) {
        statsCallbacks.append(callback)

        // guard !waitingForStats else { return }

        waitingForStats = true

        do {
            try dispatchToMaster(object: [
                "method": "requestStats",
                "params": [:],
                "id": shardNum
            ])
        } catch {
            print("error sending")
        }

    }

    private func dispatchToMaster(object: [String: Any]) throws {
        try slaveClient.send(bytes: encodeDataPacket(object))
    }

    func sendStats() {
        let fullStats = stats.reduce([:], reduceStats)

        for callback in statsCallbacks {
            callback(fullStats)
        }

        statsCallbacks.removeAll()
        stats.removeAll()
        waitingForStats = false
    }
}

let manager = try ShardManager()
try manager.identify()

bot.connect()

CFRunLoopRun()
