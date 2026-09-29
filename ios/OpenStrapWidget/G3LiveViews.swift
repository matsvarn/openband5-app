import SwiftUI

struct G3LiveData {
  let name: String
  let startedAt: Date
  let hr: Int
  let zone: Int
  let strain: Double?
  let maxHr: Int
  let signal: String

  var pulse: String { hr > 0 ? String(hr) : "—" }
  var load: String {
    strain.map { "+" + String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") } ?? "—"
  }
  var zoneLabel: String { zone > 0 ? "Zone \(zone)" : "Zone —" }
  var percent: String {
    hr > 0 && maxHr > 0
      ? "\(Int((100.0 * Double(hr) / Double(maxHr)).rounded())) % HFmax" : "% HFmax —"
  }
  var basis: String { maxHr > 0 ? "HFmax \(maxHr) · Quelle nicht übermittelt" : "HFmax fehlt" }
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
  let end: End
  @Environment(\.colorScheme) private var colorScheme
  var body: some View {
    let dark = colorScheme == .dark
    VStack(alignment: .leading, spacing: 13) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
          Text(data.name).font(.system(size: 16, weight: .bold))
          Text("\(data.signal) · seit \(data.startedAt.formatted(date: .omitted, time: .shortened))")
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Spacer()
        Text(data.startedAt, style: .timer)
          .font(.system(size: 25, weight: .bold).monospacedDigit())
      }
      HStack(alignment: .lastTextBaseline, spacing: 14) {
        Text(data.pulse).font(.system(size: 43, weight: .bold).monospacedDigit())
        Text("/min Puls").font(.system(size: 13)).foregroundStyle(.secondary)
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          Text(data.zoneLabel).font(.system(size: 17, weight: .bold))
          Text(data.percent).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        VStack(alignment: .trailing, spacing: 2) {
          Text(data.load).font(.system(size: 17, weight: .bold))
          Text("Belastung").font(.system(size: 11)).foregroundStyle(.secondary)
        }
      }
      HStack(spacing: 14) {
        G3LiveZoneRamp(zone: data.zone, dark: dark)
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
  var body: some View {
    HStack(spacing: 8) {
      Text(data.pulse).font(.system(size: 14, weight: .bold).monospacedDigit())
      Spacer()
      Text(data.startedAt, style: .timer)
        .font(.system(size: 13, weight: .bold).monospacedDigit())
    }.foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 6)
      .background(.black, in: Capsule())
  }
}

struct G3LiveMinimal: View {
  let data: G3LiveData
  var body: some View {
    Text(data.pulse).font(.system(size: 13, weight: .bold).monospacedDigit())
      .foregroundStyle(.white).padding(7).background(.black, in: Circle())
  }
}

struct G3LiveExpanded<End: View>: View {
  let data: G3LiveData
  let end: End
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        VStack(alignment: .leading) {
          Text("\(data.name) · Puls").font(.system(size: 11)).foregroundStyle(.gray)
          Text(data.pulse).font(.system(size: 31, weight: .bold).monospacedDigit())
        }
        Spacer()
        VStack(alignment: .trailing) {
          Text("Dauer").font(.system(size: 11)).foregroundStyle(.gray)
          Text(data.startedAt, style: .timer)
            .font(.system(size: 24, weight: .bold).monospacedDigit())
        }
      }
      HStack {
        Text("\(data.zoneLabel) · \(data.percent)")
        Spacer()
        Text("Belastung \(data.load)")
      }.font(.system(size: 12, weight: .semibold))
      G3LiveZoneRamp(zone: data.zone, dark: true)
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
