import SwiftUI
import WidgetKit

// The same snapshot powers every family. All formatters return an absence when
// their stored input is absent; preview fixtures live only in #Preview blocks.
enum G3Widget {
  static func canvas(_ dark: Bool) -> Color { SW.c(dark ? 0x1F1F1D : 0xF5F5F2) }
  static func ink(_ dark: Bool) -> Color { SW.c(dark ? 0xF5F5F2 : 0x1F1F1D) }
  static func muted(_ dark: Bool) -> Color { SW.c(dark ? 0xA4A49F : 0x6D6D68) }
  static func track(_ dark: Bool) -> Color { SW.c(dark ? 0x41413D : 0xE2E2DF) }
  static func gap(_ dark: Bool) -> Color { SW.c(dark ? 0x81817C : 0x92928C) }
  static func time(_ minutes: Int) -> String {
    minutes < 0 ? "—" : "\(minutes / 60)h\(String(format: "%02d", minutes % 60))"
  }
  static func strain(_ value: Double) -> String {
    value < 0 ? "—" : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
  }
  static func cap(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .bold) }
  static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .bold).monospacedDigit() }

  static func status(_ s: SW.Snapshot, _ date: Date) -> State {
    if s.neverConnected { return .never }
    if !s.g3SnapshotPresent {
      let hasLegacyValue = s.recoveryValue >= 0 || s.sleepMinutes >= 0 ||
        s.strainValue >= 0 || s.batteryPercent >= 0
      if !hasLegacyValue { return .never }
      if s.updatedAt <= 0 { return .missing }
      return Calendar.current.isDate(Date(timeIntervalSince1970: Double(s.updatedAt)),
                                     inSameDayAs: date) ? .current : .stale
    }
    if !s.g3HasSnapshot {
      guard s.sampleAt > 0 else {
        return s.recoveryValue >= 0 || s.sleepMinutes >= 0 ||
          s.strainValue >= 0 || s.batteryPercent >= 0 ? .missing : .never
      }
      return SW.stale(s, at: date) ? .stale : .empty
    }
    if s.sampleAt > 0 && SW.stale(s, at: date) { return .stale }
    if s.sampleAt <= 0 { return .missing }
    if s.recoveryValue < 0, s.baselineHave >= 0, s.baselineNeed > 0 { return .building }
    return .current
  }
  enum State: Equatable { case current, stale, building, empty, never, missing }

  static func until(_ s: SW.Snapshot, _ date: Date) -> String {
    if !s.g3SnapshotPresent {
      guard s.updatedAt > 0 else { return "Aktualität unklar" }
      let updated = Date(timeIntervalSince1970: Double(s.updatedAt))
      let clock = updated.formatted(date: .omitted, time: .shortened)
      if Calendar.current.isDate(updated, inSameDayAs: date) { return "Aktualisiert \(clock)" }
      if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date),
         Calendar.current.isDate(updated, inSameDayAs: yesterday) {
        return "Aktualisiert gestern \(clock)"
      }
      return "Aktualisiert \(updated.formatted(.dateTime.day().month(.twoDigits))) · \(clock)"
    }
    guard s.sampleAt > 0 else { return "Daten bis —" }
    let sample = Date(timeIntervalSince1970: Double(s.sampleAt))
    let clock = sample.formatted(date: .omitted, time: .shortened)
    if Calendar.current.isDate(sample, inSameDayAs: date) { return "Daten bis \(clock)" }
    if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date),
       Calendar.current.isDate(sample, inSameDayAs: yesterday) {
      return "Daten bis gestern \(clock)"
    }
    return "Daten bis \(sample.formatted(.dateTime.day().month(.twoDigits))) · \(clock)"
  }
  static func staleLabel(_ s: SW.Snapshot, _ date: Date) -> String {
    let stamp = s.g3SnapshotPresent ? s.sampleAt : s.updatedAt
    guard stamp > 0 else { return "veraltet" }
    let sample = Date(timeIntervalSince1970: Double(stamp))
    if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date),
       Calendar.current.isDate(sample, inSameDayAs: yesterday) { return "gestern" }
    return sample.formatted(.dateTime.day().month(.twoDigits))
  }
  static func statusInline(_ s: SW.Snapshot, _ date: Date) -> String {
    if status(s, date) == .never { return "Noch kein Band" }
    return "Band \(battery(s, date)) · \(until(s, date))"
  }
  /// -1 below, 0 inside, 1 above; nil without a trusted G3 range.
  static func recoveryVerdict(_ s: SW.Snapshot) -> Int? {
    guard s.g3HasSnapshot, s.recoveryValue >= 0,
          s.recoveryLow >= 0, s.recoveryHigh > s.recoveryLow else { return nil }
    if Double(s.recoveryValue) < s.recoveryLow { return -1 }
    if Double(s.recoveryValue) > s.recoveryHigh { return 1 }
    return 0
  }
  static func battery(_ s: SW.Snapshot, _ date: Date) -> String {
    guard s.batteryPercent >= 0, s.batteryAt > 0,
          Calendar.current.isDate(Date(timeIntervalSince1970: Double(s.batteryAt)),
                                  inSameDayAs: date) else { return "—" }
    return "\(s.batteryPercent) %"
  }
  static func batterySymbol(_ percent: Int) -> String {
    switch percent {
    case ..<11: return "battery.0percent"
    case 11..<38: return "battery.25percent"
    case 38..<63: return "battery.50percent"
    case 63..<88: return "battery.75percent"
    default: return "battery.100percent"
    }
  }
}

struct G3BatteryInline: View {
  let snap: SW.Snapshot
  let date: Date
  let percent: Int
  var body: some View {
    let label = G3Widget.statusInline(snap, date)
    if percent >= 0 {
      Label(label, systemImage: G3Widget.batterySymbol(percent))
    } else {
      Text(label)
    }
  }
}

struct G3ProgressBar: View {
  let fraction: Double
  let dark: Bool
  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(G3Widget.track(dark))
        if fraction >= 0 {
          Capsule().fill(G3Widget.ink(dark))
            .frame(width: geo.size.width * min(max(fraction, 0), 1))
        }
      }
    }.frame(height: 5)
  }
}

struct G3RangeScale: View {
  let value: Int
  let low: Double
  let high: Double
  let dark: Bool
  @Environment(\.widgetRenderingMode) private var renderingMode
  var body: some View {
    GeometryReader { geo in
      let valid = low >= 0 && high > low && value >= 0
      let span = valid ? high - low : 1
      let pos = valid ? min(max((Double(value) - low) / span, -0.5), 1.5) : 0.5
      let pointer: Color = renderingMode != .fullColor ? G3Widget.ink(dark) :
        Double(value) < low ? SW.c(dark ? 0xD7A45B : 0xA46B2B) :
        Double(value) > high ? SW.c(dark ? 0x9BCB9F : 0x287548) :
        G3Widget.ink(dark)
      ZStack(alignment: .leading) {
        Capsule().fill(G3Widget.track(dark)).frame(height: 6)
        if valid {
          Capsule().fill(G3Widget.gap(dark).opacity(0.5))
            .frame(width: geo.size.width * 0.23, height: 6)
            .offset(x: geo.size.width * 0.39)
          Capsule().fill(pointer).frame(width: 4, height: 14)
            .offset(x: max(0, min(geo.size.width - 4, geo.size.width * (0.39 + 0.23 * pos))))
        }
      }.frame(maxHeight: .infinity)
    }.frame(height: 16)
  }
}

struct G3Recovery: View {
  let snap: SW.Snapshot
  let date: Date
  let dark: Bool
  var compact = false
  @Environment(\.widgetRenderingMode) private var renderingMode

  private var state: G3Widget.State { G3Widget.status(snap, date) }
  private var verdict: Int? { state == .current ? G3Widget.recoveryVerdict(snap) : nil }
  private var under: Bool { verdict == -1 }
  private var above: Bool { verdict == 1 }
  private var lead: String {
    state == .never || state == .missing || state == .building || state == .empty ||
      (snap.g3SnapshotPresent && !snap.g3HasSnapshot) || snap.recoveryValue < 0
      ? "—" : String(snap.recoveryValue)
  }
  private var leadColor: Color {
    if state == .stale { return G3Widget.gap(dark) }
    guard renderingMode == .fullColor else { return G3Widget.ink(dark) }
    if under { return SW.c(dark ? 0xD7A45B : 0xA46B2B) }
    if above { return SW.c(dark ? 0x9BCB9F : 0x287548) }
    return G3Widget.ink(dark)
  }
  private var spoken: String {
    if state == .never { return "Erholung, noch kein Band" }
    if state == .missing { return "Erholung, Aktualität unklar" }
    if state == .empty {
      return "Erholung nicht verfügbar, heute keine Werte, \(G3Widget.until(snap, date))"
    }
    if state == .building {
      return "Erholung, Basis \(snap.baselineHave) von \(snap.baselineNeed), noch \(max(0, snap.baselineNeed - snap.baselineHave))"
    }
    if state == .stale {
      if snap.g3SnapshotPresent && !snap.g3HasSnapshot {
        return "Erholung nicht verfügbar, \(G3Widget.until(snap, date))"
      }
      return "Erholung \(lead), \(G3Widget.staleLabel(snap, date)), heute Nacht fehlt"
    }
    let relation = under ? "unter deinem Bereich" : above ? "über deinem Bereich" :
      verdict == 0 ? "normal \(Int(snap.recoveryLow.rounded())) bis \(Int(snap.recoveryHigh.rounded()))" :
      "persönlicher Bereich nicht verfügbar"
    return "Erholung \(lead), \(relation)"
  }
  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 5 : 9) {
      Text("ERHOLUNG").font(G3Widget.cap(compact ? 10 : 11)).tracking(1.2)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        if under { Text("▼").font(.system(size: 13, weight: .bold)) }
        if above { Text("▲").font(.system(size: 13, weight: .bold)) }
        Text(lead).font(G3Widget.number(compact ? 45 : 50))
          .minimumScaleFactor(0.58).lineLimit(1)
      }.foregroundStyle(leadColor)
      if state == .building {
        Text("Basis: \(snap.baselineHave) von \(snap.baselineNeed) · noch \(max(0, snap.baselineNeed - snap.baselineHave))")
          .font(.system(size: 11, weight: .medium)).lineLimit(2)
        HStack(spacing: 2) {
          ForEach(0..<max(0, min(snap.baselineNeed, 20)), id: \.self) { i in
            Capsule().fill(i < snap.baselineHave ? G3Widget.ink(dark) : G3Widget.track(dark))
          }
        }.frame(height: 5)
      } else if state == .never {
        Text("Zum Verbinden tippen").font(.system(size: 11, weight: .medium))
      } else if state == .stale {
        Text(snap.g3SnapshotPresent && !snap.g3HasSnapshot ? "heute keine Werte" :
             "\(G3Widget.staleLabel(snap, date)) · heute: Nacht fehlt")
          .font(.system(size: 11, weight: .medium)).lineLimit(2)
      } else if state == .missing {
        Text("Aktualität unklar").font(.system(size: 11, weight: .medium))
      } else if state == .empty {
        Text("Heute keine Werte").font(.system(size: 11, weight: .medium))
      } else if verdict != nil {
        Text(under ? "unter deinem Bereich" : above ? "über deinem Bereich" :
             "normal \(Int(snap.recoveryLow.rounded()))–\(Int(snap.recoveryHigh.rounded()))")
          .font(.system(size: compact ? 11 : 12, weight: .medium)).lineLimit(1)
        G3RangeScale(value: snap.recoveryValue, low: snap.recoveryLow,
                     high: snap.recoveryHigh, dark: dark)
      } else if !snap.g3HasSnapshot {
        Text("Bereich nicht verfügbar")
          .font(.system(size: 11, weight: .medium)).lineLimit(2)
      } else {
        Text("Persönlicher Bereich fehlt").font(.system(size: 11, weight: .medium)).lineLimit(2)
      }
      if compact && state != .never && state != .missing {
        Text(G3Widget.until(snap, date)).font(.system(size: 10, weight: .semibold)).lineLimit(1)
      }
    }
    .foregroundStyle(G3Widget.muted(dark))
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(spoken)
  }
}

struct G3OverviewMedium: View {
  let snap: SW.Snapshot
  let date: Date
  @Environment(\.colorScheme) private var colorScheme
  private var dark: Bool { colorScheme == .dark }
  private var state: G3Widget.State { G3Widget.status(snap, date) }
  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        G3Recovery(snap: snap, date: date, dark: dark)
        Spacer(minLength: 0)
        Text(state == .never ? "Noch kein Band" :
             !snap.g3HasSnapshot ? G3Widget.until(snap, date) :
             "▰ \(G3Widget.battery(snap, date)) · \(G3Widget.until(snap, date).replacingOccurrences(of: "Daten ", with: ""))")
          .font(.system(size: 10, weight: .semibold)).lineLimit(1)
          .foregroundStyle(G3Widget.muted(dark))
      }
      Rectangle().fill(G3Widget.track(dark)).frame(width: 1)
      VStack(alignment: .leading, spacing: 5) {
        Text("SCHLAF").font(G3Widget.cap()).tracking(1)
        Text(state == .current || state == .building ? G3Widget.time(snap.sleepMinutes) : "—")
          .font(G3Widget.number(25)).minimumScaleFactor(0.7).lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
        Text((state != .current && state != .building) || snap.sleepMinutes < 0
             ? "Nacht fehlt" :
             !snap.g3HasSnapshot ? "Ziel nicht verfügbar" :
             snap.sleepGoalMinutes > 0 ? "Ziel \(G3Widget.time(snap.sleepGoalMinutes))" : "Ziel fehlt")
          .font(.system(size: 10)).foregroundStyle(G3Widget.muted(dark)).lineLimit(1)
        G3ProgressBar(fraction: (state == .current || state == .building) &&
                      snap.g3HasSnapshot &&
                      snap.sleepGoalMinutes > 0 && snap.sleepMinutes >= 0
                      ? Double(snap.sleepMinutes) / Double(snap.sleepGoalMinutes) : -1, dark: dark)
        Spacer(minLength: 0)
        Text("BELASTUNG").font(G3Widget.cap()).tracking(1)
        Text(state == .current || state == .building ? G3Widget.strain(snap.strainValue) : "—")
          .font(G3Widget.number(24)).lineLimit(1)
        G3ProgressBar(fraction: (state == .current || state == .building) && snap.strainValue >= 0
                      ? snap.strainValue / 21 : -1, dark: dark)
      }.foregroundStyle(G3Widget.ink(dark)).frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(16)
    .containerBackground(G3Widget.canvas(dark), for: .widget)
  }
}

struct G3RecoverySmall: View {
  let snap: SW.Snapshot
  let date: Date
  @Environment(\.colorScheme) private var colorScheme
  var body: some View {
    let dark = colorScheme == .dark
    G3Recovery(snap: snap, date: date, dark: dark, compact: true)
      .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .containerBackground(G3Widget.canvas(dark), for: .widget)
  }
}

struct G3SleepSmall: View {
  let snap: SW.Snapshot
  let date: Date
  @Environment(\.colorScheme) private var colorScheme
  var body: some View {
    let dark = colorScheme == .dark
    let state = G3Widget.status(snap, date)
    VStack(alignment: .leading, spacing: 8) {
      Text("SCHLAF").font(G3Widget.cap()).tracking(1)
      Spacer(minLength: 0)
      Text(state == .current || state == .building ? G3Widget.time(snap.sleepMinutes) : "—")
        .font(G3Widget.number(39)).minimumScaleFactor(0.6).lineLimit(1)
      Text(state == .stale ? "\(G3Widget.staleLabel(snap, date)) · Nacht fehlt" :
           state == .never ? "Zum Verbinden tippen" :
           state == .missing ? "Aktualität unklar" :
           state == .empty ? "Heute keine Werte" :
           !snap.g3HasSnapshot ? "Ziel nicht verfügbar" :
           snap.sleepGoalMinutes > 0 ? "Ziel \(G3Widget.time(snap.sleepGoalMinutes))" : "Ziel fehlt")
        .font(.system(size: 11, weight: .medium)).lineLimit(2)
      G3ProgressBar(fraction: (state == .current || state == .building) &&
                    snap.g3HasSnapshot &&
                    snap.sleepGoalMinutes > 0 && snap.sleepMinutes >= 0
                    ? Double(snap.sleepMinutes) / Double(snap.sleepGoalMinutes) : -1, dark: dark)
      if state != .never && state != .missing {
        Text(G3Widget.until(snap, date)).font(.system(size: 10, weight: .semibold)).lineLimit(1)
      }
    }
    .foregroundStyle(G3Widget.ink(dark))
    .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .containerBackground(G3Widget.canvas(dark), for: .widget)
  }
}

struct G3SleepAccessory: View {
  let snap: SW.Snapshot
  let date: Date
  let circular: Bool
  var body: some View {
    let state = G3Widget.status(snap, date)
    let value = state == .current || state == .building
      ? G3Widget.time(snap.sleepMinutes) : "—"
    Text(circular ? value : "Schlaf \(value)").widgetAccentable()
  }
}

struct G3RecoveryCircular: View {
  let snap: SW.Snapshot
  let date: Date
  var body: some View {
    let state = G3Widget.status(snap, date)
    let verdict = state == .current ? G3Widget.recoveryVerdict(snap) : nil
    let under = verdict == -1
    let above = verdict == 1
    ZStack {
      Circle().stroke(.secondary.opacity(0.35), lineWidth: 5)
      if state == .current && snap.recoveryValue >= 0 {
        Circle().trim(from: 0, to: min(Double(snap.recoveryValue) / 100, 1))
          .stroke(.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      VStack(spacing: 0) {
        Text(state == .building && snap.baselineHave >= 0 && snap.baselineNeed > 0
             ? "\(snap.baselineHave)/\(snap.baselineNeed)" :
             state == .current && snap.recoveryValue >= 0
             ? "\(under ? "▼" : above ? "▲" : "")\(snap.recoveryValue)" : "—")
          .font(.system(size: state == .building ? 13 : under || above ? 16 : 20,
                        weight: .bold)).minimumScaleFactor(0.6)
        Text(state == .building ? "Basis" : under ? "unter" : above ? "über" : "Erh.")
          .font(.system(size: 8, weight: .semibold))
      }
    }.padding(4).widgetAccentable().accessibilityElement(children: .combine)
      .accessibilityLabel(under ? "Erholung \(snap.recoveryValue), unter deinem Bereich" :
                          above ? "Erholung \(snap.recoveryValue), über deinem Bereich" :
                          state == .building ? "Erholung, Basis \(snap.baselineHave) von \(snap.baselineNeed)" :
                          state == .current && snap.recoveryValue >= 0 ? "Erholung \(snap.recoveryValue)" :
                          state == .stale && snap.recoveryValue >= 0 &&
                            (!snap.g3SnapshotPresent || snap.g3HasSnapshot)
                            ? "Erholung \(snap.recoveryValue), \(G3Widget.staleLabel(snap, date))" :
                          "Erholung nicht verfügbar")
  }
}

struct G3RecoveryRectangular: View {
  let snap: SW.Snapshot
  let date: Date
  @Environment(\.colorScheme) private var colorScheme
  var body: some View {
    let state = G3Widget.status(snap, date)
    VStack(alignment: .leading, spacing: 3) {
      if state == .building {
        Text("Erholung — · Basis").font(.system(size: 12, weight: .bold))
        Text("\(snap.baselineHave) von \(snap.baselineNeed) · noch \(max(0, snap.baselineNeed - snap.baselineHave))")
          .font(.system(size: 11))
        HStack(spacing: 2) {
          ForEach(0..<max(0, min(snap.baselineNeed, 20)), id: \.self) { i in
            Capsule().fill(i < snap.baselineHave ? Color.primary : Color.secondary.opacity(0.35))
          }
        }.frame(height: 5)
      } else if state == .never {
        Text("Noch kein Band").font(.system(size: 12, weight: .bold))
        Text("Zum Verbinden tippen").font(.system(size: 11))
      } else if state == .stale {
        let value = snap.g3SnapshotPresent && !snap.g3HasSnapshot ? "—" :
          snap.recoveryValue >= 0 ? String(snap.recoveryValue) : "—"
        Text("Erholung \(value) · \(G3Widget.staleLabel(snap, date))")
          .font(.system(size: 12, weight: .bold))
        Text(snap.g3SnapshotPresent && !snap.g3HasSnapshot
             ? G3Widget.until(snap, date) : "heute: Nacht fehlt")
          .font(.system(size: 11))
      } else if state == .missing {
        Text("Erholung —").font(.system(size: 12, weight: .bold))
        Text("Aktualität unklar").font(.system(size: 11))
      } else if state == .empty {
        Text("Erholung —").font(.system(size: 12, weight: .bold))
        Text(G3Widget.until(snap, date)).font(.system(size: 11))
      } else {
        let verdict = G3Widget.recoveryVerdict(snap)
        let under = verdict == -1
        let above = verdict == 1
        Text(under ? "▼ Erholung \(snap.recoveryValue) · unter" :
             above ? "▲ Erholung \(snap.recoveryValue) · über" :
             "Erholung \(snap.recoveryValue >= 0 ? String(snap.recoveryValue) : "—")")
          .font(.system(size: 12, weight: .bold))
        if under || above {
          G3RangeScale(value: snap.recoveryValue, low: snap.recoveryLow,
                       high: snap.recoveryHigh, dark: colorScheme == .dark)
        } else {
          if verdict == 0 {
            G3RangeScale(value: snap.recoveryValue, low: snap.recoveryLow,
                         high: snap.recoveryHigh, dark: colorScheme == .dark)
          }
          Text("Schlaf \(G3Widget.time(snap.sleepMinutes)) · \(G3Widget.until(snap, date))")
            .font(.system(size: 11)).lineLimit(1)
        }
      }
    }.widgetAccentable().accessibilityElement(children: .combine)
  }
}

#if DEBUG
#Preview("Recovery small", as: .systemSmall) {
  OpenStrapWidget()
} timeline: {
  OpenStrapEntry.placeholder
}
#Preview("Overview medium", as: .systemMedium) {
  OpenStrapWidget()
} timeline: {
  OpenStrapEntry.placeholder
}
#Preview("Sleep small", as: .systemSmall) {
  OpenStrapSleepWidget()
} timeline: {
  SleepEntry.placeholder
}
#endif
