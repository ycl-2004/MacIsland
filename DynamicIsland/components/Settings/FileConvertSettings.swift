import Defaults
import SwiftUI

struct FileConvertSettings: View {
    @State private var engines: [ExternalConversionTool: String] = [:]

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableFileConvertFeature) {
                    Text("Enable File Convert")
                }
                .settingsHighlight(id: "fileConvert-Enable File Convert")
                Defaults.Toggle(key: .fileConvertKeepOriginal) {
                    SettingsInfoLabel("Keep original file", info: "When off, the original moves to the Trash after a successful conversion, so you can still restore it. The same switch is in the Convert tab.")
                }
                .settingsHighlight(id: "fileConvert-Keep original file")
            } header: {
                SettingsInfoLabel("File Convert", info: "Adds a Convert tab to the notch. Drop files there and choose a format. The result is saved in the same folder as the original; existing files are never replaced.")
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

            Section {
                LabeledContent("Images") { Text("JPEG, PNG, HEIC, TIFF, GIF, BMP, PDF · WebP with FFmpeg") }
                LabeledContent("PDF") { Text("PNG or JPEG, one image per page (up to 100 pages)") }
                LabeledContent("Documents") { Text("Word, ODT, RTF, HTML, Text · PDF with LibreOffice") }
                LabeledContent("Audio") { Text("M4A, WAV, AIFF · MP3, FLAC with FFmpeg") }
                LabeledContent("Video") { Text("MP4, MOV, M4A audio · WebM, MP3, GIF (first 60 s) with FFmpeg") }
            } header: {
                Text("Formats")
            }
        }
        .navigationTitle("File Convert")
        .onAppear(perform: refreshEngines)
    }

    private func refreshEngines() {
        engines = Dictionary(uniqueKeysWithValues: ExternalConversionTool.allCases.compactMap { tool in
            tool.executable.map { (tool, $0.path) }
        })
    }
}
