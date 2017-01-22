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

class Bot : RemoteCallable {
    let shardNum: Int

    weak var shard: Shard?
    var currentCall = 0
    var socket: TCPInternetSocket?
    var waitingCalls = [Int: (Any) throws -> Void]()

    init(shard: Shard, shardNum: Int) throws {
        self.shard = shard
        self.shardNum = shardNum
        socket = try TCPInternetSocket(address: InternetAddress(hostname: "127.0.0.1", port: 42343))

        try socket?.connect()
    }

    func identify() throws {
        let identifyData: [String: Any] = [
            "shard": shardNum,
            "pw": "\(authToken)\(shardNum)".sha512()
        ]

        try socket?.send(data: encodeDataPacket(identifyData))
        try socket?.startWatching(on: DispatchQueue.main) {
            do {
               try self.handleMessage()
            } catch {
                print("Error reading on bot \(self.shardNum)")
            }
        }
    }

    func handleRemoteCall(_ method: String, withParams params: [String: Any], id: Int?) throws {
        try shard?.handleRemoteCall(method, withParams: params, id: id)
    }
}
