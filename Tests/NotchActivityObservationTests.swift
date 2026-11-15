// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine

/// Executes the production subscription switch against independent publishers.
enum NotchActivityObservationTests {
    enum Music {}
    enum Timer {}
    enum Other {}
    final class Source<Tag>: ObservableObject {
        static var shared: Source<Tag> { Sources.value(Tag.self) }
        let objectWillChange = ObservableObjectPublisher()
    }
    private enum Sources {
        static var values: [ObjectIdentifier: Any] = [:]
        static func value<Tag>(_ type: Tag.Type) -> Source<Tag> {
            let id = ObjectIdentifier(type)
            if let source = values[id] as? Source<Tag> { return source }
            let source = Source<Tag>()
            values[id] = source
            return source
        }
    }
    typealias NotchMusicService = Source<Music>
    typealias NotchTimerService = Source<Timer>
    typealias NotchDownloadService = Source<Other>
    typealias AgentUsageService = Source<Other>
    typealias NotchWatchService = Source<Other>
    typealias KeepAwakeManager = Source<Other>
    typealias NotchCalendarService = Source<Other>
    typealias NotchShortcutsService = Source<Other>
    typealias NotchCallService = Source<Other>

    static func run(_ suite: TestSuite) {
        var musicChanges = 0, timerChanges = 0
        var music: Observation? = Observation(.music)
        let timer = Observation(.timer)
        let subscriptions = [music!.objectWillChange.sink { musicChanges += 1 },
                             timer.objectWillChange.sink { timerChanges += 1 }]
        for _ in 0..<120 { NotchMusicService.shared.objectWillChange.send() }
        suite.expect(musicChanges == 120 && timerChanges == 0,
                     "playback bursts update the music pill without invalidating other activity viewports")
        NotchTimerService.shared.objectWillChange.send()
        suite.expect(musicChanges == 120 && timerChanges == 1,
                     "timer ticks reach their own card without remeasuring the music pill")
        weak var released = music
        music = nil
        suite.expect(released == nil, "removing an activity releases its subscription")
        withExtendedLifetime(subscriptions) {}
    }
}
