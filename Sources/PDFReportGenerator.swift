import Foundation
#if canImport(UIKit)
import UIKit

public final class PDFReportGenerator {

    public static func generatePDF(for report: ECGAnalysisReport, gender: Gender, userNotes: String) -> URL? {
        let pageWidth: CGFloat = 595.2 // A4 width at 72 dpi
        let pageHeight: CGFloat = 841.8 // A4 height at 72 dpi
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let tempDir = FileManager.default.temporaryDirectory
        let safeDate = report.metadata.recordedDate.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: " ", with: "_")
        let fileURL = tempDir.appendingPathComponent("Referto_ECG_\(safeDate).pdf")

        do {
            try renderer.writePDF(to: fileURL) { context in
                context.beginPage()
                let ctx = context.cgContext

                var currentY: CGFloat = 36.0
                let margin: CGFloat = 40.0
                let contentWidth = pageWidth - (2 * margin)

                // 1. Header
                let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
                let subTitleFont = UIFont.systemFont(ofSize: 10, weight: .regular)
                let titleAttr: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: UIColor(red: 0.05, green: 0.15, blue: 0.35, alpha: 1.0)]
                let title = "REFERTO ELETTROCARDIOGRAFICO — LEAD I"
                (title as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: titleAttr)
                currentY += 22.0

                let subTitle = "Elaborazione matematica segnale Apple Watch • Metodo della Tangente (AHA/ACCF)"
                (subTitle as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: [.font: subTitleFont, .foregroundColor: UIColor.darkGray])
                currentY += 16.0

                // Divider line
                ctx.setStrokeColor(UIColor(red: 0.05, green: 0.15, blue: 0.35, alpha: 0.8).cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokeLineSegments(between: [CGPoint(x: margin, y: currentY), CGPoint(x: margin + contentWidth, y: currentY)])
                currentY += 14.0

                // 2. Metadata Grid (Box)
                let metaRect = CGRect(x: margin, y: currentY, width: contentWidth, height: 60)
                ctx.setFillColor(UIColor(white: 0.96, alpha: 1.0).cgColor)
                ctx.fill(metaRect)
                ctx.setStrokeColor(UIColor.lightGray.cgColor)
                ctx.setLineWidth(0.5)
                ctx.stroke(metaRect)

                let bodyFont = UIFont.systemFont(ofSize: 9.5, weight: .regular)
                let boldFont = UIFont.systemFont(ofSize: 9.5, weight: .bold)

                let colW = contentWidth / 2.0
                let m1 = "Data reg.: \(report.metadata.recordedDate)\nDispositivo: \(report.metadata.device) (\(String(format: "%.1f Hz", report.fs)))\nClassificazione Apple: \(report.metadata.classification)"
                let m2 = "Genere impostato: \(gender.rawValue)\nDurata tracciato: \(String(format: "%.0f s", report.durationSec)) (\(report.rawSignal.count) campioni)\nNote/Sintomi: \(userNotes.isEmpty ? report.metadata.symptoms : userNotes)"

                (m1 as NSString).draw(in: metaRect.insetBy(dx: 8, dy: 6), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.black])
                (m2 as NSString).draw(in: CGRect(x: margin + colW + 8, y: currentY + 6, width: colW - 16, height: 48), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.black])
                currentY += 72.0

                // 3. Clinical Evaluation Banner
                if let s = report.qtSummary {
                    let eval = s.evaluate(for: gender)
                    let bannerH: CGFloat = 32.0
                    let bannerRect = CGRect(x: margin, y: currentY, width: contentWidth, height: bannerH)

                    let bgColor: UIColor
                    let textColor: UIColor
                    switch eval.status {
                    case .normal:
                        bgColor = UIColor(red: 0.88, green: 0.96, blue: 0.88, alpha: 1.0)
                        textColor = UIColor(red: 0.05, green: 0.45, blue: 0.15, alpha: 1.0)
                    case .borderline:
                        bgColor = UIColor(red: 1.0, green: 0.95, blue: 0.80, alpha: 1.0)
                        textColor = UIColor(red: 0.70, green: 0.40, blue: 0.0, alpha: 1.0)
                    case .prolonged, .shortened:
                        bgColor = UIColor(red: 1.0, green: 0.88, blue: 0.88, alpha: 1.0)
                        textColor = UIColor(red: 0.75, green: 0.10, blue: 0.10, alpha: 1.0)
                    }

                    ctx.setFillColor(bgColor.cgColor)
                    ctx.fill(bannerRect)
                    ctx.setStrokeColor(textColor.cgColor)
                    ctx.setLineWidth(1.0)
                    ctx.stroke(bannerRect)

                    let evalTitle = "VALUTAZIONE QTc: \(eval.status.rawValue.uppercased())"
                    (evalTitle as NSString).draw(at: CGPoint(x: margin + 10, y: currentY + 5), withAttributes: [.font: UIFont.systemFont(ofSize: 10.5, weight: .bold), .foregroundColor: textColor])
                    (eval.text as NSString).draw(at: CGPoint(x: margin + 10, y: currentY + 18), withAttributes: [.font: UIFont.systemFont(ofSize: 8.5, weight: .regular), .foregroundColor: textColor])
                    currentY += bannerH + 12.0
                }

                // 4. Metric Table (Two Columns)
                let tableRect = CGRect(x: margin, y: currentY, width: contentWidth, height: 75)
                ctx.setFillColor(UIColor(white: 0.98, alpha: 1.0).cgColor)
                ctx.fill(tableRect)
                ctx.stroke(tableRect)

                let s = report.qtSummary
                let tCol1 = """
                • Frequenza Media: \(String(format: "%.0f", report.bpm)) BPM
                • Battiti Rilevati: \(report.rPeakIndices.count) battiti
                • RR Medio: \(String(format: "%.0f ms", report.hrv.meanRR))
                • Durata QRS: \(s != nil ? String(format: "%.0f ms", s!.qrsMs) : "N/D")
                """
                let tCol2 = """
                • QT Mediano: \(s != nil ? String(format: "%.0f ms", s!.qtMs) : "N/D")
                • QTc Fridericia (raccomandato): \(s != nil ? String(format: "%.0f ms", s!.qtcFridericia) : "N/D")
                • QTc Bazett: \(s != nil ? String(format: "%.0f ms", s!.qtcBazett) : "N/D")
                • HRV: SDNN \(String(format: "%.1f ms", report.hrv.sdnn)) | RMSSD \(String(format: "%.1f ms", report.hrv.rmssd))
                """

                (tCol1 as NSString).draw(in: tableRect.insetBy(dx: 10, dy: 6), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.black])
                (tCol2 as NSString).draw(in: CGRect(x: margin + colW, y: currentY + 6, width: colW - 10, height: 65), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.black])
                currentY += 85.0

                // 5. Median Beat & Tangent Plot
                ("DETTAGLIO BATTITO MEDIANO E TANGENTE (REPENTINA RIPOLARIZZAZIONE)" as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: [.font: boldFont, .foregroundColor: UIColor.black])
                currentY += 14.0

                if let mb = report.medianBeat {
                    let plotH: CGFloat = 160.0
                    let plotRect = CGRect(x: margin, y: currentY, width: contentWidth, height: plotH)
                    ctx.setFillColor(UIColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1.0).cgColor)
                    ctx.fill(plotRect)

                    let w = mb.wave
                    let minV = w.min() ?? -0.3
                    let maxV = w.max() ?? 0.3
                    let span = max(0.1, maxV - minV)

                    func toPlotPt(_ idx: Int) -> CGPoint {
                        let xNorm = CGFloat(idx) / CGFloat(max(1, w.count - 1))
                        let yNorm = CGFloat((w[idx] - minV) / span)
                        return CGPoint(x: plotRect.minX + xNorm * plotRect.width, y: plotRect.maxY - yNorm * plotRect.height)
                    }

                    // Shaded QT
                    let qX = toPlotPt(mb.qOnIndex).x
                    let tEndPt = toPlotPt(mb.tEndIndex)
                    ctx.setFillColor(UIColor.yellow.withAlphaComponent(0.15).cgColor)
                    ctx.fill(CGRect(x: qX, y: plotRect.minY, width: max(4, tEndPt.x - qX), height: plotH))

                    // Isoelectric line
                    let isoY = plotRect.maxY - CGFloat((mb.vIso - minV) / span) * plotRect.height
                    ctx.setStrokeColor(UIColor.gray.withAlphaComponent(0.6).cgColor)
                    ctx.setLineWidth(1.0)
                    ctx.setLineDash(phase: 0, lengths: [4, 4])
                    ctx.strokeLineSegments(between: [CGPoint(x: plotRect.minX, y: isoY), CGPoint(x: plotRect.maxX, y: isoY)])
                    ctx.setLineDash(phase: 0, lengths: [])

                    // Waveform path
                    let wavePath = UIBezierPath()
                    for i in 0..<w.count {
                        let pt = toPlotPt(i)
                        if i == 0 { wavePath.move(to: pt) } else { wavePath.addLine(to: pt) }
                    }
                    ctx.setStrokeColor(UIColor.white.cgColor)
                    ctx.setLineWidth(2.2)
                    wavePath.stroke()

                    // Tangent line (Orange)
                    let k = mb.kSlopeIndex
                    let m = mb.mSlope
                    let x0 = max(0, k - 14)
                    let x1 = min(w.count - 1, mb.tEndIndex + 10)
                    let y0 = plotRect.maxY - CGFloat((mb.vSlope + m * Double(x0 - k) - minV) / span) * plotRect.height
                    let y1 = plotRect.maxY - CGFloat((mb.vSlope + m * Double(x1 - k) - minV) / span) * plotRect.height
                    let p0 = CGPoint(x: toPlotPt(x0).x, y: y0)
                    let p1 = CGPoint(x: toPlotPt(x1).x, y: y1)

                    ctx.setStrokeColor(UIColor.orange.cgColor)
                    ctx.setLineWidth(2.0)
                    ctx.setLineDash(phase: 0, lengths: [5, 3])
                    ctx.strokeLineSegments(between: [p0, p1])
                    ctx.setLineDash(phase: 0, lengths: [])

                    // Markers
                    for (idx, color) in [(mb.qOnIndex, UIColor.systemBlue), (mb.tPeakIndex, UIColor.systemGreen), (mb.tEndIndex, UIColor.systemRed)] {
                        let p = toPlotPt(idx)
                        ctx.setFillColor(color.cgColor)
                        ctx.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                    }

                    // Caption
                    let caption = "Inizio Q (Blu) • Picco T (Verde) • Fine T da Tangente (Rosso) | QT Misurato = \(Int(mb.qtMs)) ms"
                    (caption as NSString).draw(at: CGPoint(x: margin + 6, y: currentY + plotH - 16), withAttributes: [.font: UIFont.systemFont(ofSize: 8, weight: .bold), .foregroundColor: UIColor.yellow])

                    currentY += plotH + 16.0
                }

                // 6. 10-Second Continuous ECG Strip on Pink Medical Grid
                ("STRISCIA ECG 10 SECONDI (CARTA MILLIMETRATA: 25 mm/s, 10 mm/mV)" as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: [.font: boldFont, .foregroundColor: UIColor.black])
                currentY += 14.0

                let stripH: CGFloat = 160.0
                let stripRect = CGRect(x: margin, y: currentY, width: contentWidth, height: stripH)

                // Pink medical paper background
                ctx.setFillColor(UIColor(red: 1.0, green: 0.96, blue: 0.96, alpha: 1.0).cgColor)
                ctx.fill(stripRect)

                // Grid: 40 ms small box, 200 ms large box
                let fs = report.fs
                let sig = report.filteredSignal
                let tenSecSamples = min(sig.count, Int(10.0 * fs))
                let secWidth = contentWidth / 10.0
                let smallBoxW = secWidth * 0.04
                let largeBoxW = secWidth * 0.20
                let boxH: CGFloat = 14.0

                // Small vertical grid
                var gx = stripRect.minX
                while gx <= stripRect.maxX {
                    ctx.setStrokeColor(UIColor(red: 1.0, green: 0.80, blue: 0.80, alpha: 0.5).cgColor)
                    ctx.setLineWidth(0.4)
                    ctx.strokeLineSegments(between: [CGPoint(x: gx, y: stripRect.minY), CGPoint(x: gx, y: stripRect.maxY)])
                    gx += smallBoxW
                }

                // Large vertical grid
                gx = stripRect.minX
                while gx <= stripRect.maxX {
                    ctx.setStrokeColor(UIColor(red: 0.95, green: 0.60, blue: 0.60, alpha: 0.8).cgColor)
                    ctx.setLineWidth(0.8)
                    ctx.strokeLineSegments(between: [CGPoint(x: gx, y: stripRect.minY), CGPoint(x: gx, y: stripRect.maxY)])
                    gx += largeBoxW
                }

                // Horizontal grid
                var gy = stripRect.minY
                while gy <= stripRect.maxY {
                    ctx.setStrokeColor(UIColor(red: 1.0, green: 0.80, blue: 0.80, alpha: 0.5).cgColor)
                    ctx.setLineWidth(0.4)
                    ctx.strokeLineSegments(between: [CGPoint(x: stripRect.minX, y: gy), CGPoint(x: stripRect.maxX, y: gy)])
                    gy += boxH
                }

                // Baseline center
                let midY = stripRect.minY + stripH / 2.0

                // Signal curve (Black)
                if tenSecSamples > 1 {
                    let sigPath = UIBezierPath()
                    for i in 0..<tenSecSamples {
                        let curSec = Double(i) / fs
                        let px = stripRect.minX + CGFloat(curSec) * secWidth
                        let py = midY - CGFloat(sig[i]) * 80.0 // 10 mm/mV scaling
                        if i == 0 { sigPath.move(to: CGPoint(x: px, y: py)) } else { sigPath.addLine(to: CGPoint(x: px, y: py)) }
                    }
                    ctx.setStrokeColor(UIColor.black.cgColor)
                    ctx.setLineWidth(1.1)
                    sigPath.stroke()

                    // R peaks markers
                    for r in report.rPeakIndices where r < tenSecSamples {
                        let rx = stripRect.minX + CGFloat(Double(r) / fs) * secWidth
                        let ry = midY - CGFloat(sig[r]) * 80.0
                        ctx.setFillColor(UIColor.red.cgColor)
                        ctx.fillEllipse(in: CGRect(x: rx - 2.5, y: ry - 2.5, width: 5, height: 5))
                    }
                }

                currentY += stripH + 20.0

                // 7. Medical Disclaimer Footer
                let disclaimer = "AVVERTENZA MEDICA: Questo referto costituisce un'elaborazione matematica su tracciato a singola derivazione (Lead I) esportato da Apple Watch tramite algoritmi a fase zero (Pan-Tompkins e Metodo della Tangente AHA). Il valore di QTc e gli indici di ripolarizzazione hanno scopo puramente informativo e di screening remoto e NON sostituiscono la diagnosi clinica formale di un medico cardiologo né un elettrocardiogramma standard a 12 derivazioni."
                (disclaimer as NSString).draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 45), withAttributes: [.font: UIFont.systemFont(ofSize: 7.5, weight: .regular), .foregroundColor: UIColor.gray])
            }

            return fileURL
        } catch {
            print("Errore generazione PDF: \(error)")
            return nil
        }
    }
}
#endif
