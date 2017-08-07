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
import Sockets
import WebSockets

public enum SwiftBotError : Error {
    case authenticationFailure
    case invalidArgument
    case invalidCall
    case invalidMessage
}

public protocol RemoteCallable : class {
    var currentCall: Int { get set }
    var shardNum: Int { get }
    var socket: WebSocket? { get set }
    var waitingCalls: [Int: (Any) throws -> ()] { get set }

    /**
        Invokes `method` on the target, returns the id of the call. Which will be used to match a result.
    */
    func call(_ method: String, withParams params: [String: Any],
        onComplete complete: ((Any) throws -> ())?) rethrows -> Int
    func handleTransportError(_ error: Error)
    func handleRemoteCall(_ method: String, withParams params: [String: Any], id: Int?) throws
    func sendResult(_ result: Any, for id: Int) throws
}

public extension RemoteCallable {
    @discardableResult
    func call(_ method: String, withParams params: [String: Any] = [:],
            onComplete complete: ((Any) throws -> ())? = nil) -> Int {
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

    func handleMessage(_ message: String) throws {
        guard let json = decodeJSON(message) as? [String: Any] else {
            throw SwiftBotError.invalidMessage
        }

        DispatchQueue.main.async {
            do {
                try self._handleMessage(json: json)
            } catch let err {
                self.handleTransportError(err)
            }
        }
    }

    private func _handleMessage(json: [String: Any]) throws {
        if let method = json["method"] as? String, let params = json["params"] as? [String: Any] {
            try handleRemoteCall(method, withParams: params, id: json["id"] as? Int)
        } else if let result = json["result"], let id = json["id"] as? Int {
            try waitingCalls[id]?(result)
            waitingCalls[id] = nil
        } else {
            throw SwiftBotError.invalidMessage
        }
    }

    func pingSocket() throws {
        try self.socket?.ping()

        DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 30) {
            do {
                try self.pingSocket()
            } catch {
                print("Error pinging")
            }
        }
    }

    private func remoteCall(object: [String: Any]) throws {
        try socket!.send(encodeDataPacket(object))
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

public func encodeDataPacket(_ json: [String: Any]) -> String {
    return encodeJSON(json)!
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
