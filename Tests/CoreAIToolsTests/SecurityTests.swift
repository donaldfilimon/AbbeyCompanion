import Foundation
import Testing
@testable import CoreAITools

@MainActor
struct SecurityTests {

    private let project = "/Users/me/MyProject"

    @Test func insideProject_isAllowed() {
        #expect(PathSecurity.resolve(within: project, path: "Sources/main.swift") != nil)
        #expect(PathSecurity.resolve(within: project, path: "Sources/Sub/File.swift") != nil)
        #expect(PathSecurity.resolve(within: project, path: ".") != nil)
        #expect(PathSecurity.resolve(within: project, path: "relative/../nested.swift") != nil)
    }

    @Test func traversal_escapingProject_isRejected() {
        // Parent directory escape
        #expect(PathSecurity.resolve(within: project, path: "../etc/passwd") == nil)
        #expect(PathSecurity.resolve(within: project, path: "../../secrets") == nil)
        // Absolute path outside the project
        #expect(PathSecurity.resolve(within: project, path: "/etc/passwd") == nil)
        #expect(PathSecurity.resolve(within: project, path: "/Users/me/.ssh/id_rsa") == nil)
        // Sibling project escape via leading ../
        #expect(PathSecurity.resolve(within: project, path: "../OtherProject/x") == nil)
    }

    @Test func resolvedPath_staysInsideProject() {
        guard let url = PathSecurity.resolve(within: project, path: "a/b/c.swift") else {
            Issue.record("expected a resolved URL for an in-project path")
            return
        }
        let base = (project as NSString).standardizingPath
        let resolved = (url.path as NSString).standardizingPath
        #expect(resolved == base || resolved.hasPrefix(base + "/"))
    }
}
