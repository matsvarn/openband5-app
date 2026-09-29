import SwiftUI

struct G3LiveData {
  let name: String
  let startedAt: Date
  let hr: Int?
  let hrSampleAt: Date?
  let signal: String?
  let zone: Int?
  let zoneLowPct: Double?
  let zoneHighPct: Double?
  let zoneBasis: String?
  let zoneBasisBpm: Int?
  let elapsedSeconds: Int?
  let paused: Bool?
  let strain: Double?

  func hasLivePulse(at now: Date) -> Bool {
    guard paused != true, let hr, hr > 0 else { return false }
    // ActivityKit may restore a state written by the previous app version.
    if signal == nil { return true }
    guard signal == "live", let hrSampleAt else { return false }
    let age = now.timeIntervalSince(hrSampleAt)
    return age >= 0 && age <= 5
  }
  func pulse(at now: Date) -> String {
    hasLivePulse(at: now) ? String(hr!) : "—"
  }
  func signalLabel(at now: Date) -> String {
    if paused == true { return "Pausiert" }
    if signal == nil { return "Signal nicht bestätigt" }
    if hasLivePulse(at: now) { return "Puls live" }
    return signal == "weak" || signal == "live" ? "Schwaches Signal" : "Kein Signal"
  }
  var elapsed: String {
    guard let elapsedSeconds, elapsedSeconds >= 0 else { return "—" }
    return String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
  }
  var load: String {
    strain.map { "+" + String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") } ?? "—"
  }
  func activeZone(at now: Date) -> Int {
    hasLivePulse(at: now) ? (zone ?? 0) : 0
  }
  func zoneLabel(at now: Date) -> String {
    if activeZone(at: now) > 0 { return "Zone \(activeZone(at: now))" }
    return hasLivePulse(at: now) && zoneBasis != nil ? "unter Zone 1" : "Zone —"
  }
  func percent(at now: Date) -> String {
    guard activeZone(at: now) > 0, let zoneLowPct, let zoneHighPct,
          let zoneBasis else { return "—" }
    let unit = zoneBasis == "karvonen" ? "% Pulsreserve" :
      (zoneBasis == "tanaka" || zoneBasis == "observed" ? "% HFmax" : nil)
    guard let unit else { return "—" }
    return "\(Int((zoneLowPct * 100).rounded()))–\(Int((zoneHighPct * 100).rounded())) \(unit)"
  }
  var basis: String {
    guard let zoneBasis, let zoneBasisBpm else {
      return signal == nil ? "Zonenbasis nicht bestätigt" : "Zonenbasis fehlt"
    }
    switch zoneBasis {
    case "tanaka": return "HFmax \(zoneBasisBpm) · altersgeschätzt"
    case "observed": return "HFmax \(zoneBasisBpm) · beobachtet"
    case "karvonen": return "Pulsreserve · HFmax \(zoneBasisBpm) beobachtet"
    default: return "Zonenbasis fehlt"
    }
  }
}

struct G3LiveDuration: View {
  let data: G3LiveData
  let size: CGFloat
  var body: some View {
    Group {
      if data.paused == true { Text(data.elapsed) }
      else { Text(data.startedAt, style: .timer) }
    }.font(.system(size: size, weight: .bold).monospacedDigit())
  }
}

private enum G3LAColor {
  static let ink = Color(red: 31/255, green: 31/255, blue: 29/255)
  static let paper = Color(red: 245/255, green: 245/255, blue: 242/255)
  static let gap = Color(red: 109/255, green: 109/255, blue: 104/255)
  static let track = Color(red: 226/255, green: 226/255, blue: 223/255)
}

struct G3LiveZoneRamp: View {
  let zone: Int
  let dark: Bool
  var body: some View {
    HStack(spacing: 3) {
      ForEach(1...5, id: \.self) { index in
        Capsule().fill(index == zone ? (dark ? .white : G3LAColor.gap) :
                       (dark ? .white.opacity(0.34) : G3LAColor.track))
          .frame(height: 7)
          .overlay(alignment: .top) {
            if index == zone {
              Capsule().fill(dark ? .white : G3LAColor.ink)
                .frame(width: 3, height: 14).offset(y: -3)
            }
          }
      }
    }.accessibilityLabel(zone > 0 ? "Zone \(zone) von 5" : "Zone nicht verfügbar")
  }
}

struct G3LiveLockCard<End: View>: View {
  let data: G3LiveData
  var now = Date()
  let end: End
  @Environment(\.colorScheme) private var colorScheme
  var body: some View {
    let dark = colorScheme == .dark
    VStack(alignment: .leading, spacing: 13) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
          Text(data.name).font(.system(size: 16, weight: .bold))
          Text("\(data.signalLabel(at: now)) · seit \(data.startedAt.formatted(date: .omitted, time: .shortened))")
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Spacer()
        G3LiveDuration(data: data, size: 25)
      }
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 0) {
          Text(data.pulse(at: now))
            .font(.system(size: 43, weight: .bold).monospacedDigit())
            .fixedSize(horizontal: true, vertical: false)
          Text("/min Puls").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          Text(data.zoneLabel(at: now)).font(.system(size: 17, weight: .bold))
          Text(data.percent(at: now)).font(.system(size: 11))
            .foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
        }
        VStack(alignment: .trailing, spacing: 2) {
          Text(data.load).font(.system(size: 17, weight: .bold))
          Text("Belastung").font(.system(size: 11)).foregroundStyle(.secondary)
        }
      }
      HStack(spacing: 14) {
        G3LiveZoneRamp(zone: data.activeZone(at: now), dark: dark)
        end
      }
      Text(data.basis).font(.system(size: 10)).foregroundStyle(.secondary)
    }
    .padding(17)
    .foregroundStyle(dark ? G3LAColor.paper : G3LAColor.ink)
    .background(dark ? G3LAColor.ink : G3LAColor.paper,
                in: RoundedRectangle(cornerRadius: 22))
  }
}

struct G3LiveCompact: View {
  let data: G3LiveData
  var now = Date()
  var body: some View {
    HStack(spacing: 8) {
      Text(data.pulse(at: now)).font(.system(size: 14, weight: .bold).monospacedDigit())
      Spacer()
      G3LiveDuration(data: data, size: 13)
    }.foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 6)
      .background(.black, in: Capsule())
  }
}

struct G3LiveMinimal: View {
  let data: G3LiveData
  var now = Date()
  var body: some View {
    Text(data.pulse(at: now)).font(.system(size: 13, weight: .bold).monospacedDigit())
      .foregroundStyle(.white).padding(7).background(.black, in: Circle())
  }
}

struct G3LiveExpanded<End: View>: View {
  let data: G3LiveData
  var now = Date()
  let end: End
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        VStack(alignment: .leading) {
          Text("\(data.name) · Puls").font(.system(size: 11)).foregroundStyle(.gray)
          Text(data.pulse(at: now)).font(.system(size: 31, weight: .bold).monospacedDigit())
        }
        Spacer()
        VStack(alignment: .trailing) {
          Text("Dauer").font(.system(size: 11)).foregroundStyle(.gray)
          G3LiveDuration(data: data, size: 24)
        }
      }
      HStack {
        Text("\(data.zoneLabel(at: now)) · \(data.percent(at: now))")
        Spacer()
        Text("Belastung \(data.load)")
      }.font(.system(size: 12, weight: .semibold))
      G3LiveZoneRamp(zone: data.activeZone(at: now), dark: true)
      HStack {
        Text(data.basis).font(.system(size: 10)).foregroundStyle(.gray)
        Spacer()
        end
      }
    }
    .foregroundStyle(.white).padding(17)
    .background(.black, in: RoundedRectangle(cornerRadius: 22))
  }
}
