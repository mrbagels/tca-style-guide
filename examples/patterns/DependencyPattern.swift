/// # Dependency Pattern
/// @topic dependency
///
/// Dependencies in TCA are declared using `@Dependency` and registered
/// via `DependencyKey`. This file demonstrates the client protocol pattern,
/// live/test implementations, and proper injection.
///
/// ## Key Rules
/// - Model dependencies as structs with closure properties (the "client" pattern)
/// - Register via `DependencyKey` with `liveValue` and `testValue`
/// - Access via `@Dependency(\.keyPath)` inside `@Reducer` structs
/// - Never access dependencies in State or View — only in the Reducer
/// - `testValue` should use `unimplemented()` to catch untested code paths
/// - `previewValue` provides safe defaults for SwiftUI previews

import ComposableArchitecture
import Foundation

// MARK: - Client Definition

/// Dependencies are modeled as structs with closure properties.
/// This enables easy mocking in tests and previews without protocols.
///
/// **Naming convention:** `[Domain]Client` (e.g., `ProfileClient`, `AuthClient`)
public struct ProfileClient {
    /// Each operation is a closure property — mockable independently
    var fetch: @Sendable () async -> Result<Profile, Error>
    var update: @Sendable (String) async -> Result<Profile, Error>
    var delete: @Sendable (Profile.ID) async -> Result<Void, Error>
}

// MARK: - Dependency Registration

/// Register the client with TCA's dependency system.
/// `DependencyKey` requires `liveValue`; `testValue` and `previewValue` are optional.
extension ProfileClient: DependencyKey {
    /// Live implementation — talks to real services
    public static let liveValue = ProfileClient(
        fetch: {
            await APIService.shared.fetchProfile()
        },
        update: { name in
            await APIService.shared.updateProfile(name: name)
        },
        delete: { id in
            await APIService.shared.deleteProfile(id: id)
        }
    )

    /// Test implementation — `unimplemented()` forces tests to explicitly
    /// override only the dependencies they need. Any un-overridden call
    /// triggers a test failure, catching untested code paths.
    public static let testValue = ProfileClient(
        fetch: unimplemented("ProfileClient.fetch"),
        update: unimplemented("ProfileClient.update"),
        delete: unimplemented("ProfileClient.delete")
    )

    /// Preview implementation — returns safe, static data for SwiftUI previews
    public static let previewValue = ProfileClient(
        fetch: { .success(Profile.preview) },
        update: { name in .success(Profile(id: "1", name: name)) },
        delete: { _ in .success(()) }
    )
}

/// Register the key path on `DependencyValues` for `@Dependency(\.profileClient)` access
extension DependencyValues {
    public var profileClient: ProfileClient {
        get { self[ProfileClient.self] }
        set { self[ProfileClient.self] = newValue }
    }
}

// MARK: - Usage in Reducer

/**
 Dependencies are accessed via `@Dependency` inside the `@Reducer` struct.
 Never in State, never in the View.

 ```swift
 @Reducer
 struct ProfileFeature {
     @Dependency(\.profileClient) var profileClient
     @Dependency(\.continuousClock) var clock

     var body: some ReducerOf<Self> {
         Reduce { state, action in
             switch action {
             case .view(.onAppear):
                 return .run { [profileClient] send in
                     let result = await profileClient.fetch()
                     await send(.internal(.profileResponse(result)))
                 }
             // ...
             }
         }
     }
 }
 ```

 **In tests**, override specific operations:

 ```swift
 let store = TestStore(initialState: ProfileFeature.State()) {
     ProfileFeature()
 } withDependencies: {
     $0.profileClient.fetch = { .success(.preview) }
 }
 ```
 */
private struct _UsageDocumentation {}
