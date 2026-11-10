import Defaults
import SwiftUI

struct FileConvertSettings: View {
    @State private var engines: [ExternalConversionTool: String] = [:]

    var body: some View {
        Group {
            Section {
                Defaults.Toggle(key: .fileConvertKeepOriginal) {
                    SettingsInfoLabel("Keep original file", info: "When off, the original moves to the Trash after a successful conversion, so you can still restore it. The same option is in the File Convert panel’s menu.")
                }
                .settingsHighlight(id: "shelf-Keep original file")
            } header: {
                SettingsInfoLabel("File Convert", info: "Shares the Shelf tab: drop files on the right panel and choose a format. Results are saved next to the original; existing files are never replaced.")
            }

            Section {
                ForEach(ExternalConversionTool.allCases, id: \.self) { tool in
                    LabeledContent(tool.name) {
                        if let path = engines[tool] {
                            Text(path).foregroundStyle(.secondary).textSelection(.enabled)
                        } else {
                            Text("Not installed").foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Check Again") { refreshEngines() }
            } header: {
                SettingsInfoLabel("Optional engines", info: "Built-in formats work without them. LibreOffice adds Word, Excel and PowerPoint to PDF with their layout. FFmpeg adds MP3, FLAC, WebM, WebP and GIF. Only copies you installed are used; nothing is downloaded.")
            }
        }
        .onAppear(perform: refreshEngines)
    }

    private func refreshEngines() {
        engines = Dictionary(uniqueKeysWithValues: ExternalConversionTool.allCases.compactMap { tool in
            tool.executable.map { (tool, $0.path) }
        })
    }
}
