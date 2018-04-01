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
import SwiftDiscord

guard CommandLine.arguments.count >= 3 else { fatalError("Not enough information to start") }

let queue = DispatchQueue(label: "Async Read Shard")
let shardRange = CommandLine.arguments[1].components(separatedBy: "..<").compactMap(Int.init)
let totalShards = Int(CommandLine.arguments[2])!
let fortuneExists = FileManager.default.fileExists(atPath: "/usr/local/bin/fortune")

guard shardRange.count == 2 else { fatalError("Incorrect shard range. Must be n..<m") }

let shardInfo = try DiscordShardInformation(shardRange: shardRange[0]..<shardRange[1], totalShards: totalShards)
let shard = Shard(token: token, shardingInfo: shardInfo)
let jumpstart = CommandLine.arguments.contains("jumpstart") || CommandLine.arguments.contains("j")

func readAsync() {
    queue.async {
        guard let input = readLine(strippingNewline: true) else { fatalError() }
        let command = input.components(separatedBy: " ")

        if command[0] == "die" {
            shard.disconnect()
        } else if command[0] == "jumpstart" {
            shard.connect(id: -1, waitTime: 0)
        } else if command[0] == "tryunorphan" {
            shard.unorphan()
        }

        readAsync()
    }
}

readAsync()

shard.unorphan()

if jumpstart {
    shard.connect(id: -1, waitTime: 0)
}

CFRunLoopRun()
