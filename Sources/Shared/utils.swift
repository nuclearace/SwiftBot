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
import SocksCore

public enum SwiftBotError : Error {
    case authenticationFailure
    case invalidArgument
    case invalidCall
    case invalidMessage
}

public protocol RemoteCallable : class {
    var currentCall: Int { get set }
    var shardNum: Int { get }
    var socket: TCPInternetSocket? { get set }
    var waitingCalls: [Int: (Any) throws -> Void] { get set }

    /**
        Invokes `method` on the target, returns the id of the call. Which will be used to match a result.
    */
    func call(_ method: String, withParams params: [String: Any],
        onComplete complete: ((Any) throws -> Void)?) rethrows -> Int
    func handleTransportError(_ error: Error)
    func handleRemoteCall(_ method: String, withParams params: [String: Any], id: Int?) throws
    func sendResult(_ result: Any, for id: Int) throws
}

public extension RemoteCallable {
    @discardableResult
    func call(_ method: String, withParams params: [String: Any] = [:],
            onComplete complete: ((Any) throws -> Void)? = nil) -> Int {
        waitingCalls[currentCall] = complete

        let callData: [String: Any] = [
            "method": method,
            "params": params,
            "id": currentCall
        ]

        currentCall += 1

        do {
            try remoteCall(object: callData)
        } catch let err {
            handleTransportError(err)
        }

        return currentCall
    }

    func handleMessage() throws {
        let messageData = try getDataFromSocket(socket!)

        guard let stringJSON = String(data: Data(bytes: messageData), encoding: .utf8),
              let json = decodeJSON(stringJSON) as? [String: Any] else { throw SwiftBotError.invalidMessage }

        if let method = json["method"] as? String, let params = json["params"] as? [String: Any] {
            try handleRemoteCall(method, withParams: params, id: json["id"] as? Int)
        } else if let result = json["result"], let id = json["id"] as? Int {
            try waitingCalls[id]?(result)
            waitingCalls[id] = nil
        } else {
            throw SwiftBotError.invalidMessage
        }
    }

    private func remoteCall(object: [String: Any]) throws {
        try socket?.send(data: encodeDataPacket(object))
    }

    func sendResult(_ result: Any, for id: Int) {
        let data: [String: Any] = [
            "result": result,
            "id": id
        ]

        do {
            try remoteCall(object: data)
        } catch {
            print("Error trying to send result \(shardNum)")
        }
    }
}

public func encodeDataPacket(_ json: [String: Any]) -> [UInt8] {
    var packetData: [UInt8]!
    let objectData = encodeJSON(json)!.data(using: .utf8)!

    objectData.withUnsafeBytes {(bytes: UnsafePointer<UInt8>) in
        defer { buf.deallocate() }

        let buf = UnsafeMutableRawBufferPointer.allocate(count: 8)
        let data = Array(UnsafeBufferPointer(start: bytes, count: objectData.count))

        buf.storeBytes(of: Int64(data.count).bigEndian, as: Int64.self)

        packetData = Array(buf) + data
    }

    return packetData
}

public func encodeJSON(_ object: Any) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }

    return String(data: data, encoding: .utf8)
}

public func decodeJSON(_ string: String) -> Any? {
    guard let data = string.data(using: .utf8, allowLossyConversion: false) else { return nil }
    guard let json = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) else { return nil }

    return json
}

public func getDataFromSocket(_ socket: TCPInternetSocket) throws -> [UInt8] {
    let lengthOfMessageBytes = try socket.recv(maxBytes: 8).map(Int.init)

    guard lengthOfMessageBytes.count == 8 else { throw SwiftBotError.invalidMessage }

    let lengthOfMessage =   lengthOfMessageBytes[0] << 56
                          | lengthOfMessageBytes[1] << 48
                          | lengthOfMessageBytes[2] << 40
                          | lengthOfMessageBytes[3] << 32
                          | lengthOfMessageBytes[4] << 24
                          | lengthOfMessageBytes[5] << 16
                          | lengthOfMessageBytes[6] << 8
                          | lengthOfMessageBytes[7]

    return try socket.recv(maxBytes: lengthOfMessage)
}

public func reduceStats(currentStats: [String: Any], otherStats: [String: Any]) -> [String: Any] {
    var mutStats = currentStats

    for (key, stat) in otherStats {
        guard let cur = mutStats[key] else {
            mutStats[key] = stat

            continue
        }

        // Hacky, but trying to switch on the types fucks up, because on macOS JSONSerialization
        // turns numbers into some generic __NSCFNumber type, which can cast to anything.
        switch key {
        case "shards":      fallthrough
        case "name":        continue
        case "orphan":      continue
        case "uptime":      fallthrough
        case "memory":      mutStats[key] = cur as! Double + (stat as! Double)
        default:            mutStats[key] = cur as! Int + (stat as! Int)
        }
    }

    return mutStats
}
