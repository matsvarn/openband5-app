//
//  LiveActivityBridge.swift
//  Runner — drives the workout Live Activity from Flutter over a MethodChannel.
//  Channel "openstrap/live_activity": start / update / end. Add to the Runner
//  target. Requires NSSupportsLiveActivities=YES in Info.plist + iOS 16.2+.
//

import Foundation
import Flutter
import ActivityKit

// Live Activity attributes (Runner copy). MUST stay identical to the copy in the
// widget extension (OpenStrapWidgetLiveActivity.swift) — ActivityKit matches the
// activity to the widget by the type name + Codable shape.
@available(iOS 16.1, *)
struct OpenStrapWidgetAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    // Optional additions decode as nil in an activity started by the old app.
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

enum LiveActivityBridge {
  private static let channelName = "openstrap/live_activity"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard #available(iOS 16.2, *) else { result(nil); return }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "start":  start(args);  result(nil)
      case "update": update(args); result(nil)
      case "end":    end();        result(nil)
      default:       result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func iOpt(_ a: [String: Any], _ k: String) -> Int? {
    (a[k] as? NSNumber)?.intValue
  }
  private static func dblOpt(_ a: [String: Any], _ k: String) -> Double? {
    (a[k] as? NSNumber)?.doubleValue
  }

  @available(iOS 16.2, *)
  private static func state(_ a: [String: Any]) -> OpenStrapWidgetAttributes.ContentState {
    .init(
      hr: iOpt(a, "hr"),
      hrSampleAt: iOpt(a, "hrSampleAtMs").map { Date(timeIntervalSince1970: Double($0) / 1000) },
      signal: a["signal"] as? String,
      zone: iOpt(a, "zone"),
      zoneLowPct: dblOpt(a, "zoneLowPct"),
      zoneHighPct: dblOpt(a, "zoneHighPct"),
      zoneBasis: a["zoneBasis"] as? String,
      zoneBasisBpm: iOpt(a, "zoneBasisBpm"),
      elapsedSeconds: iOpt(a, "elapsedSeconds"),
      paused: (a["paused"] as? NSNumber)?.boolValue,
      strain: dblOpt(a, "strain"))
  }

  @available(iOS 16.2, *)
  private static func content(_ a: [String: Any]) -> ActivityContent<OpenStrapWidgetAttributes.ContentState> {
    let value = state(a)
    let staleDate = value.signal == "live" ? value.hrSampleAt?.addingTimeInterval(5) : nil
    return ActivityContent(state: value, staleDate: staleDate)
  }

  @available(iOS 16.2, *)
  private static func start(_ a: [String: Any]) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    // One at a time — end any stragglers first.
    for act in Activity<OpenStrapWidgetAttributes>.activities {
      Task { await act.end(nil, dismissalPolicy: .immediate) }
    }
    let attrs = OpenStrapWidgetAttributes(
      sessionName: a["name"] as? String ?? "Live session",
      startedAt: Date(timeIntervalSince1970: Double(iOpt(a, "startedAtMs") ?? 0) / 1000))
    do {
      _ = try Activity.request(
        attributes: attrs,
        content: content(a))
    } catch {
      NSLog("LiveActivity start failed: \(error)")
    }
  }

  @available(iOS 16.2, *)
  private static func update(_ a: [String: Any]) {
    let content = content(a)
    for act in Activity<OpenStrapWidgetAttributes>.activities {
      Task { await act.update(content) }
    }
  }

  @available(iOS 16.2, *)
  private static func end() {
    for act in Activity<OpenStrapWidgetAttributes>.activities {
      Task { await act.end(nil, dismissalPolicy: .immediate) }
    }
  }
}
