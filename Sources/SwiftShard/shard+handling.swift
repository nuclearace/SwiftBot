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
import SwiftDiscord

extension Shard : CommandHandler {
    func handleBrutal(with arguments: [String], message: DiscordMessage) {
        brutalizeImage(options: arguments, channel: message.channel!)
    }

    func handleCommand(_ command: String, with arguments: [String], message: DiscordMessage) {
        print("got command \(command)")

        if let guild = message.channel?.guild, ignoreGuilds.contains(guild.id),
                !userOverrides.contains(message.author.id) {
            print("Ignoring this guild")

            return
        }

        guard let command = Command(rawValue: command.lowercased()) else { return }

        switch command {
        case .roles:
            handleMyRoles(with: arguments, message: message)
        case .join where arguments.count > 0:
            handleJoin(with: arguments, message: message)
        case .leave:
            handleLeave(with: arguments, message: message)
        case .is:
            handleIs(with: arguments, message: message)
        case .youtube where arguments.count == 1:
            handleYoutube(with: arguments, message: message)
        case .fortune:
            handleFortune(with: arguments, message: message)
        case .skip:
            handleSkip(with: arguments, message: message)
        case .brutal where arguments.count > 0:
            handleBrutal(with: arguments, message: message)
        case .topic where arguments.count > 0:
            handleTopic(with: arguments, message: message)
        case .stats:
            handleStats(with: arguments, message: message)
        case .weather where arguments.count > 0:
            handleWeather(with: arguments, message: message)
        case .wolfram where arguments.count > 0:
            handleWolfram(with: arguments, message: message)
        case .forecast where arguments.count > 0:
            handleForecast(with: arguments, message: message)
        default:
            print("Bad command \(command)")
        }
    }

    func handleFortune(with arguments: [String], message: DiscordMessage) {
        message.channel?.sendMessage(getFortune())
    }

    func handleIs(with arguments: [String], message: DiscordMessage) {
        guard let guild = message.channel?.guild else {
            message.channel?.sendMessage("Is this a guild channel m8?")

            return
        }

        // Avoid evaluating every member.
        let members = guild.members.lazy.map({ $0.value })
        let randomNum = Int(arc4random_uniform(UInt32(guild.members.count - 1)))
        let randomIndex = members.index(members.startIndex, offsetBy: randomNum)
        let randomMember = members[randomIndex]
        let name = randomMember.nick ?? randomMember.user.username

        message.channel?.sendMessage("\(name) is \(arguments.joined(separator: " "))")
    }

    func handleJoin(with arguments: [String], message: DiscordMessage) {
        guard let channel = findChannelFromName(arguments.joined(separator: " "),
                in: client.guildForChannel(message.channelId)) else {
            message.channel?.sendMessage("That doesn't look like a channel in this guild.")

            return
        }

        guard channel.type == .voice else {
            message.channel?.sendMessage("That's not a voice channel.")

            return
        }

        youtubeQueue[message.channel!.guild!.id] = []

        client.joinVoiceChannel(channel.id)
    }

    func handleLeave(with arguments: [String], message: DiscordMessage) {
        client.leaveVoiceChannel(onGuild: message.channel?.guild?.id ?? "")
    }

    func handleForecast(with arguments: [String], message: DiscordMessage) {
        let tomorrow = arguments.last == "tomorrow"
        let location: String

        if tomorrow {
            location = arguments.dropLast().joined(separator: " ")
        } else {
            location = arguments.joined(separator: " ")
        }

        removeWeatherToken {canWeather in
            guard canWeather else {
                message.channel?.sendMessage("Weather is rate limited right now!")

                return
            }

            guard let forecast = getForecastData(forLocation: location),
                  let embed = createForecastEmbed(withForecastData: forecast, tomorrow: tomorrow) else {
                message.channel?.sendMessage("Something went wrong with getting the forecast data")

                return
            }

            message.channel?.sendMessage("", embed: embed)
        }
    }

    func handleMyRoles(with arguments: [String], message: DiscordMessage) {
        let roles = getRolesForUser(message.author, on: message.channelId)

        message.channel?.sendMessage("Your roles: \(roles.map({ $0.name }))")
    }

    func handleSkip(with arguments: [String], message: DiscordMessage) {
        if youtube.isRunning {
            youtube.terminate()
        }

        client.voiceEngines[message.channel?.guild?.id ?? ""]?.requestNewEncoder()
    }

    func handleStats(with arguments: [String], message: DiscordMessage) {
        getStats {stats in
            message.channel?.sendMessage("", embed: createFormatMessage(withStats: stats))
        }
    }

    func handleTopic(with arguments: [String], message: DiscordMessage) {
        message.channel?.modifyChannel(options: [.topic(arguments.joined(separator: " "))])
    }

    func handleWeather(with arguments: [String], message: DiscordMessage) {
        removeWeatherToken {canWeather in
            guard canWeather else {
                message.channel?.sendMessage("Weather is rate limited right now!")

                return
            }

            guard let weatherData = getWeatherData(forLocation: arguments.joined(separator: " ")),
                  let embed = createWeatherEmbed(withWeatherData: weatherData) else {
                message.channel?.sendMessage("Something went wrong with getting the weather data")

                return
            }

            message.channel?.sendMessage("", embed: embed)
        }
    }

    func handleWolfram(with arguments: [String], message: DiscordMessage) {
        removeWolframToken {canWolfram in
            guard canWolfram else {
                message.channel?.sendMessage("Wolfram is rate limited right now!")

                return
            }

            message.channel?.sendMessage(getSimpleWolframAnswer(forQuestion: arguments.joined(separator: "+")))
        }
    }

    func handleYoutube(with arguments: [String], message: DiscordMessage) {
        message.channel?.sendMessage(playYoutube(channelId: message.channelId, link: arguments[0]))
    }
}
