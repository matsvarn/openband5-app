import SwiftUI
import WidgetKit

struct OpenStrapEntry: TimelineEntry {
  var date: Date
  let snap: SW.Snapshot
  static let placeholder = OpenStrapEntry(date: Date(), snap: .placeholder)
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> OpenStrapEntry { .placeholder }

  func getSnapshot(in context: Context, completion: @escaping (OpenStrapEntry) -> Void) {
    completion(context.isPreview ? .placeholder : OpenStrapEntry(date: Date(), snap: SW.read()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<OpenStrapEntry>) -> Void) {
    let snap = SW.read()
    completion(SW.timeline(snap, Date()) { OpenStrapEntry(date: $0, snap: snap) })
  }
}

struct OpenStrapWidgetEntryView: View {
  @Environment(\.widgetFamily) var family
  var entry: OpenStrapEntry

  @ViewBuilder var body: some View {
    switch family {
    case .systemSmall: G3RecoverySmall(snap: entry.snap, date: entry.date)
    case .systemMedium: G3OverviewMedium(snap: entry.snap, date: entry.date)
    case .accessoryCircular: G3RecoveryCircular(snap: entry.snap, date: entry.date)
    case .accessoryRectangular: G3RecoveryRectangular(snap: entry.snap, date: entry.date)
    case .accessoryInline:
      Text(G3Widget.status(entry.snap, entry.date) == .never
           ? "Noch kein Band" : G3Widget.until(entry.snap, entry.date))
    default: G3RecoverySmall(snap: entry.snap, date: entry.date)
    }
  }
}

struct OpenStrapWidget: Widget {
  let kind: String = "OpenStrapWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      OpenStrapWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("OpenBand 5 · Erholung")
    .description("Erholung, Schlaf und Belastung aus gespeicherten Banddaten.")
    .supportedFamilies([.systemSmall, .systemMedium,
                        .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}
