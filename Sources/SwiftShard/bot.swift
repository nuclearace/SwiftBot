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
import Foundation
import Shared
import SocksCore

enum TokenCall : String {
    case cleverbot = "removeCleverbotToken"
    case weather = "removeWeatherToken"
    case wolfram = "removeWolframToken"
}

class Bot : RemoteCallable {
    let shardNum: Int

    weak var shard: Shard?
    var currentCall = 0
    var socket: TCPInternetSocket?
    var waitingCalls = [Int: (Any) throws -> Void]()

    init(shard: Shard, shardNum: Int) {
        self.shard = shard
        self.shardNum = shardNum
    }

    func identify() throws {
        socket = try TCPInternetSocket(address: InternetAddress(hostname: botHost, port: 42343))
        try socket?.connect()

        let identifyData: [String: Any] = [
            "shard": shardNum,
            "pw": "\(authToken)\(shardNum)".sha3(.sha512)
        ]

        try socket?.send(data: encodeDataPacket(identifyData))
        try socket?.startWatching(on: DispatchQueue.main) {
            do {
               try self.handleMessage()
            } catch let err {
                self.handleTransportError(err)
            }
        }
    }

    func handleTransportError(_ error: Error) {
        print("Transport error on shard #\(shardNum) \(error)")

        shard?.setupOrphanedShard()
    }

    func handleRemoteCall(_ method: String, withParams params: [String: Any], id: Int?) throws {
        try shard?.handleRemoteCall(method, withParams: params, id: id)
    }

    func tokenCall(_ type: TokenCall, postCall: @escaping (Bool) -> Void) {
        call(type.rawValue) {canExecute in
            guard let canExecute = canExecute as? Bool else { return postCall(false) }

            postCall(canExecute)
        }
    }
}
