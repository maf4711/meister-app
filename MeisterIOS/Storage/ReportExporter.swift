import UIKit

/// Renders a lightweight PDF summary of the latest scan. Uses `UIGraphicsPDFRenderer`
/// so it is self-contained (no external dependency) and produces A4 pages that the
/// user can share via `ShareLink`.
struct CleanupReport {
    struct Section {
        let title: String
        let rows: [(label: String, value: String)]
    }

    let generatedAt: Date
    let deviceInfo: String
    let sections: [Section]

    func renderPDF() throws -> URL {
        let pageSize = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 @ 72 dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageSize)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeisterReport-\(Int(Date().timeIntervalSince1970)).pdf")
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            draw(sections, in: pageSize)
        }
        return url
    }

    private func draw(_ sections: [Section], in page: CGRect) {
        var y: CGFloat = 48
        let x: CGFloat = 48

        let title = "Meister Cleanup Report"
        (title as NSString).draw(
            at: CGPoint(x: x, y: y),
            withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28)]
        )
        y += 36

        let stamp = generatedAt.formatted(date: .long, time: .shortened)
        ("\(deviceInfo) · \(stamp)" as NSString).draw(
            at: CGPoint(x: x, y: y),
            withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.gray]
        )
        y += 28

        for section in sections {
            (section.title as NSString).draw(
                at: CGPoint(x: x, y: y),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 18)]
            )
            y += 24
            for row in section.rows {
                (row.label as NSString).draw(
                    at: CGPoint(x: x, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 14)]
                )
                let value = row.value as NSString
                let size = value.size(withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)])
                value.draw(
                    at: CGPoint(x: page.width - 48 - size.width, y: y),
                    withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)]
                )
                y += 20
            }
            y += 16
        }
    }
}
