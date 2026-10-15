// PROTOTYPE — throwaway. Lives on the `prototype/queue-pane` branch only.
// The floating bar and menus that drive the queue pane prototype: variant,
// what Pause and Resume send, the web user's permissions, and Daemon events
// to simulate. The bar also shows the last API call a control would make.

import SwiftUI

/// The App's Queue menu — the same in every variant — plus the Prototype menu.
struct QueueCommands: Commands {
  let lab: QueueLab

  var body: some Commands {
    CommandMenu("Queue") {
      let selected = lab.selectedActiveBundles
      if !selected.isEmpty, selected.allSatisfy(\.priority.isPaused) {
        Button("Resume") { lab.resume(selected.map(\.id)) }.disabled(!lab.permissions.queueEdit)
      } else {
        Button("Pause") { lab.pause(selected.map(\.id)) }.disabled(!lab.permissions.queueEdit || selected.isEmpty)
      }
      Menu("Priority") {
        if selected.count == 1 { RunningPriorityItems(bundle: selected[0]).environment(lab) }
      }
      .disabled(!lab.permissions.queueEdit || selected.count != 1)
      Divider()
      Button("Pause All Downloads") { lab.pauseAll() }
        .keyboardShortcut("p", modifiers: [.command, .option])
        .disabled(!lab.permissions.queueEdit || lab.allPaused)
      Button("Resume All Downloads") { lab.resumeAll() }
        .keyboardShortcut("p", modifiers: [.command, .option, .shift])
        .disabled(!lab.permissions.queueEdit || !lab.bundles.contains { !$0.isFinished && $0.priority.isPaused })
      Divider()
      Button("Remove Completed") { lab.removeCompleted() }
        .disabled(!lab.permissions.queueEdit || !lab.bundles.contains(where: \.isFinished))
    }
    CommandMenu("Prototype") {
      ForEach(QueueVariant.allCases, id: \.self) { candidate in
        Toggle(candidate.label, isOn: .init(get: { lab.variant == candidate }, set: { _ in lab.variant = candidate }))
      }
      Divider()
      Button("Previous Variant") { lab.shift(by: -1) }.keyboardShortcut(.leftArrow, modifiers: [.command, .control])
      Button("Next Variant") { lab.shift(by: 1) }.keyboardShortcut(.rightArrow, modifiers: [.command, .control])
    }
  }
}

struct QueuePrototypeBar: View {
  @Environment(QueueLab.self) private var lab

  var body: some View {
    @Bindable var lab = lab
    VStack(spacing: 4) {
      HStack(spacing: 14) {
        Button { lab.shift(by: -1) } label: { Image(systemName: "chevron.left") }
        Text(lab.variant.label).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.tail).help(lab.variant.label)
        Button { lab.shift(by: 1) } label: { Image(systemName: "chevron.right") }
        Divider().frame(height: 14).overlay(.white.opacity(0.4))
        Menu("Pause sends…") {
          Picker("Pause sends", selection: $lab.pauseKind) {
            ForEach(PauseKind.allCases, id: \.self) { Text($0.label).tag($0) }
          }
          .pickerStyle(.inline)
          Picker("Resume sends", selection: $lab.resumeKind) {
            ForEach(ResumeKind.allCases, id: \.self) { Text($0.label).tag($0) }
          }
          .pickerStyle(.inline)
        }
        .fixedSize()
        Menu("Permissions") {
          Toggle("queue_view", isOn: $lab.permissions.queueView)
          Toggle("queue_edit", isOn: $lab.permissions.queueEdit)
        }
        .fixedSize()
        Menu("Daemon") {
          Button("Disk full (Daemon force-pauses a Bundle)") { lab.simulateDiskFull() }
          Button("Merge a file into a directory Bundle") { lab.simulateMerge() }
          Button("Queue a Bundle from the Web UI") { lab.simulateNewBundle() }
          Divider()
          Button("Empty the Queue") { lab.emptyQueue() }
          Button("Reset") { lab.resetQueue() }
        }
        .fixedSize()
      }
      Text(lab.lastAction).font(.caption.monospaced()).opacity(0.75).lineLimit(1).truncationMode(.middle)
    }
    .buttonStyle(.plain)
    .menuStyle(.button)
    .foregroundStyle(.white)
    .tint(.white)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .frame(maxWidth: 760)
    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
    .shadow(radius: 8)
    .padding(.bottom, 56)
  }
}
