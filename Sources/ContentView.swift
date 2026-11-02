import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var report: ECGAnalysisReport?
    @State private var fileName: String = "Nessun file caricato"
    @State private var isImporting: Bool = false
    @State private var selectedTab: Int = 0
    @State private var zoomRange: ClosedRange<Double> = 0...10.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header card
                    headerCard

                    if let report = report {
                        // Metadata card
                        metadataCard(report: report)

                        // KPI Cards
                        kpiGrid(report: report)

                        // QT Highlights
                        qtHighlightCard(report: report)

                        // Picker tabs
                        Picker("Visualizzazione", selection: $selectedTab) {
                            Text("ECG").tag(0)
                            Text("QT Tangente").tag(1)
                            Text("Battiti").tag(2)
                            Text("Lorenz").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        // Tab content
                        switch selectedTab {
                        case 0:
                            ecgWaveformView(report: report)
                        case 1:
                            medianBeatView(report: report)
                        case 2:
                            beatTableView(report: report)
                        default:
                            lorenzPlotView(report: report)
                        }
                    } else {
                        emptyStateView
                    }
                }
                .padding()
            }
            .navigationTitle("Dynamic ECG")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isImporting = true
                    } label: {
                        Label("Apri CSV", systemImage: "doc.badge.plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.commaSeparatedText, .text, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
            .onAppear {
                loadDemoDataIfEmpty()
            }
        }
    }

    // MARK: - Subviews

    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Analisi Apple Watch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(fileName)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                isImporting = true
            } label: {
                Text("Importa")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func metadataCard(report: ECGAnalysisReport) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("📅 \(report.metadata.recordedDate)")
                Text("🩺 \(report.metadata.classification)")
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("⌚ \(report.metadata.device)")
                Text("⚡ \(String(format: "%.1f Hz", report.fs)) (\(String(format: "%.0f s", report.durationSec)))")
            }
        }
        .font(.footnote)
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func kpiGrid(report: ECGAnalysisReport) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            kpiTile(title: "Frequenza", value: "\(String(format: "%.0f", report.bpm)) BPM", color: .red)
            kpiTile(title: "Picchi R", value: "\(report.rPeakIndices.count)", color: .blue)
            kpiTile(title: "RR Medio", value: "\(String(format: "%.0f", report.hrv.meanRR)) ms", color: .orange)
            kpiTile(title: "SDNN", value: "\(String(format: "%.1f", report.hrv.sdnn)) ms", color: .purple)
            kpiTile(title: "RMSSD", value: "\(String(format: "%.1f", report.hrv.rmssd)) ms", color: .teal)
            kpiTile(title: "pNN50", value: "\(String(format: "%.1f%%", report.hrv.pnn50))", color: .green)
        }
    }

    private func kpiTile(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func qtHighlightCard(report: ECGAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Intervallo QT / QTc (Linee guida AHA)")
                    .font(.footnote.bold())
                Spacer()
                if let s = report.qtSummary {
                    Text(s.isReliable ? "✅ Affidabile" : "⚠️ Rumoroso")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(s.isReliable ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                        .foregroundStyle(s.isReliable ? .green : .orange)
                        .clipShape(Capsule())
                }
            }

            if let s = report.qtSummary {
                HStack {
                    VStack(alignment: .leading) {
                        Text("QT Mediano")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(String(format: "%.0f", s.qtMs)) ms")
                            .font(.title2.bold())
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("QTc Fridericia")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(String(format: "%.0f", s.qtcFridericia)) ms")
                            .font(.title2.bold())
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("QTc Bazett")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(String(format: "%.0f", s.qtcBazett)) ms")
                            .font(.title2.bold())
                            .foregroundStyle(.purple)
                    }
                }

                if s.hrBpm > 90.0 {
                    Text("💡 FC > 90 bpm: la formula di Bazett tende a sovrastimare, fai riferimento a Fridericia.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Onda T non chiaramente definita per il calcolo automatico del QT.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Waveform View

    private func ecgWaveformView(report: ECGAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tracciato ECG Lead I (0-10 s)")
                    .font(.subheadline.bold())
                Spacer()
                Text("R in rosso")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Canvas { context, size in
                let sig = report.filteredSignal
                guard sig.count > 10 else { return }
                let fs = report.fs
                let maxSamples = min(sig.count, Int(10.0 * fs))
                let minVal = sig.prefix(maxSamples).min() ?? -0.5
                let maxVal = sig.prefix(maxSamples).max() ?? 0.5
                let valRange = max(0.1, maxVal - minVal)

                // Grid lines
                let gridY = 4
                for g in 0...gridY {
                    let y = size.height * (CGFloat(g) / CGFloat(gridY))
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    }, with: .color(Color.gray.opacity(0.15)), lineWidth: 1)
                }

                // Plot signal
                var path = Path()
                for i in 0..<maxSamples {
                    let x = size.width * (CGFloat(i) / CGFloat(maxSamples))
                    let norm = CGFloat((sig[i] - minVal) / valRange)
                    let y = size.height * (1.0 - norm)
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(path, with: .color(.cyan), lineWidth: 1.2)

                // Plot R peaks
                for r in report.rPeakIndices where r < maxSamples {
                    let x = size.width * (CGFloat(r) / CGFloat(maxSamples))
                    let norm = CGFloat((sig[r] - minVal) / valRange)
                    let y = size.height * (1.0 - norm)
                    context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(.red))
                }
            }
            .frame(height: 220)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Median Beat View (Tangent Method)

    private func medianBeatView(report: ECGAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Battito Mediano e Metodo della Tangente")
                .font(.subheadline.bold())

            if let mb = report.medianBeat {
                Canvas { context, size in
                    let w = mb.wave
                    guard w.count > 10 else { return }
                    let minVal = w.min() ?? -0.3
                    let maxVal = w.max() ?? 0.3
                    let range = max(0.1, maxVal - minVal)

                    func pt(_ i: Int) -> CGPoint {
                        let x = size.width * (CGFloat(i) / CGFloat(w.count - 1))
                        let norm = CGFloat((w[i] - minVal) / range)
                        return CGPoint(x: x, y: size.height * (1.0 - norm))
                    }

                    // Isoelectric line
                    let isoNorm = CGFloat((mb.vIso - minVal) / range)
                    let isoY = size.height * (1.0 - isoNorm)
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: 0, y: isoY))
                        p.addLine(to: CGPoint(x: size.width, y: isoY))
                    }, with: .color(Color.gray.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    // Highlight QT box
                    let qX = pt(mb.qOnIndex).x
                    let tEndPt = pt(mb.tEndIndex)
                    let qtBox = CGRect(x: qX, y: 0, width: max(5, tEndPt.x - qX), height: size.height)
                    context.fill(Path(qtBox), with: .color(Color.yellow.opacity(0.12)))

                    // Median wave
                    var path = Path()
                    for i in 0..<w.count {
                        let p = pt(i)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    context.stroke(path, with: .color(.white), lineWidth: 2.5)

                    // Tangent line on descending limb
                    let k = mb.kSlopeIndex
                    let m = mb.mSlope
                    let x0 = max(0, k - 12)
                    let x1 = min(w.count - 1, mb.tEndIndex + 8)
                    let p0 = CGPoint(x: pt(x0).x, y: size.height * (1.0 - CGFloat((mb.vSlope + m * Double(x0 - k) - minVal) / range)))
                    let p1 = CGPoint(x: pt(x1).x, y: size.height * (1.0 - CGFloat((mb.vSlope + m * Double(x1 - k) - minVal) / range)))
                    context.stroke(Path { p in
                        p.move(to: p0)
                        p.addLine(to: p1)
                    }, with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

                    // Markers
                    let marks: [(Int, Color)] = [
                        (mb.qOnIndex, .blue),
                        (mb.tPeakIndex, .green),
                        (mb.tEndIndex, .red)
                    ]
                    for (idx, color) in marks {
                        let p = pt(idx)
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(color))
                    }
                }
                .frame(height: 240)
                .background(Color.black.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 12) {
                    Label("Inizio Q", systemImage: "circle.fill").foregroundStyle(.blue)
                    Label("Picco T", systemImage: "circle.fill").foregroundStyle(.green)
                    Label("Fine T (Tangente)", systemImage: "circle.fill").foregroundStyle(.red)
                }
                .font(.caption2)

                Text("QT: \(String(format: "%.0f ms", mb.qtMs)) | RR: \(String(format: "%.0f ms", mb.rrMs)) | QRS: \(String(format: "%.0f ms", mb.qrsMs))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Beat Table

    private func beatTableView(report: ECGAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dettaglio Battito per Battito")
                .font(.subheadline.bold())

            ForEach(report.beats.prefix(20)) { beat in
                HStack {
                    Text("Battito #\(beat.beatNumber)")
                        .font(.caption.bold())
                    Spacer()
                    Text("RR: \(String(format: "%.0f ms", beat.rrMs))")
                        .font(.caption2)
                    Spacer()
                    Text("QT: \(String(format: "%.0f ms", beat.qtMs))")
                        .font(.caption.bold())
                    Spacer()
                    Text("QTcF: \(String(format: "%.0f ms", beat.qtcFridericia))")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Lorenz Plot

    private func lorenzPlotView(report: ECGAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Grafico di Lorenz (RR_n vs RR_n+1)")
                .font(.subheadline.bold())

            Canvas { context, size in
                let rr = report.rrIntervalsMs
                guard rr.count > 2 else { return }
                let minRR = max(300.0, (rr.min() ?? 500.0) - 100.0)
                let maxRR = min(1500.0, (rr.max() ?? 1000.0) + 100.0)
                let span = max(100.0, maxRR - minRR)

                // Diagonal y = x line
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: 0, y: size.height))
                    p.addLine(to: CGPoint(x: size.width, y: 0))
                }, with: .color(Color.red.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                for i in 0..<(rr.count - 1) {
                    let xNorm = CGFloat((rr[i] - minRR) / span)
                    let yNorm = CGFloat((rr[i + 1] - minRR) / span)
                    let x = size.width * xNorm
                    let y = size.height * (1.0 - yNorm)
                    context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(.cyan))
                }
            }
            .frame(height: 220)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("Nessun tracciato selezionato")
                .font(.headline)
            Text("Tocca 'Apri CSV' in alto per caricare un tracciato esportato dall'app Salute di Apple Watch.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Handlers

    private func handleFileImport(result: Result<[URL], Error>) {
        do {
            guard let selectedFile = try result.get().first else { return }
            guard selectedFile.startAccessingSecurityScopedResource() else { return }
            defer { selectedFile.stopAccessingSecurityScopedResource() }

            let content = try String(contentsOf: selectedFile, encoding: .utf8)
            let (meta, samples, fs) = ECGParser.parseCSV(content: content)
            processSignal(samples: samples, fs: fs, metadata: meta, name: selectedFile.lastPathComponent)
        } catch {
            print("Errore apertura file: \(error)")
        }
    }

    private func processSignal(samples: [Double], fs: Double, metadata: ECGMetadata, name: String) {
        guard samples.count > 100 else { return }
        let duration = Double(samples.count) / fs
        let filtered = ECGProcessor.bandpassFilter(signal: samples, fs: fs)
        let rPeaks = ECGProcessor.detectRPeaks(signal: filtered, fs: fs)

        var rrIntervals: [Double] = []
        if rPeaks.count > 1 {
            for i in 0..<(rPeaks.count - 1) {
                rrIntervals.append((Double(rPeaks[i + 1] - rPeaks[i]) / fs) * 1000.0)
            }
        }

        let bpm = duration > 0 ? (Double(rPeaks.count) / duration) * 60.0 : 0.0
        let hrv = ECGProcessor.calculateHRV(rrMs: rrIntervals)
        let (summary, medBeat, beats) = ECGProcessor.analyzeQT(signal: samples, rPeaks: rPeaks, fs: fs)

        self.fileName = name
        self.report = ECGAnalysisReport(
            metadata: metadata,
            fs: fs,
            durationSec: duration,
            filteredSignal: filtered,
            rPeakIndices: rPeaks,
            bpm: bpm,
            hrv: hrv,
            rrIntervalsMs: rrIntervals,
            qtSummary: summary,
            medianBeat: medBeat,
            beats: beats
        )
    }

    private func loadDemoDataIfEmpty() {
        guard report == nil else { return }
        // Genera tracciato sintetico di avvio (FC 72 bpm, QT 360 ms)
        let fs = 512.0
        let n = Int(10.0 * fs)
        var synthetic = [Double](repeating: 0.0, count: n)
        let rrSamples = Int((60.0 / 72.0) * fs)
        for r in stride(from: Int(0.4 * fs), to: n - Int(0.5 * fs), by: rrSamples) {
            synthetic[r] = 0.8 // R peak
            synthetic[r - Int(0.03 * fs)] = -0.15 // Q
            synthetic[r + Int(0.04 * fs)] = -0.25 // S
            // T wave around +220 ms
            let tPeak = r + Int(0.22 * fs)
            if tPeak < n {
                synthetic[tPeak] = 0.25
            }
        }
        var meta = ECGMetadata()
        meta.recordedDate = "Demo iniziale"
        meta.classification = "Ritmo sinusale (Demo)"
        processSignal(samples: synthetic, fs: fs, metadata: meta, name: "Tracciato Dimostrativo")
    }
}
