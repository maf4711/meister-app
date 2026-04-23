import SwiftUI
import UniformTypeIdentifiers

struct ICloudCleanerView: View {
    @State private var pickedFolder: URL?
    @State private var findings: [ICloudDriveCleaner.Finding] = []
    @State private var isScanning = false
    @State private var isPickingFolder = false

    var body: some View {
        List {
            Section {
                if let pickedFolder {
                    LabeledContent("Folder", value: pickedFolder.lastPathComponent)
                }
                Button {
                    isPickingFolder = true
                } label: {
                    Label(pickedFolder == nil ? "Choose Folder" : "Choose Another Folder",
                          systemImage: "folder.badge.plus")
                }
                if pickedFolder != nil {
                    Button {
                        scan()
                    } label: {
                        Label(isScanning ? "Scanning…" : "Scan for Large / Old Files",
                              systemImage: "magnifyingglass")
                    }
                    .disabled(isScanning)
                }
            } footer: {
                Text("Finds files larger than 50 MB or untouched for 180 days. iCloud-synced folders work too — iOS downloads on demand.")
            }

            if !findings.isEmpty {
                Section("Found \(findings.count) files · \(totalSize)") {
                    ForEach(findings) { finding in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.url.lastPathComponent).lineLimit(1)
                            Text("\(ByteSize.formatted(finding.size)) · \(finding.modified.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("iCloud Drive")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isPickingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                pickedFolder = url
                findings = []
            }
        }
    }

    private var totalSize: String {
        ByteSize.formatted(findings.reduce(Int64(0)) { $0 + $1.size })
    }

    private func scan() {
        guard let folder = pickedFolder else { return }
        isScanning = true
        Task.detached {
            let result = (try? ICloudDriveCleaner.scan(at: folder)) ?? []
            await MainActor.run {
                findings = result
                isScanning = false
            }
        }
    }
}
