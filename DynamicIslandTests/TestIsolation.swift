import Foundation
import XCTest

extension XCTestCase {
    /// A preferences suite kept in a temporary folder and removed after the
    /// test. A suite named by a path keeps its plist there; a plain name would
    /// leave one in ~/Library/Preferences that the preferences daemon writes back.
    func temporaryDefaultsSuite() throws -> String {
        let folder = FileManager.default.temporaryDirectory.appending(path: "AtollDefaults.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = folder.appending(path: "defaults").path
        addTeardownBlock {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: folder)
        }
        return name
    }

    /// Keeps a rendered PNG for visual review in the result bundle, never in a
    /// shared folder such as /tmp, so a run leaves nothing behind.
    func attachPreview(_ png: Data, named name: String) {
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
