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

import Dispatch
import Foundation
import Shared
import WebSocketKit

class Shard : RemoteCallable {
    let shardCount: Int
    let shardNum: Int

    weak var bot: SwiftBot?
    var currentCall = 0
    var socket: WebSocket?
    var waitingCalls = [Int: (Any) throws -> ()]()

    init(manager: SwiftBot, shardNum: Int, shardCount: Int, socket: WebSocket? = nil) throws {
        self.shardCount = shardCount
        self.bot = manager
        self.shardNum = shardNum

        if socket != nil {
            try attachSocket(socket!)
        }
    }

    func attachSocket(_ socket: WebSocket) throws {
        self.socket = socket

        try self.pingSocket()

        self.socket?.onText {[weak self] ws, text in
            guard let this = self else { return }

            do {
                try this.handleMessage(text)
            } catch let err {
                this.handleTransportError(err)
            }
        }

        self.socket?.onClose.whenComplete {[weak self] _ in
            guard let this = self else { return }

            print("Shard #\(this.shardNum) disconnected")

            DispatchQueue.main.async {
                this.bot?.authenticatedShards -= this.shardCount
                this.bot?.shards[this.shardNum] = nil
            }
        }
    }

    func handleTransportError(_ error: Error) {
        print("Transport error on shard #\(shardNum) \(error)")
    }

    func handleRemoteCall(_ method: String, withParams params: [String: Any], id: Int?) throws {
        try bot?.handleRemoteCall(method, withParams: params, id: id, shardNum: shardNum)
    }
}
