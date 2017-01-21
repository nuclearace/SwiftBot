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

let queue = DispatchQueue(label: "Async Read")
let bot = DiscordBot(token: token, shardNum: shardNum, totalShards: totalShards)

#if os(macOS)
class ShardManager : NSObject {
    let botId = UUID()
    let center = DistributedNotificationCenter.default()

    var stats = [[String: Any]]()
    var statsCallbacks = [([String: Any]) -> Void]()
    var waitingForStats = false

    override init() {
        super.init()

        center.addObserver(self, selector: #selector(ShardManager.killBot(_:)),
                           name: NSNotification.Name("die"), object: nil)
        center.addObserver(self, selector: #selector(ShardManager.getStats(_:)),
                           name: NSNotification.Name("stats"), object: nil)
        center.addObserver(self, selector: #selector(ShardManager.handleStat(_:)),
                           name: NSNotification.Name("stat"), object: nil)
    }

    deinit {
        center.removeObserver(self)
    }

    func getStats(_ notification: NSNotification) {
        guard let json = encodeJSON(bot.calculateStats()) else { return }

        center.post(name: NSNotification.Name("stat"), object: json)
    }

    func handleStat(_ notification: NSNotification) {
        guard waitingForStats else { return } // We don't care

        guard let object = notification.object as? String,
              let json = decodeJSON(object) as? [String: Any] else {
            stats.append([:])

            if stats.count == totalShards {
                sendStats()
            }

            return
        }

        stats.append(json)

        guard stats.count == totalShards else { return }

        sendStats()
    }

    func killBot(_ notification: NSNotification) {
        print("Got notification that we should die")

        center.removeObserver(self)

        bot.disconnect()
    }

    func requestStats(withCallback callback: @escaping ([String: Any]) -> Void) {
        statsCallbacks.append(callback)

        guard !waitingForStats else { return }

        waitingForStats = true
        center.post(name: NSNotification.Name("stats"), object: nil)
    }

    func sendStats() {
        func reduceStats(currentStats: [String: Any], otherStats: [String: Any]) -> [String: Any] {
            var mutStats = currentStats

            for (key, stat) in otherStats {
                guard let cur = mutStats[key] else {
                    mutStats[key] = stat

                    continue
                }

                // Hacky, but trying to switch on the types fucks up, because on macOS JSONSerialization
                // turns numbers into some generic __NSCFNumber type, which can cast to anything.
                switch key {
                case "shards":      fallthrough
                case "name":        continue
                case "uptime":      fallthrough
                case "memory":      mutStats[key] = cur as! Double + (stat as! Double)
                default:            mutStats[key] = cur as! Int + (stat as! Int)
                }
            }

            return mutStats
        }

        let fullStats = stats.reduce([:], reduceStats)

        for callback in statsCallbacks {
            callback(fullStats)
        }

        waitingForStats = false
        statsCallbacks.removeAll()
    }
}

let manager = ShardManager()
#endif

func readAsync() {
    queue.async {
        guard let input = readLine(strippingNewline: true) else { fatalError() }

        if input == "quit" {
            bot.disconnect()
        }

        readAsync()
    }
}

readAsync()

bot.connect()

CFRunLoopRun()
