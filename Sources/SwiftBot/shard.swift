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

import Foundation
import Shared
import SocksCore

class Shard : RemoteCallable {
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
