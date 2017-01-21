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

#if os(Linux)
typealias Process = Task
#endif

typealias BotProcess = (process: Process, pipe: Pipe)

let token = "Bot mysupersecrettoken"
let weather = ""
let wolfram = ""
let numberOfShards = 2
let botProcessLocation = FileManager.default.currentDirectoryPath + "/.build/release/SwiftBot"
let botId = UUID()

let queue = DispatchQueue(label: "Async Read")
var killingBots = false
var bots = [Int: BotProcess]()
var shutdownBots = 0

#if os(macOS)
class BotManager : NSObject {
    let center = DistributedNotificationCenter.default()

    deinit {
        center.removeObserver(self)
    }

    func killBots() {
        center.post(name: NSNotification.Name("die"), object: nil)
    }
}

let manager = BotManager()
#endif

func killBots() {
    killingBots = true

    #if os(macOS)
    manager.killBots()
    #else
    for (_, botProcess) in bots {
        botProcess.pipe.fileHandleForWriting.write("quit\n".data(using: .utf8)!)
    }
    #endif
}

func readAsync() {
    queue.async {
        guard let input = readLine(strippingNewline: true) else { fatalError() }

        if input == "quit" {
            killBots()
        }

        readAsync()
    }
}

func launchBot(withShardNum shardNum: Int) {
    let botProcess = Process()
    let pipe = Pipe()

    botProcess.launchPath = botProcessLocation
    botProcess.standardInput = pipe
    botProcess.arguments = [token, "\(shardNum)", "\(numberOfShards)", weather, wolfram]
    botProcess.terminationHandler = {process in
        print("Bot \(shardNum) died")

        guard killingBots else {
            print("Restarting it")

            launchBot(withShardNum: shardNum)

            return
        }

        shutdownBots += 1

        if shutdownBots == bots.count {
            exit(0)
        }
    }

    botProcess.launch()

    bots[shardNum] = (botProcess, pipe)
}

print("Type 'quit' to stop")

readAsync()

for i in 0..<numberOfShards {
    launchBot(withShardNum: i)
}

CFRunLoopRun()

