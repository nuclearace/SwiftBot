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

typealias BotProcess = (process: Process, socket: TCPInternetSocket?)

let token = "Bot mysupersecrettoken"
let weather = ""
let wolfram = ""
let numberOfShards = 2
let botProcessLocation = FileManager.default.currentDirectoryPath + "/.build/release/SwiftBot"
let botId = UUID()
let weatherLimiter = RateLimiter(tokensPerInterval: 10, interval: "minute")
let wolframLimiter = RateLimiter(tokensPerInterval: 67, interval: "day")

let queue = DispatchQueue(label: "Async Read")

enum BotEvent : String {
    case requestStats
    case stat
}

class BotManager {
    let acceptQueue = DispatchQueue(label: "Accept Queue")
    let botQueue = DispatchQueue(label: "Bot Queue")
    let masterServer: TCPInternetSocket

    var bots = [Int: BotProcess]()
    var killingBots = false
    var shutdownBots = 0

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

        print("Bot \(botNum) identified")

        bots[Int(botNum)]?.socket = socket

        try socket.startWatching(on: DispatchQueue.main) {
            print("Bot \(botNum) has something waiting")

            do {
               try self.handleBotEvent(socket: socket)
            } catch {
                print("Error reading from bot \(botNum)")
            }
        }
    }

    func broadcast(event: String, params: [String: Any]) throws {
        let eventData = encodeDataPacket([
            "method": event,
            "params": params,
            "id": -1
        ])

        for (_, bot) in bots {
            print("sending to bot")
            try bot.socket?.send(data: eventData)
        }
    }

    func killBots() {
        killingBots = true


        do {
            try broadcast(event: "die", params: [:])
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

                // self.launchBot(withShardNum: shardNum)

                return
            }

            self.shutdownBots += 1

            if self.shutdownBots == self.bots.count {
                exit(0)
            }
        }

        botProcess.launch()

        bots[shardNum] = (botProcess, nil)
    }

    func handleBotEvent(socket: TCPInternetSocket) throws {
        let messageData = try getDataFromSocket(socket)

        guard let stringJSON = String(data: Data(bytes: messageData), encoding: .utf8),
              let json = decodeJSON(stringJSON) as? [String: Any],
              let eventString = json["method"] as? String,
              let event = BotEvent(rawValue: eventString) else { return }

        switch event {
        case .requestStats:     try broadcast(event: "getStats", params: [:])
        case .stat:             try handleStat(json)
        }
    }

    func handleStat(_ json: [String: Any]) throws {
        guard let stat = json["params"] as? [String: Any] else { return }

        try broadcast(event: "stat", params: stat)
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

