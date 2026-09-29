import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// Codable shape mirrors ios/LiveActivityBridge.swift.
struct OpenStrapWidgetAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var hr: Int?
    var hrSampleAt: Date?
    var signal: String?
    var zone: Int?
    var zoneLowPct: Double?
    var zoneHighPct: Double?
    var zoneBasis: String?
    var zoneBasisBpm: Int?
    var elapsedSeconds: Int?
    var paused: Bool?
    var strain: Double?
  }
  var sessionName: String
  var startedAt: Date
}

@available(iOSApplicationExtension 17.0, *)
struct EndSessionIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Einheit beenden"
  func perform() async throws -> some IntentResult {
    UserDefaults(suiteName: AppGroup.identifier)?.set(true, forKey: "end_session")
    for activity in Activity<OpenStrapWidgetAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    return .result()
  }
}

private func displayData(_ context: ActivityViewContext<OpenStrapWidgetAttributes>) -> G3LiveData {
  let state = context.state
  return G3LiveData(name: context.attributes.sessionName,
                    startedAt: context.attributes.startedAt,
                    hr: state.hr, hrSampleAt: state.hrSampleAt,
                    signal: state.signal, zone: state.zone,
                    zoneLowPct: state.zoneLowPct, zoneHighPct: state.zoneHighPct,
                    zoneBasis: state.zoneBasis, zoneBasisBpm: state.zoneBasisBpm,
                    elapsedSeconds: state.elapsedSeconds, paused: state.paused,
                    strain: state.strain)
}

struct OpenStrapWidgetLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: OpenStrapWidgetAttributes.self) { context in
      TimelineView(.periodic(from: .now, by: 1)) { timeline in
        G3LiveLockCard(data: displayData(context), now: timeline.date,
                       end: Button(intent: EndSessionIntent()) {
          Label("Beenden", systemImage: "stop")
            .font(.system(size: 13, weight: .semibold))
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 8)
        }.buttonStyle(.bordered))
      }
    } dynamicIsland: { context in
      let data = displayData(context)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          EmptyView()
        }
        DynamicIslandExpandedRegion(.trailing) {
          EmptyView()
        }
        DynamicIslandExpandedRegion(.bottom) {
          TimelineView(.periodic(from: .now, by: 1)) { timeline in
            G3LiveExpanded(data: data, now: timeline.date,
                           end: Button(intent: EndSessionIntent()) {
              Label("Beenden", systemImage: "stop")
                .frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.bordered))
          }
        }
      } compactLeading: {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
          Text(data.pulse(at: timeline.date))
            .font(.system(size: 14, weight: .bold).monospacedDigit())
        }
      } compactTrailing: {
        G3LiveDuration(data: data, size: 13)
      } minimal: {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
          Text(data.pulse(at: timeline.date))
            .font(.system(size: 13, weight: .bold).monospacedDigit())
        }
      }.keylineTint(.white)
    }
  }
}
