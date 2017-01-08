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

import Foundation

func getForecastData(forLocation location: String) -> [String: Any]? {
    let escapedLocation = location.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
    let stringUrl = "https://api.wunderground.com/api/\(weather)/conditions/forecast/q/\(escapedLocation).json"
    let weatherUndergroundData = getWeatherUndergroundData(withURL: stringUrl) as? [String: Any]

    return weatherUndergroundData
}

func getWeatherData(forLocation location: String) -> [String: Any]? {
    let escapedLocation = location.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
    let stringUrl = "https://api.wunderground.com/api/\(weather)/conditions/q/\(escapedLocation).json"
    let weatherUndergroundData = getWeatherUndergroundData(withURL: stringUrl) as? [String: Any]

    return weatherUndergroundData?["current_observation"] as? [String: Any]
}

private func getWeatherUndergroundData(withURL url: String) -> Any? {
    guard let request = createGetRequest(for: url) else {
        return nil
    }

    let lock = DispatchSemaphore(value: 0)
    var weatherData: Any?

    getRequestData(for: request) {data in
        guard let data = data else {
            lock.signal()

            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) else {
            lock.signal()

            return
        }

        weatherData = json

        lock.signal()
    }

    lock.wait()

    return weatherData
}