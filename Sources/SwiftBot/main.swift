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
import CryptoSwift
import Dispatch
import Foundation
import Shared
import SocksCore
import SwiftRateLimiter

#if os(Linux)
typealias Process = Task
#endif

let botProcessLocation = FileManager.default.currentDirectoryPath + "/.build/release/SwiftShard"
let weatherLimiter = RateLimiter(tokensPerInterval: 10, interval: "minute", firesImmediatly: true)
let wolframLimiter = RateLimiter(tokensPerInterval: 67, interval: "day", firesImmediatly: true)

let queue = DispatchQueue(label: "Async Read")

enum BotCall : String {
    case getStats
    case removeWeatherToken
    case removeWolframToken
}

class ShardProcess : RemoteCallable {
    let process: Process
    let shardNum: Int

    weak var manager: SwiftBot?
    var currentCall = 0
    var socket: TCPInternetSocket?
    var waitingCalls = [Int: (Any) throws -> Void]()

    init(process: Process, manager: SwiftBot, shardNum: Int) {
        self.process = process
        self.manager = manager
        self.shardNum = shardNum
    }

    func attachSocket(_ socket: TCPInternetSocket) throws {
        self.socket = socket

        try socket.startWatching(on: DispatchQueue.main) {
            print("Shard #\(self.shardNum) has something waiting")

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

class SwiftBot {
    let acceptQueue = DispatchQueue(label: "Accept Queue")
    let masterServer: TCPInternetSocket

    var authenticatedShards = 0
    var shards = [Int: ShardProcess]()
    var connected = false
    var killingShards = false
    var shutdownShards = 0
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
            } catch SwiftBotError.authenticationFailure {
                print("Shard failed to authenticate")

                self.acceptConnection()
            } catch let err {
                // Unknown error, assume the worst.
                print("Error accepting connection: \(err)")
                self.shutdown()
            }
        }
    }

    func attachSocketToBot(_ socket: TCPInternetSocket) throws {
        print("Got new connection")

        // Before a bot starts up, it should identify itself
        guard let stringJSON = String(data: Data(bytes: try getDataFromSocket(socket)), encoding: .utf8),
              let json = decodeJSON(stringJSON) as? [String: Any],
              let shard = json["shard"] as? Int,
              let pw = json["pw"] as? String,
              pw == "\(authToken)\(shard)".sha512() else {
                try socket.close()
                throw SwiftBotError.authenticationFailure
            }

        print("Shard #\(shard) identified")

        try shards[shard]?.attachSocket(socket)

        authenticatedShards += 1

        if !connected {
            connect()
        } else {
            connect(shard: shard)
        }
    }

    func callAll(_ method: String, params: [String: Any] = [:], complete: ((Any) throws -> Void)? = nil) {
        for (_, shard) in shards {
            shard.call(method, withParams: params, onComplete: complete)
        }
    }

    func connect() {
        guard authenticatedShards == numberOfShards, !connected else { return }

        print("Telling all shards to connect")

        connected = true
        var wait = 0

        for i in 0..<numberOfShards {
            connect(shard: i, wait: wait)

            wait += 5
        }
    }

    func connect(shard: Int, wait: Int = 3) {
        print("Commanding shard #\(shard) to connect")

        shards[shard]?.call("connect", withParams: ["wait": wait]) {success in
            guard let success = success as? Bool else { return }

            print("Shard #\(shard) connected: \(success)")
        }
    }

    func kill(shard: Int) {
        authenticatedShards -= 1

        print("Commanding shard #\(shard) to die")

        shards[shard]?.call("die")
    }

    func launchShard(_ shardNum: Int) {
        let shardProccess = Process()

        shardProccess.launchPath = botProcessLocation
        shardProccess.arguments = ["\(shardNum)", "\(numberOfShards)"]
        shardProccess.terminationHandler = {process in
            print("Shard #\(shardNum) died")

            guard self.killingShards else {
                print("Restarting it")

                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 5) {
                    self.launchShard(shardNum)
                }

                return
            }

            self.shutdownShards += 1

            if self.shutdownShards == self.shards.count {
                exit(0)
            }
        }

        shardProccess.launch()

        shards[shardNum] = ShardProcess(process: shardProccess,
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
                    self.shards[shardNum]?.sendResult(false, for: id)

                    return
                }

                self.shards[shardNum]?.sendResult(true, for: id)
            }
        }

        switch (call, id) {
        case let (.getStats, id?):                  callAll("getStats", complete: _handleStat(id))
        case let (.removeWeatherToken, id?):        tryRemoveToken(weatherLimiter, id)
        case let (.removeWolframToken, id?):        tryRemoveToken(wolframLimiter, id)
        default:                                    throw SwiftBotError.invalidCall
        }
    }

    func restart() {
        connected = false
        authenticatedShards = 0

        callAll("die")
    }

    func sendStats(_ id: Int, shardNum: Int) {
        shards[shardNum]?.sendResult(stats.reduce([:], reduceStats), for: id)

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

    func shutdown() {
        killingShards = true

        do {
            callAll("die")
            try masterServer.close()
        } catch {
            print("couldn't close server")
        }
    }

    func start() {
        for i in 0..<numberOfShards {
            launchShard(i)
        }
    }
}

let manager = try SwiftBot()

func readAsync() {
    queue.async {
        guard let input = readLine(strippingNewline: true) else { fatalError() }
        let command = input.components(separatedBy: " ")

        if command[0] == "quit" {
            manager.shutdown()
        } else if command[0] == "kill", command.count == 3  {
            if command[1] == "all" {
                manager.restart()
            } else if command[1] == "shard", let shardNum = Int(command[2]) {
                manager.kill(shard: shardNum)
            }
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

