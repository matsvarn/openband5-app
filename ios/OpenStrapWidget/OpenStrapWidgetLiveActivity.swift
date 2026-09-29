import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// Codable shape mirrors ios/LiveActivityBridge.swift.
struct OpenStrapWidgetAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var hr: Int
    var zone: Int
    var strain: Double?
    var calories: Int?
    var maxHr: Int
    var rhr: Int
  }
  var sessionName: String
  var startedAt: Date
  var targetKcal: Int
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
                    hr: state.hr, zone: state.zone, strain: state.strain,
                    maxHr: state.maxHr, signal: "Signal nicht bestätigt")
}

struct OpenStrapWidgetLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: OpenStrapWidgetAttributes.self) { context in
      G3LiveLockCard(data: displayData(context), end: Button(intent: EndSessionIntent()) {
        Label("Beenden", systemImage: "stop")
          .font(.system(size: 13, weight: .semibold))
          .frame(minWidth: 44, minHeight: 44)
          .padding(.horizontal, 8)
      }.buttonStyle(.bordered))
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
          G3LiveExpanded(data: data, end: Button(intent: EndSessionIntent()) {
            Label("Beenden", systemImage: "stop")
              .frame(minWidth: 44, minHeight: 44)
          }.buttonStyle(.bordered))
        }
      } compactLeading: {
        Text(data.pulse).font(.system(size: 14, weight: .bold).monospacedDigit())
      } compactTrailing: {
        Text(data.startedAt, style: .timer)
          .font(.system(size: 13, weight: .bold).monospacedDigit())
      } minimal: {
        Text(data.pulse).font(.system(size: 13, weight: .bold).monospacedDigit())
      }.keylineTint(.white)
    }
  }
}
