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

import CoreFoundation
import Dispatch
import Foundation
import Shared
import SocksCore
import SwiftRateLimiter

#if os(Linux)
typealias Process = Task
#endif

let token = "Bot token"
let weather = ""
let wolfram = ""
let numberOfShards = 2
let botProcessLocation = FileManager.default.currentDirectoryPath + "/.build/release/SwiftBot"
let botId = UUID()
let weatherLimiter = RateLimiter(tokensPerInterval: 10, interval: "minute", firesImmediatly: true)
let wolframLimiter = RateLimiter(tokensPerInterval: 67, interval: "day", firesImmediatly: true)

let queue = DispatchQueue(label: "Async Read")

enum BotCall : String {
    case getStats
    case removeWeatherToken
    case removeWolframToken
}

class BotProcess : RemoteCallable {
    let process: Process
    let shardNum: Int

    weak var manager: BotManager?
    var socket: TCPInternetSocket?

    var currentCall = 0
    var waitingCalls = [Int: (Any) throws -> Void]()

    init(process: Process, manager: BotManager, shardNum: Int) {
        self.process = process
        self.manager = manager
        self.shardNum = shardNum
    }

    func attachSocket(_ socket: TCPInternetSocket) throws {
        self.socket = socket

        try socket.startWatching(on: DispatchQueue.main) {
            print("Bot \(self.shardNum) has something waiting")

            do {
               try self.handleMessage()
            } catch let err {
                print("Error reading from shard #\(self.shardNum) \(err)")
            }
        }
    }

    func handleRemoteCall(_ method: String, withParams params: [String: Any], id: Int?) throws {
        try manager?.handleRemoteCall(method, withParams: params, id: id, shardNum: shardNum)
    }
}

class BotManager {
    let acceptQueue = DispatchQueue(label: "Accept Queue")
    let botQueue = DispatchQueue(label: "Bot Queue")
    let masterServer: TCPInternetSocket

    var bots = [Int: BotProcess]()
    var killingBots = false
    var shutdownBots = 0
    var stats = [[String: Any]]()
    var waitingForStats = false

    init() throws {
        masterServer = try TCPInternetSocket(address: InternetAddress(hostname: "127.0.0.1", port: 42343))
    }

    func acceptConnection() {
        acceptQueue.async {
            print("Waiting for a new connection")

            do {
                try self.attachSocketToBot(try self.masterServer.accept())
                self.acceptConnection()
            } catch {
                // TODO see how we can recover. Kill bots? Tell them to reconnect?
                print("Error accepting connections")
            }
        }
    }

    func attachSocketToBot(_ socket: TCPInternetSocket) throws {
        print("Got new connection")

        // Before a bot starts up, it should identify itself
        let botNumData = try socket.recv(maxBytes: 4).map(Int.init)
        let botNum = botNumData[0] << 24 | botNumData[1] << 16 | botNumData[2] << 8 | botNumData[3]

        print("Shard #\(botNum) identified")

        try bots[Int(botNum)]?.attachSocket(socket)
    }

    func callAll(_ method: String, params: [String: Any] = [:], complete: ((Any) throws -> Void)? = nil) throws {
        for (_, bot) in bots {
            bot.call(method, withParams: params, onComplete: complete)
        }
    }

    func killBots() {
        killingBots = true

        do {
            try callAll("die")
            try masterServer.close()
        } catch {
            print("couldn't close server")
        }
    }

    func launchBot(withShardNum shardNum: Int) {
        let botProcess = Process()

        botProcess.launchPath = botProcessLocation
        botProcess.arguments = [token, "\(shardNum)", "\(numberOfShards)", weather, wolfram]
        botProcess.terminationHandler = {process in
            print("Bot \(shardNum) died")

            guard self.killingBots else {
                print("Restarting it")

                self.launchBot(withShardNum: shardNum)

                return
            }

            self.shutdownBots += 1

            if self.shutdownBots == self.bots.count {
                exit(0)
            }
        }

        botProcess.launch()

        bots[shardNum] = BotProcess(process: botProcess,
                                    manager: self,
                                    shardNum: shardNum)
    }

    func handleRemoteCall(_ method: String, withParams params: [String: Any], id: Int?, shardNum: Int) throws {
        guard let call = BotCall(rawValue: method) else { throw SwiftBotError.invalidCall }

        func _handleStat(_ id: Int) -> (Any) throws -> Void {
            waitingForStats = true

            return {stat in
                guard self.waitingForStats, let stat = stat as? [String: Any] else {
                    throw SwiftBotError.invalidArgument
                }

                self.stats.append(stat)

                guard self.stats.count == numberOfShards else { return }

                self.sendStats(id, shardNum: shardNum)
            }
        }

        func tryRemoveToken(_ limiter: RateLimiter, _ id: Int) {
            limiter.removeTokens(1) {err, tokens in
                guard let tokens = tokens, tokens > 0 else {
                    self.bots[shardNum]?.sendResult(false, for: id)

                    return
                }
            }

            self.bots[shardNum]?.sendResult(true, for: id)
        }

        switch (call, id) {
        case let (.getStats, id?):                  try callAll("getStats", complete: _handleStat(id))
        case let (.removeWeatherToken, id?):        tryRemoveToken(weatherLimiter, id)
        case let (.removeWolframToken, id?):        tryRemoveToken(wolframLimiter, id)
        default:                                    throw SwiftBotError.invalidCall
        }
    }

    func sendStats(_ id: Int, shardNum: Int) {
        bots[shardNum]?.sendResult(stats.reduce([:], reduceStats), for: id)

        waitingForStats = false
        stats.removeAll()
    }

    func setupServer() throws {
        print("Starting to listen")

        try masterServer.bind()
        try masterServer.listen()

        print("starting to accept connections")

        acceptConnection()
    }

    func start() {
        for i in 0..<numberOfShards {
            launchBot(withShardNum: i)
        }
    }
}

let manager = try BotManager()

func readAsync() {
    queue.async {
        guard let input = readLine(strippingNewline: true) else { fatalError() }

        if input == "quit" {
            manager.killBots()
        }

        readAsync()
    }
}

print("Type 'quit' to stop")

readAsync()

print("Setting up master server")

try manager.setupServer()

manager.start()

CFRunLoopRun()

