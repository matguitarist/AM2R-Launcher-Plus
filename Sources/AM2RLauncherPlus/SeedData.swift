import Foundation
import SwiftData

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// store with profiles a person can get by installing from AM2R 1.1.
@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let context = model.container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<Profile>())) ?? 0) == 0 else { return }
        let older = Profile(name: "Community Updates 1.5.4", version: "1.5.4")
        older.engine = .rosetta
        older.installedAt = Date.now.addingTimeInterval(-90 * 86_400)
        older.playTime = 11 * 3_600
        context.insert(older)
        let current = Profile(name: "Community Updates 1.5.5", version: "1.5.5")
        current.lastPlayedAt = Date.now.addingTimeInterval(-3_600)
        current.playTime = 2 * 3_600 + 14 * 60
        context.insert(current)
        try? context.save()
        model.selection = current.id
    }
}
