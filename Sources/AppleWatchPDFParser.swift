import Foundation
#if canImport(PDFKit) && canImport(UIKit)
import PDFKit
import UIKit

public final class AppleWatchPDFParser {

    /// Parses an official Apple Watch ECG PDF ("Referto per il medico")
    /// Extracts text metadata and traces the 30-second continuous waveform from the 3 strips.
    public static func parsePDF(url: URL) -> (metadata: ECGMetadata, multiLead: MultiLeadData, fs: Double)? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else {
            return nil
        }

        var meta = ECGMetadata()
        meta.device = "Apple Watch (da PDF)"
        meta.lead = "Derivazione I"
        let fs = 512.0

        // 1. Extract Text Metadata
        if let text = page.string {
            parseTextMetadata(text: text, meta: &meta)
        }

        // 2. Render PDF Page at High Resolution for Signal Tracing
        let renderWidth: CGFloat = 1800.0
        let pageBounds = page.bounds(for: .mediaBox)
        let scale = renderWidth / max(1.0, pageBounds.width)
        let renderHeight = pageBounds.height * scale
        let renderSize = CGSize(width: renderWidth, height: renderHeight)

        let renderer = UIGraphicsImageRenderer(size: renderSize)
        let pageImage = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: renderSize))
            ctx.cgContext.saveGState()
            ctx.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }

        guard let cgImage = pageImage.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height

        guard let pixelData = cgImage.dataProvider?.data,
              let dataPtr = CFDataGetBytePtr(pixelData) else {
            return nil
        }
        let bytesPerPixel = 4
        let bytesPerRow = cgImage.bytesPerRow

        // 3. Locate the 3 horizontal strips
        // Strip 1: 0 - 10s (approx Y: 22% - 39%)
        // Strip 2: 10 - 20s (approx Y: 43% - 60%)
        // Strip 3: 20 - 30s (approx Y: 64% - 81%)
        let stripYRanges: [(start: Double, end: Double)] = [
            (0.22, 0.40),
            (0.43, 0.61),
            (0.64, 0.82)
        ]

        let xStartRel = 0.08
        let xEndRel = 0.94
        let xStartPx = Int(Double(width) * xStartRel)
        let xEndPx = Int(Double(width) * xEndRel)
        let colCount = max(10, xEndPx - xStartPx)

        // 10 mm/mV -> at 72 dpi: 10 mm = 28.35 pt -> scaled: 28.35 * scale pixels per mV
        let pixelsPerMV = 28.35 * Double(scale)

        var fullTrace: [Double] = []

        for (stripIdx, yRange) in stripYRanges.enumerated() {
            let yMinPx = Int(Double(height) * yRange.start)
            let yMaxPx = Int(Double(height) * yRange.end)

            var stripSamples: [Double] = []
            var lastValidMV = 0.0

            // Baseline estimate: median vertical center of the strip
            let baselineY = Double(yMinPx + yMaxPx) / 2.0

            for x in xStartPx..<xEndPx {
                var darkestVal = 255.0
                var bestY = baselineY
                var foundDark = false

                // Scan column from top to bottom
                for y in yMinPx..<yMaxPx {
                    let offset = y * bytesPerRow + x * bytesPerPixel
                    let r = Double(dataPtr[offset])
                    let g = Double(dataPtr[offset + 1])
                    let b = Double(dataPtr[offset + 2])

                    // Exclude red/pink grid lines (Grid: high Red, lower Green/Blue)
                    let isGrid = (r > 190 && g < 175) || (r > 180 && (r - g) > 25)

                    // Luminance
                    let lum = 0.299 * r + 0.587 * g + 0.114 * b

                    if !isGrid && lum < 120.0 {
                        if lum < darkestVal {
                            darkestVal = lum
                            bestY = Double(y)
                            foundDark = true
                        }
                    }
                }

                if foundDark {
                    // Invert Y: pixel Y grows downward, ECG voltage grows upward
                    let mv = -(bestY - baselineY) / pixelsPerMV
                    stripSamples.append(mv)
                    lastValidMV = mv
                } else {
                    stripSamples.append(lastValidMV)
                }
            }

            // Remove calibration pulse in the first ~5% of each strip
            let calibWidth = Int(Double(stripSamples.count) * 0.05)
            if stripSamples.count > calibWidth {
                let activeSamples = Array(stripSamples.dropFirst(calibWidth))
                fullTrace.append(contentsOf: activeSamples)
            } else {
                fullTrace.append(contentsOf: stripSamples)
            }
        }

        guard fullTrace.count > 100 else { return nil }

        // 4. Resample to standard 512 Hz over 30 seconds (15,360 samples)
        let targetCount = Int(30.0 * fs)
        var resampled = [Double](repeating: 0.0, count: targetCount)
        let srcCount = fullTrace.count

        for i in 0..<targetCount {
            let srcIdxDouble = (Double(i) / Double(targetCount - 1)) * Double(srcCount - 1)
            let i0 = Int(floor(srcIdxDouble))
            let i1 = min(srcCount - 1, i0 + 1)
            let frac = srcIdxDouble - Double(i0)
            resampled[i] = fullTrace[i0] * (1.0 - frac) + fullTrace[i1] * frac
        }

        let multi = MultiLeadData(
            hasMultipleLeads: false,
            lead1: resampled,
            lead2: resampled,
            lead3: resampled,
            average: resampled
        )

        return (meta, multi, fs)
    }

    private static func parseTextMetadata(text: String, meta: inout ECGMetadata) {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            // Date
            if lower.contains("data") || lower.contains("date") || lower.contains("202") {
                if meta.recordedDate == "N/D" && trimmed.count > 6 {
                    meta.recordedDate = trimmed
                }
            }

            // Classification
            if lower.contains("sinusale") || lower.contains("sinus rhythm") {
                meta.classification = "Ritmo sinusale"
            } else if lower.contains("fibrillazione") || lower.contains("atrial fib") {
                meta.classification = "Fibrillazione atriale"
            } else if lower.contains("elevata") || lower.contains("high heart rate") {
                meta.classification = "Frequenza cardiaca elevata"
            } else if lower.contains("bassa") || lower.contains("low heart rate") {
                meta.classification = "Frequenza cardiaca bassa"
            } else if lower.contains("inconcludente") || lower.contains("inconclusive") {
                meta.classification = "Inconcludente"
            }

            // Heart Rate
            if lower.contains("bpm") {
                let comps = trimmed.components(separatedBy: " ")
                for c in comps {
                    if let val = Double(c.replacingOccurrences(of: "bpm", with: "").trimmingCharacters(in: .punctuationCharacters)) {
                        meta.classification += " (\(Int(val)) BPM)"
                        break
                    }
                }
            }
        }
    }
}
#endif
