// PROTOTYPE — throwaway. Lives on the `prototype/queue-pane` branch only.
// Pieces every queue pane variant shares: the pane's empty and no-permission
// states, the priority menu, the Bundle context menu, the remove
// confirmation, and the bottom bar.

import AppKit
import SwiftUI

enum QueueFormat {
  static func bytes(_ value: Int64) -> String { value.formatted(.byteCount(style: .binary)) }
  static func speed(_ value: Int64) -> String { value == 0 ? "" : bytes(value) + "/s" }
  static func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(1))) }

  static func timeLeft(_ seconds: Int?) -> String {
    guard let seconds else { return "" }
    return Duration.seconds(seconds).formatted(.units(allowed: [.days, .hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
  }

  static func added(_ date: Date) -> String { date.formatted(.relative(presentation: .named)) }
}

/// The pane under the detail area, in the current variant — or the state
/// that replaces it.
struct QueuePaneView: View {
  @Environment(QueueLab.self) private var lab

  var body: some View {
    Group {
      if !lab.permissions.queueView {
        ContentUnavailableView(
          "Queue Unavailable", systemImage: "lock",
          description: Text("Your web user on the Daemon doesn't have permission to view the queue."))
      } else if lab.bundles.isEmpty {
        ContentUnavailableView(
          "No Downloads", systemImage: "arrow.down.circle",
          description: Text("Download files from a search, a file list or a magnet link in chat."))
      } else {
        switch lab.variant {
        case .outline: OutlineQueueView()
        case .downloads: DownloadsQueueView()
        case .inspector: InspectorQueueView()
        }
      }
    }
    .frame(minHeight: 140, idealHeight: 220)
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        lab.tick()
      }
    }
  }
}

/// The Web UI's priority dropdown: every priority, Paused ones included, plus Auto.
struct PriorityMenuItems: View {
  let bundle: QueueBundle
  @Environment(QueueLab.self) private var lab

  var body: some View {
    ForEach(QueuePriority.allCases.reversed(), id: \.self) { priority in
      Toggle(priority.label, isOn: .init(
        get: { bundle.priority == priority && !(bundle.autoPriority && !priority.isPaused) },
        set: { _ in lab.setPriority(priority, auto: false, of: bundle.id) }))
    }
    Divider()
    Toggle("Auto", isOn: .init(
      get: { bundle.autoPriority && !bundle.priority.isPaused },
      set: { _ in lab.setPriority(.normal, auto: true, of: bundle.id) }))
  }
}

/// Priority without the Paused values — for variants where pause is its own control.
struct RunningPriorityItems: View {
  let bundle: QueueBundle
  @Environment(QueueLab.self) private var lab

  var body: some View {
    Toggle("Auto", isOn: .init(
      get: { bundle.autoPriority },
      set: { _ in lab.setPriority(.normal, auto: true, of: bundle.id) }))
    Divider()
    ForEach(QueuePriority.running.reversed(), id: \.self) { priority in
      Toggle(priority.label, isOn: .init(
        get: { !bundle.autoPriority && (bundle.priority == priority || bundle.priorityBeforePause == priority) },
        set: { _ in lab.setPriority(priority, auto: false, of: bundle.id) }))
    }
  }
}

/// The context menu for a selection of Bundles, in the order the Web UI uses.
struct BundleContextMenu: View {
  let ids: Set<Int>
  var pauseIsPriority = false
  @Environment(QueueLab.self) private var lab

  private var selected: [QueueBundle] { lab.bundles.filter { ids.contains($0.id) } }
  private var active: [QueueBundle] { selected.filter { !$0.isFinished } }

  var body: some View {
    let canEdit = lab.permissions.queueEdit
    if !pauseIsPriority, !active.isEmpty {
      if active.allSatisfy(\.priority.isPaused) {
        Button("Resume") { lab.resume(active.map(\.id)) }.disabled(!canEdit)
      } else {
        Button("Pause") { lab.pause(active.map(\.id)) }.disabled(!canEdit)
      }
    }
    if active.count == 1, let bundle = active.first {
      Menu("Priority") {
        if pauseIsPriority { PriorityMenuItems(bundle: bundle) } else { RunningPriorityItems(bundle: bundle) }
      }
      .disabled(!canEdit)
    }
    if !active.isEmpty {
      Divider()
      Button("Search for Alternates") { lab.searchForAlternates(active.map(\.id)) }.disabled(!canEdit)
      Button("Search for “\(active.first!.name)”") { lab.lastAction = "Opens a search Session" }
        .disabled(active.count != 1)
    }
    Divider()
    Button("Copy Name") { NSPasteboard.general.setString(selected.map(\.name).joined(separator: "\n"), forType: .string) }
    Button("Copy Daemon Path") { NSPasteboard.general.setString(selected.map(\.target).joined(separator: "\n"), forType: .string) }
    Divider()
    Button(selected.count > 1 ? "Remove \(selected.count) Bundles…" : "Remove…") {
      RemoveConfirmation.run(selected, lab: lab)
    }
    .disabled(!canEdit || selected.isEmpty)
  }
}

/// NSAlert with a checkbox for `remove_finished`. Default leaves files alone.
enum RemoveConfirmation {
  static func run(_ bundles: [QueueBundle], lab: QueueLab) {
    guard !bundles.isEmpty else { return }
    let alert = NSAlert()
    alert.messageText = bundles.count == 1 ? "Remove “\(bundles[0].name)” from the Queue?" : "Remove \(bundles.count) Bundles from the Queue?"
    alert.informativeText = "Unfinished files are deleted from the Daemon's disk. Finished files are kept unless you choose to delete them too."
    alert.addButton(withTitle: "Remove")
    alert.addButton(withTitle: "Cancel")
    alert.buttons[0].hasDestructiveAction = true
    alert.showsSuppressionButton = true
    alert.suppressionButton?.title = "Also delete finished files"
    alert.suppressionButton?.state = .off
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    lab.remove(bundles.map(\.id), deletingFinished: alert.suppressionButton?.state == .on)
  }
}

/// A Bundle's progress, coloured by state.
struct BundleProgress: View {
  let bundle: QueueBundle

  var body: some View {
    ProgressView(value: bundle.progress)
      .progressViewStyle(.linear)
      .tint(tint)
      .controlSize(.small)
  }

  private var tint: Color {
    if bundle.status == .downloadError { return .red }
    if bundle.isFinished { return .green }
    if bundle.priority.isPaused { return .gray }
    return .accentColor
  }
}

struct BundleIcon: View {
  let bundle: QueueBundle

  var body: some View {
    Image(systemName: bundle.isDirectory ? "folder.fill" : "doc.fill")
      .foregroundStyle(bundle.isDirectory ? Color.accentColor : .secondary)
  }
}

/// Settled: ↓/↑ totals and queue size on the left, Show/Hide Queue on the right.
struct QueueBottomBar: View {
  var showsPauseAll = false
  @Environment(QueueLab.self) private var lab

  var body: some View {
    HStack(spacing: 10) {
      Label(QueueFormat.speed(lab.downSpeed).ifEmpty("0 B/s"), systemImage: "arrow.down")
      Label("1 KiB/s", systemImage: "arrow.up")
      Text("·")
      Text(queueSize)
      if showsPauseAll, lab.permissions.queueView {
        Button(lab.allPaused ? "Resume All" : "Pause All", systemImage: lab.allPaused ? "play.fill" : "pause.fill") {
          lab.allPaused ? lab.resumeAll() : lab.pauseAll()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .disabled(!lab.permissions.queueEdit || lab.activeCount == 0)
        .help(lab.allPaused ? "Resume All Downloads" : "Pause All Downloads")
      }
      Spacer()
      Button(lab.paneVisible ? "Hide Queue" : "Show Queue", systemImage: "rectangle.bottomthird.inset.filled") {
        lab.paneVisible.toggle()
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .help(lab.paneVisible ? "Hide Queue (⌥⌘L)" : "Show Queue (⌥⌘L)")
    }
    .labelStyle(.titleAndIcon)
    .monospacedDigit()
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
  }

  private var queueSize: String {
    guard lab.permissions.queueView else { return "Queue —" }
    guard lab.activeCount > 0 else { return "Queue empty" }
    return "\(lab.activeCount) Bundles, \(QueueFormat.bytes(lab.bytesLeft)) left"
  }
}

extension String {
  func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
