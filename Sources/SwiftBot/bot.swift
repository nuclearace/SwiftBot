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

import CryptoSwift
import Dispatch
import Foundation
import HTTP
import Shared
import Sockets
import SwiftRateLimiter
import WebSockets

enum BotCall : String {
    case getStats
    case ping
    case removeCleverbotToken
    case removeWeatherToken
    case removeWolframToken
}

class SwiftBot : Responder {
    let acceptQueue = DispatchQueue(label: "Accept Queue")
    let cleverbotLimiter = RateLimiter(tokensPerInterval: 30, interval: "minute", firesImmediatly: true)
    let masterServer: TCPServer
    let startTime = Date()
    let weatherLimiter = RateLimiter(tokensPerInterval: 10, interval: "minute", firesImmediatly: true)
    let wolframLimiter = RateLimiter(tokensPerInterval: 67, interval: "day", firesImmediatly: true)

    var authenticatedShards = 0
    var shards = [Int: Shard]()
    var connected = false
    var killingShards = false
    var shutdownShards = 0
    var stats = [[String: Any]]()
    var waitingForStats = false

    init() throws {
        masterServer = try TCPServer(TCPInternetSocket(InternetAddress(hostname: botHost, port: 42343)))
    }

    func attachSocketToBot(_ socket: WebSocket, shard: Int) throws {
        if let shard = shards[shard] {
            print("Add socket to shard #\(shard.shardNum)")

            try shard.attachSocket(socket)
        } else {
            shards[shard] = try Shard(manager: self, shardNum: shard, socket: socket)
        }

        shards[shard]?.call("setup", withParams: ["heartbeatInterval": 50])

        authenticatedShards += 1

        if authenticatedShards == numberOfShards {
            print("Shards are launched, type 'connect' to start them. Or 'connect shard \(shard)' to launch just this shard")
        } else {
            print("Shard #\(shard) is identified, type 'connect shard \(shard)' to launch it")
        }
    }

    func callAll(_ method: String, params: [String: Any] = [:], complete: ((Any) throws -> ())? = nil) {
        for (_, shard) in shards {
            shard.call(method, withParams: params, onComplete: complete)
        }
    }

    func connect() {
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

    func launch(shard: Int) {
        let shardProccess = Process()

        shardProccess.launchPath = botProcessLocation
        shardProccess.arguments = ["\(shard)", "\(numberOfShards)"]
        shardProccess.terminationHandler = {process in
            print("Shard #\(shard) died")

            guard self.killingShards else {
                print("Restarting it")

                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 5) {
                    self.launch(shard: shard)
                }

                return
            }

            self.shutdownShards += 1

            if self.shutdownShards == self.shards.count {
                exit(0)
            }
        }

        shardProccess.launch()

        shards[shard] = try! Shard(manager: self, shardNum: shard)
    }

    private func handleStat(callNum: Int, shardNum: Int) -> (Any) throws -> () {
        waitingForStats = true

        return {stat in
            guard self.waitingForStats, let stat = stat as? [String: Any] else {
                throw SwiftBotError.invalidArgument
            }

            self.stats.append(stat)

            guard self.stats.count == numberOfShards else { return }

            self.sendStats(callNum, shardNum: shardNum)
        }
    }

    func handleRemoteCall(_ method: String, withParams params: [String: Any], id: Int?, shardNum: Int) throws {
        guard let call = BotCall(rawValue: method) else { throw SwiftBotError.invalidCall }

        switch (call, id) {
        case let (.getStats, id?):
            callAll("getStats", complete: handleStat(callNum: id, shardNum: shardNum))
        case let(.ping, id?):
            pong(to: shardNum, callNum: id)
        case let (.removeCleverbotToken, id?):
            tryRemoveToken(from: cleverbotLimiter, callNum: id, shardNum: shardNum)
        case let (.removeWeatherToken, id?):
            tryRemoveToken(from: weatherLimiter, callNum: id, shardNum: shardNum)
        case let (.removeWolframToken, id?):
            tryRemoveToken(from: wolframLimiter, callNum: id, shardNum: shardNum)
        default:
            throw SwiftBotError.invalidCall
        }
    }

    func pong(to shardNum: Int, callNum: Int) {
        shards[shardNum]?.sendResult(true, for: callNum)
    }

    func respond(to request: Request) throws -> Response {
        print("Got new connection\nauthenticating")

        // Before a bot starts up, it should identify itself
        guard let shard = Int(request.headers["shard"]!),
              let pw = request.headers["pw"], pw == "\(authToken)\(shard)".sha3(.sha512) else {
            throw SwiftBotError.authenticationFailure
        }

        return try request.upgradeToWebSocket {ws in
            print("Upgraded shard #\(shard) socket to WebSockets")

            try self.attachSocketToBot(ws, shard: shard)
        }
    }

    func restart() {
        connected = false
        authenticatedShards = 0

        callAll("die")
    }

    func sendStats(_ id: Int, shardNum: Int) {
        shards[shardNum]?.sendResult(stats.reduce(["uptime": Date().timeIntervalSince(startTime)], reduceStats),
                                     for: id)

        waitingForStats = false
        stats.removeAll()
    }

    func setupServer() throws {
        print("Starting to listen")

        try masterServer.start(self) {err in
            print(err)
        }
    }

    func shutdown() {
        killingShards = true

        callAll("die")
    }

    func start() {
        for i in 0..<numberOfShards {
            launch(shard: i)
        }
    }

    private func tryRemoveToken(from limiter: RateLimiter, callNum: Int, shardNum: Int) {
        limiter.removeTokens(1) {err, tokens in
            guard let tokens = tokens, tokens > 0 else {
                self.shards[shardNum]?.sendResult(false, for: callNum)

                return
            }

            self.shards[shardNum]?.sendResult(true, for: callNum)
        }
    }

}
