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

import CryptoSwift
import Dispatch
import Foundation
import Shared
import NIO
import WebSocketKit

enum TokenCall : String {
    case cleverbot = "removeCleverbotToken"
    case weather = "removeWeatherToken"
    case wolfram = "removeWolframToken"
}

class Bot : RemoteCallable {
    let shardNum: Int

    weak var shard: Shard?
    var currentCall = 0
    var socket: WebSocket?
    var waitingCalls = [Int: (Any) throws -> ()]()

    private let shardCount: Int
    private let runloop: EventLoop

    init(shard: Shard, shardNum: Int, shardCount: Int, runloop: EventLoop) {
        self.shard = shard
        self.shardNum = shardNum
        self.shardCount = shardCount
        self.runloop = runloop
    }

    func identify() throws {
//        let headers: [HeaderKey: String] = [
//            HeaderKey("shardCount"): String(self.shardCount),
//            HeaderKey("shard"): String(self.shardNum),
//            HeaderKey("pw"): "\(authToken)\(self.shardNum)".sha3(.sha512),
//        ]
//
//        let url = URL(string: "ws://\(botHost):42343")!
//        let path = url.path.isEmpty ? "/" : url.path
//
//        let future = HTTPClient.webSocket(scheme: .wss,
//                hostname: url.host!,
//                port: url.port,
//                path: path,
//                on: runloop
//        )
//        let doneFuture = runloop.newSucceededFuture(result: ())
//
//        _ = future.then {[weak self] ws -> EventLoopFuture<()> in
//            guard let this = self else { return doneFuture }
//
//            this.socket = ws
//
//            this.socket?.onText {[weak self] ws, string in
//                guard let this = self else { return }
//
//                do {
//                    try this.handleMessage(string)
//                } catch let err {
//                    this.handleTransportError(err)
//                }
//            }
//
//            _ = this.socket?.onClose.do {[weak self] err in
//                guard let this = self else { return }
//
//                print("Shard #\(this.shardNum) disconnected.")
//
//                DispatchQueue.main.async {
//                    this.shard?.setupOrphanedShard()
//                }
//            }
//
//            return doneFuture
//        }
//
//        future.catch({[weak self] error in
//            print("Error \(error)")
//        })
    }

    func handleTransportError(_ error: Error) {
        print("Transport error on shard #\(shardNum) \(error)")

        shard?.setupOrphanedShard()
    }

    func handleRemoteCall(_ method: String, withParams params: [String: Any], id: Int?) throws {
        try shard?.handleRemoteCall(method, withParams: params, id: id)
    }

    func tokenCall(_ type: TokenCall, postCall: @escaping (Bool) -> ()) {
        call(type.rawValue) {canExecute in
            guard let canExecute = canExecute as? Bool else { return postCall(false) }

            postCall(canExecute)
        }
    }
}
