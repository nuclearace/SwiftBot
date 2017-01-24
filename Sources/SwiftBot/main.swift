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

let botProcessLocation = FileManager.default.currentDirectoryPath + "/.build/release/SwiftShard"
let queue = DispatchQueue(label: "Async Read")
let bot = try SwiftBot()

print("Setting up master server")

try bot.setupServer()

func readAsync() {
    queue.async {
        guard let input = readLine(strippingNewline: true) else { fatalError() }
        let command = input.components(separatedBy: " ")

        if command[0] == "quit" {
            bot.shutdown()
        } else if command[0] == "kill", command.count == 3  {
            if command[1] == "all" {
                bot.restart()
            } else if command[1] == "shard", let shardNum = Int(command[2]) {
                bot.kill(shard: shardNum)
            }
        } else if command[0] == "connect", command.count == 3, let shardNum = Int(command[2]) {
            bot.connect(shard: shardNum)
        } else if command[0] == "connect", command.count == 1 {
            bot.connect()
        } else if command[0] == "start" {
            bot.start()
        }

        readAsync()
    }
}

print("Bot is ready for deployment. Type 'start' to launch shards. Type 'quit' to stop")

readAsync()
CFRunLoopRun()
