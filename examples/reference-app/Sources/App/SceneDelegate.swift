/// # Scene Delegate
/// @topic navigation
///
/// Minimal `UIWindowSceneDelegate` that stores the window scene reference.
/// In a production app, this would also handle scene-level deep links
/// via `scene(_:openURLContexts:)` and state restoration.
///
/// ## Key Rules
/// - Keep minimal — most logic belongs in TCA reducers
/// - Store `windowScene` for any UIKit presentation needs
/// - Deep links arriving at scene level should be forwarded to TCA

import UIKit

// MARK: - Scene Delegate

public final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    /// Reference to the connected window scene.
    public var windowScene: UIWindowScene?

    // MARK: - Scene Lifecycle

    public func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        windowScene = scene as? UIWindowScene
    }
}
