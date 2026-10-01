import Foundation
import CoreBluetooth
import UIKit
import Flutter

/// Keeps the app eligible for background relaunch when the paired WHOOP band becomes
/// reachable — the mechanism WHOOP/Garmin use on iOS (CoreBluetooth State Preservation
/// & Restoration). No persistent notification, no foreground service.
///
/// Running this as a SEPARATE CBCentralManager (distinct restoration identifier) from
/// the "live" central flutter_blue_plus drives is an Apple-documented, supported pattern,
/// not an inferred workaround: "Because apps can have multiple instances of
/// CBCentralManager... be sure each restoration identifier is unique, so that the system
/// can properly distinguish one central... from another" (Core Bluetooth Background
/// Processing for iOS Apps). Confirmed directly against that doc — this is not a deviation
/// from a single-manager model Apple only describes for the simple case.
///
/// It does NOT drain data. flutter_blue_plus owns the real GATT session. Apple's
/// cancelPeripheralConnection documentation says cancelling a local connection does
/// not guarantee the physical link disconnects while another connection exists:
/// https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/cancelperipheralconnection(_:)
/// This central holds a no-timeout pending connect so iOS relaunches us when the band
/// shows up, then tells Flutter to sync. Every connected restore band is handedOff.
/// Only a completed takeover may leave restoration idle; every other handoff end
/// cancels and re-arms a pending connect.
/// Dart sends syncDone after a drain attempt or a confirmed flutter_blue_plus link,
/// and handoffExpired if foreground takeover fails within 80 awake polls. Unacknowledged
/// handoffs are released by background-task expiration or the 60-second watchdog.
///
/// This is RECOVERY-ONLY: normal sync is the kept-alive live connection + the AppState
/// flusher. Dart starts recovery when the connection drops (`setOwnsBand(false)` / `arm`);
/// unacknowledged wakes keep recovery armed. No connect timeout or cooldown.
///
/// After syncDone releases a handoff, we go IDLE until the next explicit request from
/// Dart (a fresh disconnect). Expired handoffs instead re-arm recovery.
/// Arming only happens while backgrounded; in the foreground
/// flutter_blue_plus owns the band.
///
/// Verified against Apple's official docs ("Core Bluetooth Background Processing for iOS
/// Apps"): a state-restoration relaunch is a BOUNDED wake, not indefinite runtime — "an app
/// has around 10 seconds to complete a task... apps that spend too much time executing in
/// the background can be throttled back by the system or killed," and even a fully
/// backgrounded app "can't run forever... the system may need to terminate your app to free
/// up memory." This is exactly why the headless sync this triggers (background_sync.dart's
/// runHeadlessSync) is designed to make partial progress safely on every wake — commit
/// whatever it drained before the window closes, resume from the durable cursor next time —
/// rather than assuming it gets to run to completion in one continuous background session.

/// Per-peripheral restore state. Replaces the three process-wide flags
/// (`handedOff` / `idleAfterSync` / `appOwnsBand`), which were only ever correct
/// while exactly one band could be provisioned: with two, band A's foreground
/// connect set `appOwnsBand = true` and suppressed band B's background re-arm,
/// presenting days later as "the app stopped syncing overnight" with no error.
/// Only a completed takeover may leave restoration idle; every other handoff end
/// cancels and re-arms a pending connect.
private struct ArmState {
  /// The peripheral we hold a pending connect for. Retained here so ARC cannot
  /// drop it mid-connect — a peripheral we no longer hold is one `cancelPending`
  /// can no longer cancel.
  var peripheral: CBPeripheral?
  /// Always true while this restore band's peripheral is connected, including on
  /// relaunch. Ends with syncDone (idle) or an expired handoff (re-arm).
  var handedOff = false
  /// Incremented for each connected handoff so older watchdogs cannot release it.
  var handoffGeneration: Int = 0
  /// Dart accepted the wake and will release it with syncDone or handoffExpired,
  /// even across suspension. False leaves release to task expiration or the watchdog.
  var wakeAcknowledged = false
  /// Set only after syncDone; an expired handoff re-arms instead.
  /// Suppresses re-arming until Dart explicitly re-arms it on the next disconnect.
  var idleAfterSync = false
  /// True while the app holds the live flutter_blue_plus connection to THIS band.
  var appOwnsBand = false
}

class BleRestoreManager: NSObject {
  static let shared = BleRestoreManager()

  private static let restoreId = "openstrap.ble.restore"
  private static let bandUUIDKey = "openstrap.ble.band_uuid"   // LEGACY scalar. Never removed.
  private static let bandUUIDsKey = "openstrap.ble.band_uuids"  // [String], the new truth.

  private var central: CBCentralManager?
  private var bandUUID: UUID?
  /// Provisioned bands and their arm state, keyed by CoreBluetooth peripheral UUID.
  /// With one provisioned band there is exactly one entry and every loop below runs
  /// once — byte-identical behaviour to the scalar version it replaces.
  private var arms: [UUID: ArmState] = [:]
  private var channel: FlutterMethodChannel?
  private var flutterReady = false
  private var pendingLogs: [String] = []
  private let logTimestamp = ISO8601DateFormatter()

  private func log(_ message: String) {
    NSLog("%@", message)
    let line = "\(logTimestamp.string(from: Date())) \(message)"
    if flutterReady {
      channel?.invokeMethod("log", arguments: line)
    } else {
      pendingLogs.append(line)
      if pendingLogs.count > 200 { pendingLogs.removeFirst() }
    }
  }

  private func logArmState(_ uuid: UUID) {
    let st = state(uuid)
    log("[ble-restore] \(uuid.uuidString) handedOff=\(st.handedOff) idleAfterSync=\(st.idleAfterSync)")
  }

  private var wakeQueuedBeforeReady = false
  private var bgTask: UIBackgroundTaskIdentifier = .invalid

  /// Insert-or-get, so a caller never has to branch on "first time for this UUID".
  private func state(_ uuid: UUID) -> ArmState {
    arms[uuid] ?? ArmState()
  }

  // MARK: - Lifecycle

  /// Wire lifecycle observers, but DO NOT create the CBCentralManager yet unless a band
  /// is already saved (i.e. an accessory was provisioned on a prior launch).
  ///
  /// CRITICAL ORDERING (AccessorySetupKit): `ASAccessorySession.showPicker` fails with
  /// "CBManager is active with global permissions" if ANY CBCentralManager already exists
  /// in the process when the picker is shown. On a FIRST-time pairing there is no
  /// provisioned accessory yet, so creating the restore central here at launch is exactly
  /// what blocked the picker. The fix: only instantiate the restore central when we
  /// already have a provisioned band (saved bandUUID). On a fresh install the central is
  /// created LATER — see `bandProvisioned(_:)`, called right after the ASK picker succeeds.
  ///
  /// On launches where the band is already provisioned, creating the central here is fine
  /// (scoped Bluetooth authorization is already granted, and we never show the picker), so
  /// iOS can still call willRestoreState to relaunch us for a Bluetooth event.
  func start(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
    for u in loadBandUUIDs() { arms[u] = ArmState() }
    let nc = NotificationCenter.default
    nc.addObserver(self, selector: #selector(appDidEnterBackground),
                   name: UIApplication.didEnterBackgroundNotification, object: nil)
    nc.addObserver(self, selector: #selector(appWillEnterForeground),
                   name: UIApplication.willEnterForegroundNotification, object: nil)
    if !arms.isEmpty {
      // Already provisioned on a prior launch → safe to create the restore central now so
      // iOS can relaunch us via willRestoreState. (No picker is ever shown in this case.)
      ensureCentral()
      log("[ble-restore] started (bands=\(arms.keys.map(\.uuidString).joined(separator: ","))) "
            + "— restore central up")
    } else {
      // Fresh install / no provisioned accessory → DEFER central creation so the ASK
      // picker can be shown with no CBCentralManager alive.
      log("[ble-restore] started (no band) — restore central deferred until provisioned")
    }
  }

  /// Lazily create the restoring CBCentralManager (idempotent). Must only be called once a
  /// band has been provisioned via ASK — never before the first ASK picker, or it
  /// re-introduces the "CBManager is active with global permissions" failure.
  private func ensureCentral() {
    guard central == nil else { return }
    central = CBCentralManager(
      delegate: self,
      queue: nil,
      options: [CBCentralManagerOptionRestoreIdentifierKey: BleRestoreManager.restoreId]
    )
  }

  /// Called from Dart immediately AFTER the ASK picker provisions an accessory (first-time
  /// pairing). Now that an accessory exists, it is safe to create the restore central; from
  /// here on the app behaves exactly as a normal already-provisioned launch.
  func bandProvisioned(_ uuid: UUID) {
    saveBandUUID(uuid)
    bandUUID = uuid
    if arms[uuid] == nil { arms[uuid] = ArmState() }
    ensureCentral()
    log("[ble-restore] band provisioned — restore central created")
  }

  /// Wire the Dart channel. Safe on the implicit engine too (background launch).
  func attach(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "openstrap/ble_restore", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "provisioned":
        // First-time ASK pairing just succeeded — NOW it's safe to create the restore
        // central (an accessory exists, so showPicker is no longer pending and the
        // "CBManager is active with global permissions" constraint no longer applies).
        if let s = call.arguments as? String, let uuid = UUID(uuidString: s) {
          self.bandProvisioned(uuid)
        }
        result(nil)
      case "arm":
        // Scalar String (today's shape) or a List<String> — either way, arm each uuid.
        var uuids: [UUID] = []
        if let s = call.arguments as? String, let uuid = UUID(uuidString: s) {
          uuids = [uuid]
        } else if let list = call.arguments as? [String] {
          uuids = list.compactMap(UUID.init(uuidString:))
        }
        for uuid in uuids {
          self.saveBandUUID(uuid)
          self.bandUUID = uuid
          var s = self.state(uuid)
          if s.peripheral?.state == .connected {
            self.log("[ble-restore] arm \(uuid.uuidString) — connected handoff stays open")
          } else {
            s.handedOff = false
            s.wakeAcknowledged = false
          }
          s.idleAfterSync = false   // explicit (re-)arm request from Dart
          self.arms[uuid] = s
          self.logArmState(uuid)
        }
        if !uuids.isEmpty {
          // The band is provisioned by the time Dart arms; ensure the restore central
          // exists (it may have been deferred at launch on a fresh install).
          self.ensureCentral()
          self.armIfAppropriate()
        }
        result(nil)
      case "setOwnsBand":
        if let dict = call.arguments as? [String: Any],
           let s = dict["uuid"] as? String, let uuid = UUID(uuidString: s) {
          let owns = (dict["owns"] as? Bool) ?? false
          var st = self.state(uuid)
          st.appOwnsBand = owns
          self.arms[uuid] = st
          self.logArmState(uuid)
          if owns {
            self.cancelPending(uuid)
            self.log("[ble-restore] app owns band \(uuid.uuidString) — pending connect cancelled")
          } else {
            st.idleAfterSync = false
            self.arms[uuid] = st
            self.logArmState(uuid)
            self.log("[ble-restore] app released band \(uuid.uuidString) — arming recovery")
            self.armIfAppropriate()
          }
        } else {
          let owns = (call.arguments as? Bool) ?? false
          for uuid in Array(self.arms.keys) {
            var st = self.state(uuid)
            st.appOwnsBand = owns
            if owns {
              self.arms[uuid] = st
              self.logArmState(uuid)
              self.cancelPending(uuid)
            } else {
              st.idleAfterSync = false
              self.arms[uuid] = st
              self.logArmState(uuid)
            }
          }
          if owns {
            self.log("[ble-restore] app owns band — pending connect cancelled")
          } else {
            self.log("[ble-restore] app released band — arming recovery")
            self.armIfAppropriate()
          }
        }
        result(nil)
      case "armRecoveryNow":
        // Atomic combination of setOwnsBand(false) + arm(uuid) in ONE round trip —
        // used on the hot disconnect-recovery path (AppState._armRecovery). Two
        // separate awaited channel calls left a window where a process suspension
        // between them could drop appOwnsBand to false with nothing armed to
        // replace it (worst of both: app no longer owns the band, AND no pending
        // connect is watching for it). Doing both under one delegate callback,
        // wrapped in a short background-task extension, removes that window.
        if let s = call.arguments as? String, let uuid = UUID(uuidString: s) {
          self.beginBackground()
          self.saveBandUUID(uuid)
          self.bandUUID = uuid
          var st = self.state(uuid)
          st.appOwnsBand = false
          if st.peripheral?.state == .connected {
            self.log("[ble-restore] armRecoveryNow \(uuid.uuidString) — connected handoff stays open")
          } else {
            st.handedOff = false
            st.wakeAcknowledged = false
          }
          st.idleAfterSync = false
          self.arms[uuid] = st
          self.logArmState(uuid)
          self.ensureCentral()
          self.armIfAppropriate()
          self.log("[ble-restore] armRecoveryNow — recovery armed atomically")
          // The actual recovery (the no-timeout pending connect) is now held by
          // bluetoothd itself and survives full app suspension; the background-task
          // extension only needed to cover this method's own synchronous work, so
          // release it shortly rather than holding it for the full ~30s budget.
          DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.endBackground()
          }
        }
        result(nil)
      case "disarm":
        if let s = call.arguments as? String, let uuid = UUID(uuidString: s) {
          self.disarm(uuid)
        } else {
          self.disarm()
        }
        result(nil)
      case "releaseCentralForPicker":
        // Tears down the CBCentralManager but keeps `arms` and BOTH UserDefaults keys.
        // `disarm()` also clears the keys, which is right for unpair and catastrophic
        // here: a process death between this call and the picker's completion would
        // leave the primary with no restore key and no error anywhere.
        self.cancelPending()
        if self.central != nil {
          self.central?.delegate = nil
          self.central = nil
          self.log("[ble-restore] restore central released for ASK picker (bands kept)")
        }
        result(nil)
      case "ready":
        self.flutterReady = true
        for line in self.pendingLogs {
          self.channel?.invokeMethod("log", arguments: line)
        }
        self.pendingLogs.removeAll()
        if self.wakeQueuedBeforeReady {
          self.wakeQueuedBeforeReady = false
          self.channel?.invokeMethod("wake", arguments: nil)
          for uuid in Array(self.arms.keys) where self.arms[uuid]?.handedOff == true {
            self.startWakeWatchdog(uuid)
          }
        }
        result(nil)
      case "wakeAck":
        for uuid in Array(self.arms.keys) where self.arms[uuid]?.handedOff == true {
          self.arms[uuid]?.wakeAcknowledged = true
          self.log("[ble-restore] wake acknowledged for \(uuid.uuidString)")
        }
        result(nil)
      case "syncDone":
        self.log("[ble-restore] syncDone received")
        // Dart finished the drain or confirmed a live band link. Release the named
        // bands (all if omitted).
        let uuids: [UUID]
        if let s = call.arguments as? String, let uuid = UUID(uuidString: s) {
          uuids = [uuid]
        } else if let list = call.arguments as? [String] {
          uuids = list.compactMap(UUID.init(uuidString:))
        } else {
          uuids = Array(self.arms.keys)
        }
        for uuid in uuids {
          var st = self.state(uuid)
          st.handedOff = false
          st.wakeAcknowledged = false
          st.idleAfterSync = true
          self.arms[uuid] = st
          self.logArmState(uuid)
          self.cancelPending(uuid)
        }
        self.endBackground()
        result(nil)
      case "handoffExpired":
        let uuids: [UUID]
        if let s = call.arguments as? String, let uuid = UUID(uuidString: s) {
          uuids = [uuid]
        } else {
          uuids = Array(self.arms.keys)
        }
        for uuid in uuids {
          self.releaseHandoffAndRearm(uuid, reason: "handoffExpired")
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
  }

  @objc private func appDidEnterBackground() { armIfAppropriate() }
  @objc private func appWillEnterForeground() {
    // Connected restore bands are handedOff until syncDone or an expired handoff releases
    // them. Keep those links across foregrounding and cancel every other peripheral.
    log("[ble-restore] appWillEnterForeground — cancelling pending connections")
    for uuid in Array(arms.keys) {
      let s = state(uuid)
      if s.peripheral?.state == .connected {
        log("[ble-restore] foreground — keeping connected restore peripheral \(uuid.uuidString) until syncDone/setOwnsBand")
      } else {
        cancelPending(uuid)
      }
    }
  }

  // MARK: - Pending connect

  private func armIfAppropriate() {
    // Process-level guards, evaluated once (unchanged from today, same log text).
    guard let central = central else { log("[ble-restore] skip arm — no central"); return }
    guard central.state == .poweredOn else {
      log("[ble-restore] skip arm — central not poweredOn (state=\(central.state.rawValue))"); return
    }
    if UIApplication.shared.applicationState == .active {
      log("[ble-restore] skip arm — app active"); return
    }
    guard !arms.isEmpty else { log("[ble-restore] skip arm — no bandUUID"); return }

    // Write `Array(arms.keys)`, not `arms.keys` directly — the loop body mutates `arms`,
    // and iterating the live Keys view while doing so is a mutation-during-iteration hazard.
    for uuid in Array(arms.keys) {
      var s = state(uuid)
      let tag = uuid.uuidString
      if s.appOwnsBand { log("[ble-restore] skip arm \(tag) — app owns band"); continue }
      if s.peripheral?.state == .connected {
        log("[ble-restore] skip arm \(tag) — restore peripheral already connected"); continue
      }
      if s.handedOff { log("[ble-restore] skip arm \(tag) — handedOff"); continue }
      if s.idleAfterSync {
        log("[ble-restore] skip arm \(tag) — idle after sync (awaiting re-arm)"); continue
      }
      // Already holding a pending connect for this one — arming again is a no-op that
      // would drop and re-take the retain.
      if s.peripheral != nil { continue }
      guard let p = central.retrievePeripherals(withIdentifiers: [uuid]).first else {
        log("[ble-restore] band \(tag) not retrievable yet"); continue
      }
      s.peripheral = p
      arms[uuid] = s
      central.connect(p, options: nil)  // no timeout → persists, relaunches us when reachable
      log("[ble-restore] armed pending connect \(tag)")
    }
  }

  private func cancelPending(_ uuid: UUID? = nil) {
    guard let uuid = uuid else {
      for (_, s) in arms {
        if let p = s.peripheral { central?.cancelPeripheralConnection(p) }
      }
      for key in arms.keys { arms[key]?.peripheral = nil }
      return
    }
    if let p = arms[uuid]?.peripheral { central?.cancelPeripheralConnection(p) }
    arms[uuid]?.peripheral = nil
  }

  private func disarm(_ uuid: UUID? = nil) {
    guard let uuid = uuid else {
      cancelPending()
      arms = [:]
      clearBandUUIDs()
      bandUUID = nil
      // Release the restore central so the process has NO CBCentralManager again. This
      // matters when the user unpairs and then re-pairs in the same app session: ASK's
      // showPicker fails with "CBManager is active with global permissions" if a central is
      // still alive. Dropping our strong reference lets CoreBluetooth tear it down; a fresh
      // one is re-created on the next provision/arm. (flutter_blue_plus's central is also
      // disconnected by AppState.unpair → engine.disconnect before re-pairing.)
      if central != nil {
        central?.delegate = nil
        central = nil
        log("[ble-restore] disarmed — restore central released")
      } else {
        log("[ble-restore] disarmed")
      }
      return
    }
    cancelPending(uuid)
    arms.removeValue(forKey: uuid)
    clearBandUUIDs(uuid)
    if bandUUID == uuid { bandUUID = nil }
    if arms.isEmpty, central != nil {
      central?.delegate = nil
      central = nil
      log("[ble-restore] disarmed \(uuid.uuidString) — restore central released (no bands left)")
    } else {
      log("[ble-restore] disarmed \(uuid.uuidString)")
    }
  }

  // MARK: - Wake → Flutter

  private func signalWake(_ uuid: UUID) {
    beginBackground()
    if flutterReady {
      channel?.invokeMethod("wake", arguments: nil)
      startWakeWatchdog(uuid)
      log("[ble-restore] wake → Flutter")
    } else {
      wakeQueuedBeforeReady = true
      log("[ble-restore] wake queued (Flutter not ready)")
    }
  }

  private func startWakeWatchdog(_ uuid: UUID) {
    // Only an unacknowledged wake may expire. Once Dart accepts it, Dart
    // ends it with syncDone or handoffExpired; suspension must not consume its budget.
    let generation = state(uuid).handoffGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
      guard let self = self else { return }
      let s = self.state(uuid)
      guard s.handoffGeneration == generation, s.handedOff else { return }
      if s.wakeAcknowledged {
        self.log("[ble-restore] wake watchdog skipped — Dart acknowledged handoff \(uuid.uuidString)")
        return
      }
      self.releaseHandoffAndRearm(uuid, reason: "unacknowledged wake watchdog")
    }
  }

  private func releaseHandoffAndRearm(_ uuid: UUID, reason: String) {
    guard var s = arms[uuid], s.handedOff else { return }
    log("[ble-restore] \(reason) — releasing handoff and re-arming pending connect \(uuid.uuidString)")
    s.handedOff = false
    s.wakeAcknowledged = false
    s.idleAfterSync = false
    arms[uuid] = s
    logArmState(uuid)
    let wasConnected = s.peripheral?.state == .connected
    cancelPending(uuid)
    // Connected links re-arm in didDisconnect after this central releases them.
    if !wasConnected { armIfAppropriate() }
    if !arms.values.contains(where: { $0.handedOff }) { endBackground() }
  }

  private func beginBackground() {
    endBackground()
    bgTask = UIApplication.shared.beginBackgroundTask(withName: "openstrap.bleSync") { [weak self] in
      guard let self = self else { return }
      self.log("[ble-restore] background task expired — releasing unacknowledged handoffs")
      for uuid in Array(self.arms.keys) {
        let s = self.state(uuid)
        if s.handedOff && !s.wakeAcknowledged {
          self.releaseHandoffAndRearm(uuid, reason: "background task expiration")
        }
      }
      self.endBackground()
    }
  }
  private func endBackground() {
    if bgTask != .invalid {
      UIApplication.shared.endBackgroundTask(bgTask)
      bgTask = .invalid
    }
  }

  // MARK: - Persistence

  /// Every provisioned band's peripheral UUID.
  ///
  /// MIGRATION, and the order matters: read the NEW list first, fall back to the OLD
  /// scalar, and never delete the scalar. An install that upgrades and then rolls back
  /// (TestFlight, a reverted build) still finds its band under the old key; an install
  /// that upgrades and never rolls back reads the list from the first launch after the
  /// first save. The scalar costs 36 bytes forever, which is the entire price of never
  /// having to be right about this on a phone we cannot debug.
  private func loadBandUUIDs() -> [UUID] {
    let d = UserDefaults.standard
    if let list = d.stringArray(forKey: BleRestoreManager.bandUUIDsKey), !list.isEmpty {
      return list.compactMap(UUID.init(uuidString:))
    }
    // Pre-M4 install: the scalar is the only record. Do NOT write the list here —
    // a read must not have a side effect, and `start()` runs before Dart is alive.
    if let one = d.string(forKey: BleRestoreManager.bandUUIDKey),
       let u = UUID(uuidString: one) {
      return [u]
    }
    return []
  }

  /// Additive. Writes BOTH keys: the list gains the uuid, and the scalar keeps naming
  /// the PRIMARY (the first band ever provisioned) so a rollback still reconnects it.
  private func saveBandUUID(_ u: UUID) {
    let d = UserDefaults.standard
    var list = d.stringArray(forKey: BleRestoreManager.bandUUIDsKey) ?? []
    if list.isEmpty, let legacy = d.string(forKey: BleRestoreManager.bandUUIDKey) {
      list = [legacy]                       // carry the pre-M4 band across, in position 0
    }
    let s = u.uuidString
    if !list.contains(s) { list.append(s) }
    d.set(list, forKey: BleRestoreManager.bandUUIDsKey)
    if d.string(forKey: BleRestoreManager.bandUUIDKey) == nil {
      d.set(s, forKey: BleRestoreManager.bandUUIDKey)   // first band ever = the mirror
    }
  }

  /// nil = forget everything (unpair). A uuid = forget one, and the scalar mirror is
  /// only cleared when the list empties, never when a secondary is removed.
  private func clearBandUUIDs(_ u: UUID? = nil) {
    let d = UserDefaults.standard
    guard let u = u else {
      d.removeObject(forKey: BleRestoreManager.bandUUIDsKey)
      d.removeObject(forKey: BleRestoreManager.bandUUIDKey)
      return
    }
    var list = (d.stringArray(forKey: BleRestoreManager.bandUUIDsKey) ?? loadBandUUIDs().map(\.uuidString))
    list.removeAll { $0 == u.uuidString }
    if list.isEmpty {
      d.removeObject(forKey: BleRestoreManager.bandUUIDsKey)
      d.removeObject(forKey: BleRestoreManager.bandUUIDKey)
    } else {
      d.set(list, forKey: BleRestoreManager.bandUUIDsKey)
      if d.string(forKey: BleRestoreManager.bandUUIDKey) == u.uuidString {
        d.set(list[0], forKey: BleRestoreManager.bandUUIDKey)
      }
    }
  }
}

extension BleRestoreManager: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    log("[ble-restore] central state=\(central.state.rawValue)")
    if central.state == .poweredOn { armIfAppropriate() }
  }

  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
    guard !restored.isEmpty else { return }
    // Take ALL of them, not just the first — the count was already being logged, so the
    // code always knew there could be more. Each carries a pending/active connect
    // bluetoothd preserved for us. An already-connected band needs the same handoff
    // as didConnect because restoration need not deliver another didConnect callback.
    // Keep retaining a restored peripheral whose UUID is not in `arms` (band we have
    // since forgotten): bluetoothd preserved a connect for it and dropping the retain
    // loses the ability to cancel it. Insert a default entry so the retain has a home;
    // didConnect below still refuses to wake Dart for it.
    let knownBands = Set(arms.keys)
    for p in restored {
      arms[p.identifier, default: ArmState()].peripheral = p
      if p.state == .connected && knownBands.contains(p.identifier) {
        centralManager(central, didConnect: p)
      }
    }
    log("[ble-restore] willRestoreState restored \(restored.count) peripheral(s)")
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    let uuid = peripheral.identifier
    guard arms[uuid] != nil else {
      log("[ble-restore] didConnect for unknown band \(uuid.uuidString) — cancelling")
      central.cancelPeripheralConnection(peripheral)
      return
    }
    log("[ble-restore] didConnect \(uuid.uuidString) — handing off to flutter_blue_plus")
    arms[uuid]?.handoffGeneration += 1
    arms[uuid]?.handedOff = true
    arms[uuid]?.wakeAcknowledged = false
    logArmState(uuid)
    signalWake(uuid)
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    let uuid = peripheral.identifier
    if arms[uuid]?.peripheral === peripheral {
      arms[uuid]?.peripheral = nil
    }
    let handedOff = state(uuid).handedOff
    let nativeError = error as NSError?
    log("[ble-restore] didDisconnect \(uuid.uuidString) (handedOff=\(handedOff)) code=\(nativeError.map { String($0.code) } ?? "none") description=\(error?.localizedDescription ?? "none")")
    // Re-arm only if our own pending connect dropped while still in recovery mode (band
    // went away again). armIfAppropriate's idleAfterSync/appOwnsBand guards prevent loops.
    if !handedOff { armIfAppropriate() }
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    let uuid = peripheral.identifier
    arms[uuid]?.peripheral = nil
    let nativeError = error as NSError?
    log("[ble-restore] didFailToConnect \(uuid.uuidString) code=\(nativeError.map { String($0.code) } ?? "none") description=\(error?.localizedDescription ?? "none")")
    if !state(uuid).handedOff { armIfAppropriate() }
  }
}
