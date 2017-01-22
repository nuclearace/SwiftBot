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
import CryptoSwift
import Dispatch
import Foundation
import Shared
import Socks
import SocksCore

guard CommandLine.arguments.count == 3 else { fatalError("Not enough information to start") }

let shardNum = Int(CommandLine.arguments[1])!
let totalShards = Int(CommandLine.arguments[2])!
let fortuneExists = FileManager.default.fileExists(atPath: "/usr/local/bin/fortune")

let bot = DiscordBot(token: token, shardNum: shardNum, totalShards: totalShards)

enum BotCall : String {
    case connect
    case die
    case getStats
}

class ShardManager : RemoteCallable {
    let queue = DispatchQueue(label: "Async Read")
    let shardNum: Int

    var connectId = -1
    var currentCall = 0
    var socket: TCPInternetSocket?
    var statsCallbacks = [([String: Any]) -> Void]()
    var waitingCalls =  [Int: (Any) throws -> Void]()
    var waitingForStats = false

    init(shardNum: Int) throws {
        self.shardNum = shardNum
        socket = try TCPInternetSocket(address: InternetAddress(hostname: "127.0.0.1", port: 42343))
        try socket?.connect()
    }

    func clearStats() {
        waitingForStats = false
        statsCallbacks.removeAll()
    }

    func connect(id: Int, waitTime wait: Int?) {
        let wait = wait ?? 1
        connectId = id

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(wait)) {
            bot.connect()
        }
    }

    func die() {
        do {
            try socket?.close()
        } catch {
            print("Error closing #\(shardNum)")
        }

        exit(0)
    }

    func getStats(id: Int) {
        let data: [String: Any] = [
            "result": bot.calculateStats(),
            "id": id
        ]

        do {
            try dispatchToMaster(object: data)
        } catch {
            print("Error trying to send stats")
        }
    }

    func identify() throws {
        let identifyData: [String: Any] = [
            "shard": shardNum,
            "pw": "\(authToken)\(shardNum)".sha512()
        ]

        try socket?.send(data: encodeDataPacket(identifyData))
        try socket?.startWatching(on: DispatchQueue.main) {
            do {
               try self.handleMessage()
            } catch {
                print("Error reading on bot \(self.shardNum)")
            }
        }
    }

    func handleRemoteCall(_ method: String, withParams params: [String: Any], id: Int?) throws {
        guard let event = BotCall(rawValue: method) else { throw SwiftBotError.invalidCall }

        switch (event, id) {
        case (.die, _):               killBot()
        case let (.connect, id?):     connect(id: id, waitTime: params["wait"] as? Int)
        case let (.getStats, id?):    getStats(id: id)
        default:                      throw SwiftBotError.invalidCall
        }
    }

    func killBot() {
        print("Got notification that we should die")

        bot.disconnect()
    }

    func removeWeatherToken(withCallback callback: @escaping (Bool) -> Void) {
        call("removeWeatherToken") {canWeather in
            guard let canWeather = canWeather as? Bool else { return callback(false) }

            callback(canWeather)
        }
    }

    func removeWolframToken(withCallback callback: @escaping (Bool) -> Void) {
        call("removeWolframToken") {canWolfram in
            guard let canWolfram = canWolfram as? Bool else { return callback(false) }

            callback(canWolfram)
        }
    }

    func requestStats(withCallback callback: @escaping ([String: Any]) -> Void) {
        statsCallbacks.append(callback)

        guard !waitingForStats else { return }

        waitingForStats = true

        // Make a RPC to fetch the stats for the entire network
        call("getStats") {stats in
            defer { self.clearStats() }

            guard let stats = stats as? [String: Any] else { return }

            for callback in self.statsCallbacks {
                callback(stats)
            }
        }
    }

    private func dispatchToMaster(object: [String: Any]) throws {
        try socket?.send(data: encodeDataPacket(object))
    }
}

let manager = try ShardManager(shardNum: shardNum)
try manager.identify()

CFRunLoopRun()
