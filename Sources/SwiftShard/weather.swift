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

func getForecastData(forLocation location: String, callback: @escaping ([String: Any]?) -> ()) {
    let escapedLocation = location.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
    let stringUrl = "https://api.wunderground.com/api/\(weather)/conditions/forecast/q/\(escapedLocation).json"

    getWeatherUndergroundData(withURL: stringUrl, callback: {data in
        callback(data as? [String: Any])
    })
}

func getWeatherData(forLocation location: String, callback: @escaping ([String: Any]?) -> ()) {
    let escapedLocation = location.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
    let stringUrl = "https://api.wunderground.com/api/\(weather)/conditions/q/\(escapedLocation).json"

    getWeatherUndergroundData(withURL: stringUrl, callback: {data in
        let weatherUndergroundData = data as? [String: Any]

        callback(weatherUndergroundData?["current_observation"] as? [String: Any])
    })
}

private func getWeatherUndergroundData(withURL url: String, callback: @escaping (Any?) -> ()) {
    guard let request = createGetRequest(for: url) else {
        return callback(nil)
    }

    getRequestData(for: request) {data in
        guard let data = data else {
            return callback(nil)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) else {
            callback(nil)

            return
        }

        callback(json)
    }
}
