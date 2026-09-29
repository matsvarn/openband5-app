import SwiftUI
import WidgetKit

struct SleepEntry: TimelineEntry {
  var date: Date
  let snap: SW.Snapshot
  static let placeholder = SleepEntry(date: Date(), snap: .placeholder)
}

struct SleepProvider: TimelineProvider {
  func placeholder(in context: Context) -> SleepEntry { .placeholder }

  func getSnapshot(in context: Context, completion: @escaping (SleepEntry) -> Void) {
    completion(context.isPreview ? .placeholder : SleepEntry(date: Date(), snap: SW.read()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SleepEntry>) -> Void) {
    let snap = SW.read()
    completion(SW.timeline(snap, Date()) { SleepEntry(date: $0, snap: snap) })
  }
}

struct OpenStrapSleepWidgetEntryView: View {
  @Environment(\.widgetFamily) var family
  var entry: SleepEntry

  @ViewBuilder var body: some View {
    switch family {
    case .systemSmall: G3SleepSmall(snap: entry.snap, date: entry.date)
    case .accessoryCircular:
      Text(G3Widget.status(entry.snap, entry.date) == .current
           ? G3Widget.time(entry.snap.sleepMinutes) : "—").widgetAccentable()
    case .accessoryRectangular, .accessoryInline:
      Text("Schlaf \(G3Widget.status(entry.snap, entry.date) == .current ? G3Widget.time(entry.snap.sleepMinutes) : "—")")
        .widgetAccentable()
    default: G3SleepSmall(snap: entry.snap, date: entry.date)
    }
  }
}

struct OpenStrapSleepWidget: Widget {
  let kind: String = "OpenStrapSleepWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: SleepProvider()) { entry in
      OpenStrapSleepWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("OpenBand 5 · Schlaf")
    .description("Schlafdauer und gespeichertes Schlafziel.")
    .supportedFamilies([.systemSmall, .accessoryCircular,
                        .accessoryRectangular, .accessoryInline])
  }
}
