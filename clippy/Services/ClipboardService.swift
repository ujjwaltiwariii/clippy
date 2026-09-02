//
//  ClipboardService.swift
//  clippy
//
//  The single @MainActor source of truth the UI observes. Wires together
//  monitoring, storage, and privacy settings.
//

import Foundation
import AppKit
import Combine

@MainActor
final class ClipboardService: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var searchText: String = ""
    @Published var isPaused: Bool {
        didSet { UserDefaults.standard.set(isPaused, forKey: DefaultsKey.isPaused) }
    }
    @Published var lastError: String?
    @Published var toastMessage: String?

    let repository: ClipboardRepositoryProtocol
    private let monitor: ClipboardMonitor
    private var searchDebounceTask: Task<Void, Never>?
    private var cleanupTimer: Timer?

    var settings: PrivacySettings

    init(repository: ClipboardRepositoryProtocol, monitor: ClipboardMonitor) {
        self.repository = repository
        self.monitor = monitor
        self.settings = PrivacySettings.loadFromDefaults()
        self.isPaused = UserDefaults.standard.bool(forKey: DefaultsKey.isPaused)

        monitor.isPaused = isPaused
        monitor.onNewContent = { [weak self] content in
            self?.handleNewContent(content)
        }
        monitor.start()

        Task { await reload() }
        scheduleCleanup()
    }

    private func handleNewContent(_ content: ClipboardContent) {
        Task {
            let sensitive = settings.detectSensitiveContent &&
                SensitiveDataDetector.isSensitive(content,
                                                   ignorePasswordManagers: settings.ignorePasswordManagers,
                                                   detectOTP: settings.autoDeleteOTP)
            if sensitive && settings.dontStoreSensitiveItems {
                return // never touches disk
            }
            if content.type == .image && !settings.saveImages { return }
            if content.type == .file && !settings.saveFiles { return }

            do {
                _ = try await repository.insertOrBump(content, isSensitive: sensitive)
                await reload()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func reload() async {
        do {
            let limit = max(settings.maxHistoryItems, 50)
            items = try await repository.search(query: searchText, limit: limit)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateSearch(_ text: String) {
        searchText = text
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    // MARK: - Actions

    func copyToPasteboard(_ item: ClipboardItem) {
        let changeCount = ClipboardWriter.write(item) { [repository] item in
            repository.imageData(for: item)
        }
        monitor.markSelfWrite(changeCount: changeCount)
        toastMessage = "Copied"
    }

    func togglePin(_ item: ClipboardItem) {
        Task {
            try? await repository.setPinned(item.id, pinned: !item.isPinned)
            await reload()
        }
    }

    func delete(_ item: ClipboardItem) {
        Task {
            try? await repository.delete(item.id)
            await reload()
        }
    }

    func clearHistory(keepPinned: Bool) {
        Task {
            try? await repository.clearAll(keepPinned: keepPinned)
            await reload()
        }
    }

    func togglePause() {
        isPaused.toggle()
        monitor.isPaused = isPaused
    }

    func imageData(for item: ClipboardItem) -> Data? {
        repository.imageData(for: item)
    }

    // MARK: - Retention

    private func scheduleCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                try? await self.repository.purgeExpired(after: TimeInterval(self.settings.autoDeleteAfter))
                await self.reload()
            }
        }
    }

    func persistSettings() {
        settings.saveToDefaults()
        Task { await reload() }
    }
}

/// Snapshot of the Privacy + Clipboard settings sections, backed by UserDefaults.
struct PrivacySettings {
    var maxHistoryItems: Int
    var autoDeleteAfter: Int
    var saveImages: Bool
    var saveFiles: Bool
    var detectSensitiveContent: Bool
    var dontStoreSensitiveItems: Bool
    var autoDeleteOTP: Bool
    var ignorePasswordManagers: Bool

    static func loadFromDefaults() -> PrivacySettings {
        let defaults = UserDefaults.standard
        return PrivacySettings(
            maxHistoryItems: defaults.object(forKey: DefaultsKey.maxHistoryItems) as? Int ?? AppConstants.defaultMaxHistoryItems,
            autoDeleteAfter: defaults.object(forKey: DefaultsKey.autoDeleteAfter) as? Int ?? AutoDeleteInterval.never.rawValue,
            saveImages: defaults.object(forKey: DefaultsKey.saveImages) as? Bool ?? true,
            saveFiles: defaults.object(forKey: DefaultsKey.saveFiles) as? Bool ?? true,
            detectSensitiveContent: defaults.object(forKey: DefaultsKey.detectSensitiveContent) as? Bool ?? true,
            dontStoreSensitiveItems: defaults.object(forKey: "dontStoreSensitiveItems") as? Bool ?? true,
            autoDeleteOTP: defaults.object(forKey: DefaultsKey.autoDeleteOTP) as? Bool ?? true,
            ignorePasswordManagers: defaults.object(forKey: DefaultsKey.ignorePasswordManagers) as? Bool ?? true
        )
    }

    func saveToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(maxHistoryItems, forKey: DefaultsKey.maxHistoryItems)
        defaults.set(autoDeleteAfter, forKey: DefaultsKey.autoDeleteAfter)
        defaults.set(saveImages, forKey: DefaultsKey.saveImages)
        defaults.set(saveFiles, forKey: DefaultsKey.saveFiles)
        defaults.set(detectSensitiveContent, forKey: DefaultsKey.detectSensitiveContent)
        defaults.set(dontStoreSensitiveItems, forKey: "dontStoreSensitiveItems")
        defaults.set(autoDeleteOTP, forKey: DefaultsKey.autoDeleteOTP)
        defaults.set(ignorePasswordManagers, forKey: DefaultsKey.ignorePasswordManagers)
    }
}
