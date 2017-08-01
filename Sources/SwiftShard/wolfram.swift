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

import Dispatch
import Foundation
import Shared

func getSimpleWolframAnswer(forQuestion question: String) -> String {
    let escapedQuestion = question.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    let url = "http://api.wolframalpha.com/v1/query?appid=\(wolfram)&input=\(escapedQuestion)&output=json"

    guard let json = doWolframRequest(withURL: url),
          let queryresult = json["queryresult"] as? [String: Any],
          let success = queryresult["success"] as? Bool,
          success,
          let pods = queryresult["pods"] as? [[String: Any]] else {
        return "Failed to get from wolfram"
    }

    if let primaryPod = pods.filter({ $0["primary"] as? Bool ?? false }).first,
       let subpods = primaryPod["subpods"] as? [[String: Any]] {
        return "```\(subpods[0]["plaintext"] ?? "LOL IDK")```"
    } else {
        var noAnswerAnswer = "```Wolfram couldn't think of a primary answer, so here's what it said:\n\n"
        var i = 1

        for subpod in pods.flatMap({ $0["subpods"] as? [[String: Any]] ?? [] }) {
            guard i < 6 else { break }
            guard let plaintext = subpod["plaintext"] as? String else { continue }

            noAnswerAnswer += "\(i) | \(plaintext)\n"
            i += 1
        }

        return noAnswerAnswer + "```"
    }
}

private func doWolframRequest(withURL url: String) -> [String: Any]? {
    guard let request = createGetRequest(for: url) else {
        return nil
    }

    let lock = DispatchSemaphore(value: 0)
    var wolframData: [String: Any]?

    getRequestData(for: request) {data in
        guard let data = data else {
            lock.signal()

            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) else {
            lock.signal()

            return
        }

        wolframData = json as? [String: Any]

        lock.signal()
    }

    lock.wait()

    return wolframData
}
