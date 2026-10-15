// PROTOTYPE — throwaway. Lives on the `prototype/queue-pane` branch only.
//
// Question: What does the queue pane look like, and what does pause mean?
// Three layouts of the pane under the detail area, switchable from the
// floating bar or the Prototype menu (⌃⌘← / ⌃⌘→):
//
//   A — Outline: a sortable, customisable outline; Pause is a priority in
//       the Priority column's popup (the Web UI's model, made native)
//   B — Downloads list: Safari/Transmission-style two-line rows, a pause
//       button on each row, priority only in the context menu
//   C — Outline + inspector: a compact outline, the selected Bundle's
//       priority, pause, sources and actions in an inspector beside it
//   D — A's outline made Mac-native: Pause/Resume and Priority are
//       commands on the selection (context menu, Queue menu); the Priority
//       column is plain text; paused rows are dimmed
//   E — D plus a pause/resume button beside each Bundle's progress bar
//
// Every variant: Bundle rows expand to their files (fetched on expansion),
// Remove confirms with "Also delete finished files", and the Queue menu has
// Pause All / Resume All / Remove Completed.

import AppKit
import SwiftUI

// MARK: - Shared row model for the outline variants

nonisolated struct QueueRow: Identifiable {
  enum Kind {
    case bundle(QueueBundle)
    case file(QueueFile, bundleID: Int)
    case loading(Int)
  }

  let id: String
  let kind: Kind
  let name: String
  let size: Int64
  let progress: Double
  let speed: Int64
  let secondsLeft: Int
  let status: String
  let sources: Int
  let priority: Int
  let added: Date
  var content = ""
  var location = ""

  init(_ bundle: QueueBundle) {
    id = QueueRowID.bundle(bundle.id)
    kind = .bundle(bundle)
    name = bundle.name
    size = bundle.size
    progress = bundle.progress
    speed = bundle.speed
    secondsLeft = bundle.secondsLeft ?? .max
    status = bundle.statusText
    sources = bundle.sourcesOnline
    priority = bundle.isFinished ? -2 : bundle.priority.rawValue
    added = bundle.added
    content = bundle.contentText
    location = bundle.target
  }

  init(_ file: QueueFile, in bundle: QueueBundle) {
    id = QueueRowID.file(file.id)
    kind = .file(file, bundleID: bundle.id)
    name = file.name
    size = file.size
    progress = file.progress
    speed = file.speed
    secondsLeft = file.speed > 0 ? Int((file.size - file.downloaded) / file.speed) : .max
    status = file.isFinished ? "Finished" : file.speed > 0 ? "Downloading" : bundle.priority.isPaused ? "Paused" : "Waiting"
    sources = 0
    priority = file.priority.rawValue
    added = bundle.added
  }

  init(loadingFor bundleID: Int) {
    id = "l\(bundleID)"
    kind = .loading(bundleID)
    name = "Loading files…"
    size = 0
    progress = 0
    speed = 0
    secondsLeft = .max
    status = ""
    sources = 0
    priority = 0
    added = .distantPast
  }

  var bundle: QueueBundle? {
    if case .bundle(let bundle) = kind { return bundle }
    return nil
  }
}

/// The rows under an expanded Bundle: a loading placeholder until the first
/// page arrives, then its files.
@MainActor func childRows(of bundle: QueueBundle, lab: QueueLab) -> [QueueRow] {
  guard let files = lab.files[bundle.id] else { return [QueueRow(loadingFor: bundle.id)] }
  return files.map { QueueRow($0, in: bundle) }
}

struct QueueNameCell: View {
  let row: QueueRow

  var body: some View {
    switch row.kind {
    case .bundle(let bundle):
      Label { Text(bundle.name).lineLimit(1) } icon: { BundleIcon(bundle: bundle) }
    case .file(let file, _):
      Label { Text(file.name).lineLimit(1) } icon: { Image(systemName: "doc").foregroundStyle(.secondary) }
    case .loading:
      HStack(spacing: 6) {
        ProgressView().controlSize(.mini)
        Text(row.name).foregroundStyle(.secondary)
      }
    }
  }
}

struct QueueProgressCell: View {
  let row: QueueRow

  var body: some View {
    switch row.kind {
    case .bundle(let bundle):
      HStack(spacing: 6) {
        BundleProgress(bundle: bundle).frame(minWidth: 50)
        Text(QueueFormat.percent(bundle.progress)).font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
      }
    case .file(let file, _):
      HStack(spacing: 6) {
        ProgressView(value: file.progress).controlSize(.mini).frame(minWidth: 50)
        Text(QueueFormat.percent(file.progress)).font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
      }
    case .loading: EmptyView()
    }
  }
}

struct FilePriorityMenu: View {
  let file: QueueFile
  let bundleID: Int
  @Environment(QueueLab.self) private var lab

  var body: some View {
    Menu(file.autoPriority ? "\(file.priority.label) (auto)" : file.priority.label) {
      ForEach(QueuePriority.allCases.reversed(), id: \.self) { priority in
        Button(priority.label) { lab.setFilePriority(priority, auto: false, file: file.id, in: bundleID) }
      }
      Divider()
      Button("Auto") { lab.setFilePriority(.normal, auto: true, file: file.id, in: bundleID) }
    }
    .menuStyle(.borderlessButton)
    .disabled(!lab.permissions.queueEdit || file.isFinished)
  }
}

// MARK: - A, D, E: Outline

/// How the outline lets people pause: A's priority popup in the cell, D's
/// commands on the selection, or E's commands plus a button on each row.
enum OutlineStyle {
  case priorityPopup, commands, commandsWithButton
}

struct OutlineQueueView: View {
  let style: OutlineStyle
  @Environment(QueueLab.self) private var lab
  @State private var sortOrder = [KeyPathComparator(\QueueRow.added, order: .reverse)]
  @SceneStorage("queueOutlineColumns") private var columns = TableColumnCustomization<QueueRow>()

  var body: some View {
    @Bindable var lab = lab
    Table(of: QueueRow.self, selection: $lab.selection, sortOrder: $sortOrder, columnCustomization: $columns) {
      TableColumn("Name", value: \.name) { QueueNameCell(row: $0).foregroundStyle(dims($0) ? .secondary : .primary) }
        .width(min: 160, ideal: 280)
        .customizationID("name")
        .disabledCustomizationBehavior(.visibility)
      TableColumn("Size", value: \.size) { Text(QueueFormat.bytes($0.size)).monospacedDigit() }
        .width(min: 60, ideal: 80)
        .customizationID("size")
      TableColumn("Progress", value: \.progress) { row in
        HStack(spacing: 6) {
          QueueProgressCell(row: row)
          if style == .commandsWithButton { PauseButton(row: row) }
        }
      }
        .width(min: 90, ideal: 140)
        .customizationID("progress")
      TableColumn("Status", value: \.status) { statusCell($0) }
      .width(min: 70, ideal: 110)
      .customizationID("status")
      TableColumn("Speed", value: \.speed) { Text(QueueFormat.speed($0.speed)).monospacedDigit() }
        .width(min: 60, ideal: 80)
        .customizationID("speed")
      TableColumn("Time Left", value: \.secondsLeft) { Text(QueueFormat.timeLeft($0.secondsLeft == .max ? nil : $0.secondsLeft)).monospacedDigit() }
        .width(min: 60, ideal: 80)
        .customizationID("timeLeft")
      TableColumn("Sources", value: \.sources) { Text($0.bundle?.sourcesText ?? "").monospacedDigit() }
        .width(min: 50, ideal: 60)
        .customizationID("sources")
      TableColumn("Priority", value: \.priority) { priorityCell($0) }
        .width(min: 90, ideal: 120)
        .customizationID("priority")
      Group {
      TableColumn("Added", value: \QueueRow.added) { row in Text(row.bundle.map { QueueFormat.added($0.added) } ?? "") }
        .width(min: 70, ideal: 100)
        .customizationID("added")
        .defaultVisibility(.hidden)
      TableColumn("Content", value: \QueueRow.content) { row in Text(row.content) }
        .width(min: 70, ideal: 110)
        .customizationID("content")
        .defaultVisibility(.hidden)
      TableColumn("Location", value: \QueueRow.location) { row in Text(row.location).truncationMode(.middle) }
        .width(min: 90, ideal: 200)
        .customizationID("location")
        .defaultVisibility(.hidden)
      }
    } rows: {
      ForEach(lab.bundles.map(QueueRow.init).sorted(using: sortOrder)) { row in
        if let bundle = row.bundle, bundle.isDirectory {
          DisclosureTableRow(row, isExpanded: expansion(of: bundle.id)) {
            ForEach(childRows(of: bundle, lab: lab).sorted(using: sortOrder)) { TableRow($0) }
          }
        } else {
          TableRow(row)
        }
      }
    }
    .contextMenu(forSelectionType: String.self) { ids in
      let bundleIDs = Set(ids.compactMap(QueueRowID.bundleID))
      if bundleIDs.isEmpty, style != .priorityPopup {
        FileContextMenu(fileIDs: Set(ids.compactMap(QueueRowID.fileID)))
      } else {
        BundleContextMenu(ids: bundleIDs, pauseIsPriority: style == .priorityPopup)
      }
    }
    .onDeleteCommand { RemoveConfirmation.run(lab.bundles.filter { lab.selection.contains(QueueRowID.bundle($0.id)) }, lab: lab) }
  }

  /// D and E dim paused Bundles instead of putting a control in the row.
  private func dims(_ row: QueueRow) -> Bool {
    guard style != .priorityPopup, let bundle = row.bundle else { return false }
    return bundle.priority.isPaused && !bundle.isFinished
  }

  @ViewBuilder private func statusCell(_ row: QueueRow) -> some View {
    HStack(spacing: 4) {
      if dims(row) { Image(systemName: "pause.fill").font(.caption2) }
      Text(row.status)
    }
    .foregroundStyle(row.bundle?.status == .downloadError ? .red : dims(row) ? .secondary : .primary)
  }

  @ViewBuilder private func priorityCell(_ row: QueueRow) -> some View {
    switch row.kind {
    case .bundle(let bundle) where style != .priorityPopup:
      Text(bundle.priorityText).foregroundStyle(dims(row) ? .secondary : .primary)
    case .file(let file, _) where style != .priorityPopup:
      Text(file.autoPriority ? "\(file.priority.label) (auto)" : file.priority.label).foregroundStyle(.secondary)
    case .bundle(let bundle) where !bundle.isFinished:
      Menu(bundle.priorityText) { PriorityMenuItems(bundle: bundle) }
        .menuStyle(.borderlessButton)
        .foregroundStyle(bundle.priority.isPaused ? .secondary : .primary)
        .disabled(!lab.permissions.queueEdit)
        .help(lab.permissions.queueEdit ? "" : "Your web user can't change the queue.")
    case .file(let file, let bundleID):
      FilePriorityMenu(file: file, bundleID: bundleID)
    default:
      EmptyView()
    }
  }

  private func expansion(of id: Int) -> Binding<Bool> {
    .init(get: { lab.expanded.contains(id) }, set: { lab.setExpanded(id, $0) })
  }
}

/// E: Safari-style pause/resume beside a Bundle's progress bar.
struct PauseButton: View {
  let row: QueueRow
  @Environment(QueueLab.self) private var lab

  var body: some View {
    if let bundle = row.bundle, !bundle.isFinished {
      Button(bundle.priority.isPaused ? "Resume" : "Pause", systemImage: bundle.priority.isPaused ? "play.circle.fill" : "pause.circle.fill") {
        lab.togglePause(bundle.id)
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
      .disabled(!lab.permissions.queueEdit)
      .help(bundle.priority.isPaused ? "Resume" : "Pause")
    } else {
      Color.clear.frame(width: 16)
    }
  }
}

/// D and E: file rows set their priority from the context menu.
struct FileContextMenu: View {
  let fileIDs: Set<Int>
  @Environment(QueueLab.self) private var lab

  var body: some View {
    if fileIDs.count == 1, let id = fileIDs.first, let (file, bundleID) = lab.file(id), !file.isFinished {
      Menu("Priority") {
        Toggle("Auto", isOn: .init(get: { file.autoPriority }, set: { _ in lab.setFilePriority(.normal, auto: true, file: id, in: bundleID) }))
        Divider()
        ForEach(QueuePriority.allCases.reversed(), id: \.self) { priority in
          Toggle(priority.label, isOn: .init(
            get: { !file.autoPriority && file.priority == priority },
            set: { _ in lab.setFilePriority(priority, auto: false, file: id, in: bundleID) }))
        }
      }
      .disabled(!lab.permissions.queueEdit)
    }
    Button("Copy Name") {
      let names = fileIDs.compactMap { lab.file($0)?.file.name }
      NSPasteboard.general.setString(names.joined(separator: "\n"), forType: .string)
    }
  }
}

// MARK: - B: Downloads list

struct DownloadsQueueView: View {
  @Environment(QueueLab.self) private var lab

  var body: some View {
    @Bindable var lab = lab
    VStack(spacing: 0) {
      header
      Divider()
      List(selection: $lab.selection) {
        ForEach(lab.bundles) { bundle in
          DownloadRow(bundle: bundle).tag(QueueRowID.bundle(bundle.id))
          if bundle.isDirectory, lab.expanded.contains(bundle.id) {
            ForEach(childRows(of: bundle, lab: lab)) { row in
              DownloadFileRow(row: row).tag(row.id)
            }
          }
        }
      }
      .listStyle(.inset)
      .alternatingRowBackgrounds()
      .contextMenu(forSelectionType: String.self) { ids in
        BundleContextMenu(ids: Set(ids.compactMap(QueueRowID.bundleID)))
      }
      .onDeleteCommand { RemoveConfirmation.run(lab.bundles.filter { lab.selection.contains(QueueRowID.bundle($0.id)) }, lab: lab) }
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Text("Downloads").font(.headline)
      Text("\(lab.activeCount) of \(lab.bundles.count) unfinished").foregroundStyle(.secondary)
      Spacer()
      Button(lab.allPaused ? "Resume All" : "Pause All", systemImage: lab.allPaused ? "play.fill" : "pause.fill") {
        lab.allPaused ? lab.resumeAll() : lab.pauseAll()
      }
      .disabled(!lab.permissions.queueEdit || lab.activeCount == 0)
      Button("Clear Completed") { lab.removeCompleted() }
        .disabled(!lab.permissions.queueEdit || !lab.bundles.contains(where: \.isFinished))
    }
    .buttonStyle(.borderless)
    .font(.callout)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
  }
}

struct DownloadRow: View {
  let bundle: QueueBundle
  @Environment(QueueLab.self) private var lab
  @State private var showsSources = false

  var body: some View {
    HStack(spacing: 10) {
      disclosure
      BundleIcon(bundle: bundle).font(.title2).frame(width: 26)
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(bundle.name).fontWeight(.medium).lineLimit(1)
          if bundle.autoPriority, !bundle.priority.isPaused, !bundle.isFinished {
            Text(bundle.priority.label).font(.caption2).foregroundStyle(.secondary)
              .padding(.horizontal, 4).background(.quaternary, in: Capsule())
          } else if !bundle.priority.isPaused, !bundle.isFinished {
            Text(bundle.priority.label).font(.caption2.bold()).foregroundStyle(.secondary)
              .padding(.horizontal, 4).background(.quaternary, in: Capsule())
          }
        }
        if !bundle.isFinished { BundleProgress(bundle: bundle) }
        HStack(spacing: 0) {
          Text(detail).foregroundStyle(bundle.status == .downloadError ? .red : .secondary)
          if !bundle.isFinished {
            Text(" · ").foregroundStyle(.secondary)
            Button("\(bundle.sourcesOnline) of \(bundle.sources.count) sources") { showsSources = true }
              .buttonStyle(.link)
              .popover(isPresented: $showsSources) { SourcesList(bundle: bundle).frame(width: 420, height: 220) }
          }
        }
        .font(.caption)
        .monospacedDigit()
      }
      Spacer(minLength: 8)
      if !bundle.isFinished {
        Button(bundle.priority.isPaused ? "Resume" : "Pause", systemImage: bundle.priority.isPaused ? "play.circle.fill" : "pause.circle.fill") {
          lab.togglePause(bundle.id)
        }
        .labelStyle(.iconOnly)
        .font(.title2)
        .buttonStyle(.borderless)
        .disabled(!lab.permissions.queueEdit)
        .help(bundle.priority.isPaused ? "Resume" : "Pause")
      }
      Button("Remove", systemImage: "xmark.circle.fill") { RemoveConfirmation.run([bundle], lab: lab) }
        .labelStyle(.iconOnly)
        .font(.title2)
        .foregroundStyle(.secondary)
        .buttonStyle(.borderless)
        .disabled(!lab.permissions.queueEdit)
    }
    .padding(.vertical, 3)
  }

  @ViewBuilder private var disclosure: some View {
    if bundle.isDirectory {
      Button {
        lab.setExpanded(bundle.id, !lab.expanded.contains(bundle.id))
      } label: {
        Image(systemName: "chevron.right")
          .rotationEffect(.degrees(lab.expanded.contains(bundle.id) ? 90 : 0))
          .frame(width: 12)
      }
      .buttonStyle(.borderless)
    } else {
      Color.clear.frame(width: 12)
    }
  }

  private var detail: String {
    let sizes = "\(QueueFormat.bytes(bundle.downloaded)) of \(QueueFormat.bytes(bundle.size))"
    if bundle.isFinished { return "\(QueueFormat.bytes(bundle.size)) · \(bundle.statusText)" }
    if bundle.isRunning {
      return "\(sizes) · \(QueueFormat.speed(bundle.speed)) · \(QueueFormat.timeLeft(bundle.secondsLeft)) left" + (bundle.priority == .paused ? " · Pausing…" : "")
    }
    return "\(sizes) · \(bundle.statusText)"
  }
}

struct DownloadFileRow: View {
  let row: QueueRow

  var body: some View {
    HStack(spacing: 8) {
      QueueNameCell(row: row)
      Spacer()
      if case .file(let file, let bundleID) = row.kind {
        Text(QueueFormat.bytes(file.size)).foregroundStyle(.secondary)
        ProgressView(value: file.progress).controlSize(.mini).frame(width: 80)
        FilePriorityMenu(file: file, bundleID: bundleID).frame(width: 110)
      }
    }
    .font(.callout)
    .padding(.leading, 48)
  }
}

struct SourcesList: View {
  let bundle: QueueBundle
  @Environment(QueueLab.self) private var lab

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Table(bundle.sources) {
        TableColumn("User") { source in
          Label(source.nick, systemImage: source.online ? "person.fill" : "person")
            .foregroundStyle(source.online ? .primary : .secondary)
        }
        TableColumn("Hubs", value: \.hubs)
        TableColumn("Last Speed") { Text(QueueFormat.speed($0.lastSpeed)) }
        TableColumn("Files") { Text("\($0.files)") }.width(40)
      }
      .contextMenu(forSelectionType: QueueSource.ID.self) { nicks in
        Button("Send Private Message") {}
        Button("Browse File List") {}
        Divider()
        Button("Remove Source") { nicks.forEach { lab.removeSource($0, from: bundle.id) } }
          .disabled(!lab.permissions.queueEdit)
      }
      HStack {
        Button("Search for Alternates") { lab.searchForAlternates([bundle.id]) }
          .disabled(!lab.permissions.queueEdit)
        Spacer()
      }
      .padding(8)
    }
  }
}

// MARK: - C: Outline + inspector

struct InspectorQueueView: View {
  @Environment(QueueLab.self) private var lab
  @State private var sortOrder = [KeyPathComparator(\QueueRow.added, order: .reverse)]

  var body: some View {
    @Bindable var lab = lab
    HStack(spacing: 0) {
      Table(of: QueueRow.self, selection: $lab.selection, sortOrder: $sortOrder) {
        TableColumn("Name", value: \.name) { row in
          VStack(alignment: .leading, spacing: 2) {
            QueueNameCell(row: row)
            if let bundle = row.bundle, !bundle.isFinished { BundleProgress(bundle: bundle).padding(.leading, 22) }
          }
        }
        .width(min: 180, ideal: 320)
        TableColumn("Status", value: \.status) { row in
          HStack(spacing: 4) {
            if row.bundle?.priority.isPaused == true, row.bundle?.isFinished == false { Image(systemName: "pause.fill").font(.caption2) }
            Text(row.status)
          }
          .foregroundStyle(row.bundle?.status == .downloadError ? .red : .secondary)
        }
        .width(min: 70, ideal: 110)
        TableColumn("Speed", value: \.speed) { Text(QueueFormat.speed($0.speed)).monospacedDigit() }
          .width(min: 60, ideal: 80)
        TableColumn("Time Left", value: \.secondsLeft) { Text(QueueFormat.timeLeft($0.secondsLeft == .max ? nil : $0.secondsLeft)).monospacedDigit() }
          .width(min: 60, ideal: 80)
      } rows: {
        ForEach(lab.bundles.map(QueueRow.init).sorted(using: sortOrder)) { row in
          if let bundle = row.bundle, bundle.isDirectory {
            DisclosureTableRow(row, isExpanded: .init(get: { lab.expanded.contains(bundle.id) }, set: { lab.setExpanded(bundle.id, $0) })) {
              ForEach(childRows(of: bundle, lab: lab)) { TableRow($0) }
            }
          } else {
            TableRow(row)
          }
        }
      }
      .contextMenu(forSelectionType: String.self) { ids in
        BundleContextMenu(ids: Set(ids.compactMap(QueueRowID.bundleID)))
      }
      .onDeleteCommand { RemoveConfirmation.run(lab.bundles.filter { lab.selection.contains(QueueRowID.bundle($0.id)) }, lab: lab) }
      .frame(minWidth: 380)
      Divider()
      BundleInspector()
        .frame(width: 300)
    }
  }
}

struct BundleInspector: View {
  @Environment(QueueLab.self) private var lab

  private var bundle: QueueBundle? {
    let ids = lab.selection.compactMap(QueueRowID.bundleID)
    guard ids.count == 1 else { return nil }
    return lab.bundle(ids[0])
  }

  var body: some View {
    if let bundle {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .top) {
            BundleIcon(bundle: bundle).font(.largeTitle)
            VStack(alignment: .leading) {
              Text(bundle.name).font(.headline).lineLimit(2)
              Text(bundle.target).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
            }
          }
          BundleProgress(bundle: bundle)
          Text("\(QueueFormat.bytes(bundle.downloaded)) of \(QueueFormat.bytes(bundle.size)) (\(QueueFormat.percent(bundle.progress)))")
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
          if !bundle.isFinished { controls(bundle) }
          Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow { Text("Status").foregroundStyle(.secondary); Text(bundle.statusText).foregroundStyle(bundle.status == .downloadError ? .red : .primary) }
            GridRow { Text("Speed").foregroundStyle(.secondary); Text(QueueFormat.speed(bundle.speed).ifEmpty("—")) }
            GridRow { Text("Time left").foregroundStyle(.secondary); Text(QueueFormat.timeLeft(bundle.secondsLeft).ifEmpty("—")) }
            GridRow { Text("Content").foregroundStyle(.secondary); Text(bundle.contentText) }
            GridRow { Text("Added").foregroundStyle(.secondary); Text(QueueFormat.added(bundle.added)) }
          }
          .font(.callout)
          if !bundle.isFinished { sources(bundle) }
          HStack {
            Spacer()
            Button("Remove…", role: .destructive) { RemoveConfirmation.run([bundle], lab: lab) }
              .disabled(!lab.permissions.queueEdit)
          }
        }
        .padding(12)
      }
    } else {
      ContentUnavailableView(lab.selection.count > 1 ? "\(lab.selection.count) Selected" : "No Bundle Selected", systemImage: "info.circle")
    }
  }

  private func controls(_ bundle: QueueBundle) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        lab.togglePause(bundle.id)
      } label: {
        Label(bundle.priority.isPaused ? "Resume" : "Pause", systemImage: bundle.priority.isPaused ? "play.fill" : "pause.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      LabeledContent("Priority") {
        Picker("Priority", selection: .init(
          get: { bundle.autoPriority ? -1 : (bundle.priority.isPaused ? (bundle.priorityBeforePause ?? .normal).rawValue : bundle.priority.rawValue) },
          set: { value in
            if value == -1 { lab.setPriority(.normal, auto: true, of: bundle.id) }
            else if let priority = QueuePriority(rawValue: value) { lab.setPriority(priority, auto: false, of: bundle.id) }
          })) {
          Text("Auto").tag(-1)
          Divider()
          ForEach(QueuePriority.running.reversed(), id: \.self) { Text($0.label).tag($0.rawValue) }
        }
        .labelsHidden()
      }
      if bundle.autoPriority, !bundle.priority.isPaused {
        Text("The Daemon currently runs it at \(bundle.priority.label).").font(.caption).foregroundStyle(.secondary)
      }
    }
    .disabled(!lab.permissions.queueEdit)
  }

  private func sources(_ bundle: QueueBundle) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Sources").font(.headline)
        Text("\(bundle.sourcesOnline) of \(bundle.sources.count) online").foregroundStyle(.secondary)
        Spacer()
        Button("Search for Alternates", systemImage: "magnifyingglass") { lab.searchForAlternates([bundle.id]) }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .disabled(!lab.permissions.queueEdit)
          .help("Search for Alternates")
      }
      ForEach(bundle.sources) { source in
        HStack {
          Circle().fill(source.online ? .green : .secondary.opacity(0.4)).frame(width: 7, height: 7)
          Text(source.nick)
          Spacer()
          Text(QueueFormat.speed(source.lastSpeed)).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.callout)
        .help(source.hubs)
        .contextMenu {
          Button("Send Private Message") {}
          Button("Browse File List") {}
          Divider()
          Button("Remove Source") { lab.removeSource(source.nick, from: bundle.id) }.disabled(!lab.permissions.queueEdit)
        }
      }
    }
  }
}
