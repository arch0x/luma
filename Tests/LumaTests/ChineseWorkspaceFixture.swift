import Foundation
@testable import Luma

/// Existing interaction fixtures assert Chinese labels; default-language tests use Workspace directly.
@MainActor func chineseWorkspace(preferences: UserDefaults = .standard, autoSaveDelay: Duration = .seconds(1)) -> Workspace {
    let workspace = Workspace(preferences: preferences, autoSaveDelay: autoSaveDelay)
    workspace.language = .simplifiedChinese
    return workspace
}
