import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var report: ECGAnalysisReport?
    @State private var fileName: String = "Nessun file caricato"
    @State private var isImporting: Bool = false
    @State private var selectedTab: Int = 0
    @State private var speedScale: Double = 1.0 // 1.0 = 25 mm/s, 2.0 = 50 mm/s
    @State private var voltageScale: Double = 1.0 // 1.0 = 10 mm/mV, 2.0 = 20 mm/mV
    @State private var selectedGender: Gender = .male
    @State private var userNotes: String = ""
    @State private var isNotesSheetPresented: Bool = false
    @State private var generatedPDFURL: URL?
    @State private var isSharingPDF: Bool = false
    @State private var useRawSignal: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header card
                    headerCard

                    if let report = report {
                        // Metadata card with Gender toggle
                        metadataCard(report: report)

                        // Clinical Interpretation Banner
                        clinicalEvaluationCard(report: report)

                        // KPI Grid
                        kpiGrid(report: report)

                        // QT Technical Highlights
                        qtHighlightCard(report: report)

                        // Segmented control
                        Picker("Visualizzazione", selection: $selectedTab) {
                            Text("Tracciato").tag(0)
                            Text("QT Tangente").tag(1)
                            Text("Battiti").tag(2)
                            Text("Lorenz").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 4)

                        // Selected tab content
                        switch selectedTab {
                        case 0:
                            continuousEcgStripView(report: report)
                        case 1:
                            medianBeatTangentView(report: report)
                        case 2:
                            beatTableView(report: report)
                        default:
                            lorenzPlotView(report: report)
                        }

                        // Export PDF Action Button
                        pdfExportSection(report: report)
                    } else {
                        emptyStateView
                    }
                }
                .padding()
            }
            .navigationTitle("Dynamic ECG")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isImporting = true
                        } label: {
                            Label("Apri CSV da File", systemImage: "doc.badge.plus")
                        }

                        Button {
                            isNotesSheetPresented = true
                        } label: {
                            Label("Aggiungi Note Cliniche", systemImage: "pencil.and.list.clipboard")
                        }

                        Divider()

                        Menu("Carica Tracciato di Esempio") {
                            Button("Tracciato Sinusale 1 (70 bpm)") {
                                loadSample(named: "Sinusale_1", hr: 70, qt: 354)
                            }
                            Button("Tracciato Sinusale 2 (92 bpm)") {
                                loadSample(named: "Sinusale_2", hr: 92, qt: 324)
                            }
                            Button("Frequenza Elevata (113 bpm)") {
                                loadSample(named: "Elevata_113bpm", hr: 113, qt: 291)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
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
            .sheet(isPresented: $isNotesSheetPresented) {
                notesInputSheet
            }
            .onAppear {
                if report == nil {
                    loadSample(named: "Sinusale_1", hr: 70, qt: 354)
                }
            }
        }
    }

    // MARK: - Header & Metadata

    private var headerCard: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tracciato Apple Watch")
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
                Label("Sfoglia", systemImage: "folder")
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
        VStack(spacing: 8) {
            HStack {
                Label(report.metadata.recordedDate, systemImage: "calendar")
                Spacer()
                Label(report.metadata.device, systemImage: "applewatch")
            }
            Divider()
            HStack {
                Label(report.metadata.classification, systemImage: "waveform.path.ecg")
                    .foregroundStyle(report.metadata.classification.lowercased().contains("elevata") ? .orange : .green)
                Spacer()
                Text("\(String(format: "%.1f Hz", report.fs)) • \(String(format: "%.0f s", report.durationSec))")
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text("Genere per intervalli QTc:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Genere", selection: $selectedGender) {
                    ForEach(Gender.allCases) { g in
                        Text(g.rawValue).tag(g)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
        }
        .font(.caption)
        .padding(12)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Clinical Evaluation Card

    private func statusColor(for status: QTcStatus) -> Color {
        switch status {
        case .normal: return .green
        case .borderline: return .orange
        case .prolonged, .shortened: return .red
        }
    }

    @ViewBuilder
    private func clinicalEvaluationCard(report: ECGAnalysisReport) -> some View {
        if let s = report.qtSummary {
            let eval = s.evaluate(for: selectedGender)
            let color = statusColor(for: eval.status)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: eval.isWarning ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .foregroundStyle(color)
                    Text("Valutazione Clinica QTc: \(eval.status.rawValue.uppercased())")
                        .font(.subheadline.bold())
                        .foregroundStyle(color)
                    Spacer()
                    Text("Linee Guida AHA")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(eval.text)
                    .font(.caption)
                    .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    Text("Normale: < \(selectedGender == .male ? "450" : "460") ms")
                    Text("Borderline: \(selectedGender == .male ? "450-470" : "460-480") ms")
                    Text("Prolungato: > \(selectedGender == .male ? "470" : "480") ms")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.4), lineWidth: 1)
            )
        }
    }

    private func kpiGrid(report: ECGAnalysisReport) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            kpiTile(title: "Frequenza", value: "\(String(format: "%.0f", report.bpm)) BPM", color: .red)
            kpiTile(title: "Picchi R", value: "\(report.rPeakIndices.count)", color: .blue)
            kpiTile(title: "RR Medio", value: "\(String(format: "%.0f", report.hrv.meanRR)) ms", color: .orange)
            kpiTile(title: "SDNN (HRV)", value: "\(String(format: "%.1f", report.hrv.sdnn)) ms", color: .purple)
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
                Text("Intervalli di Ripolarizzazione")
                    .font(.footnote.bold())
                Spacer()
                if let s = report.qtSummary {
                    Text(s.isReliable ? "✅ Alta Affidabilità" : "⚠️ Dispersione / Rumore")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(s.isReliable ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                        .foregroundStyle(s.isReliable ? .green : .orange)
                        .clipShape(Capsule())
                }
            }

            if let s = report.qtSummary {
                HStack(alignment: .firstTextBaseline) {
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

                HStack {
                    Text("Framingham: \(String(format: "%.0f ms", s.qtcFramingham))")
                    Spacer()
                    Text("Hodges: \(String(format: "%.0f ms", s.qtcHodges))")
                    Spacer()
                    Text("QRS: \(String(format: "%.0f ms", s.qrsMs))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text("Morfologia dell'onda T non sufficientemente chiara per il calcolo automatico del QT.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 30-Second Continuous Strip with Medical Grid

    private func continuousEcgStripView(report: ECGAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tracciato Continuo (30 s)")
                    .font(.subheadline.bold())
                Spacer()
                Text("Scorri orizzontalmente ➔")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Controls for scaling & filter toggle
            HStack {
                Picker("Scala", selection: $speedScale) {
                    Text("25 mm/s").tag(1.0)
                    Text("50 mm/s").tag(2.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Spacer()

                Toggle("Grezzo", isOn: $useRawSignal)
                    .font(.caption2)
                    .toggleStyle(.button)
                    .tint(.orange)
            }

            let sig = useRawSignal ? report.rawSignal : report.filteredSignal
            let fs = report.fs
            let totalSec = report.durationSec
            let pointsPerSecond = 100.0 * speedScale
            let totalWidth = max(350.0, totalSec * pointsPerSecond)

            ScrollView(.horizontal, showsIndicators: true) {
                Canvas { context, size in
                    // 1. Draw Medical ECG Grid
                    let secWidth = pointsPerSecond
                    let smallBoxW = secWidth * 0.04
                    let largeBoxW = secWidth * 0.20
                    let boxH = 20.0 * voltageScale

                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.04, green: 0.06, blue: 0.11)))

                    var x = 0.0
                    while x < size.width {
                        context.stroke(Path { p in
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: size.height))
                        }, with: .color(Color.red.opacity(0.08)), lineWidth: 0.5)
                        x += smallBoxW
                    }

                    x = 0.0
                    while x < size.width {
                        context.stroke(Path { p in
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: size.height))
                        }, with: .color(Color.red.opacity(0.25)), lineWidth: 1.0)
                        x += largeBoxW
                    }

                    var y = 0.0
                    while y < size.height {
                        context.stroke(Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: size.width, y: y))
                        }, with: .color(Color.red.opacity(0.12)), lineWidth: 0.5)
                        y += boxH
                    }

                    let midY = size.height / 2.0
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: 0, y: midY))
                        p.addLine(to: CGPoint(x: size.width, y: midY))
                    }, with: .color(Color.red.opacity(0.4)), lineWidth: 1.2)

                    // 2. Waveform
                    guard sig.count > 1 else { return }
                    let mvScale = 100.0 * voltageScale

                    var wavePath = Path()
                    for i in 0..<sig.count {
                        let curSec = Double(i) / fs
                        let px = curSec * pointsPerSecond
                        let py = midY - CGFloat(sig[i] * mvScale)
                        if i == 0 { wavePath.move(to: CGPoint(x: px, y: py)) } else { wavePath.addLine(to: CGPoint(x: px, y: py)) }
                    }
                    context.stroke(wavePath, with: .color(useRawSignal ? .orange : .cyan), lineWidth: 1.4)

                    // 3. R peak markers
                    for r in report.rPeakIndices where r < sig.count {
                        let rx = (Double(r) / fs) * pointsPerSecond
                        let ry = midY - CGFloat(sig[r] * mvScale)
                        context.stroke(Path { p in
                            p.move(to: CGPoint(x: rx - 4, y: ry - 4))
                            p.addLine(to: CGPoint(x: rx + 4, y: ry + 4))
                            p.move(to: CGPoint(x: rx - 4, y: ry + 4))
                            p.addLine(to: CGPoint(x: rx + 4, y: ry - 4))
                        }, with: .color(.red), lineWidth: 2.0)
                    }

                    // 4. P peaks
                    for pIdx in report.pPeakIndices where pIdx < sig.count {
                        let px = (Double(pIdx) / fs) * pointsPerSecond
                        let py = midY - CGFloat(sig[pIdx] * mvScale)
                        context.fill(Path(ellipseIn: CGRect(x: px - 2.5, y: py - 2.5, width: 5, height: 5)), with: .color(.green))
                    }
                }
                .frame(width: totalWidth, height: 260)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                Label("Griglia clinica: 1 mm = 40 ms / 0.1 mV", systemImage: "grid")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(useRawSignal ? "Segnale Grezzo (uV/1000)" : "Fase-Zero filtfilt")
                    .font(.caption2.bold())
                    .foregroundStyle(useRawSignal ? .orange : .blue)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Median Beat & Tangent Method

    private func medianBeatTangentView(report: ECGAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Battito Mediano e Metodo della Tangente")
                    .font(.subheadline.bold())
                Spacer()
                if let mb = report.medianBeat {
                    Text("QT = \(String(format: "%.0f ms", mb.qtMs))")
                        .font(.subheadline.bold())
                        .foregroundStyle(.yellow)
                }
            }

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

                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.06, green: 0.08, blue: 0.14)))

                    // Isoelectric dotted line
                    let isoNorm = CGFloat((mb.vIso - minVal) / range)
                    let isoY = size.height * (1.0 - isoNorm)
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: 0, y: isoY))
                        p.addLine(to: CGPoint(x: size.width, y: isoY))
                    }, with: .color(Color.gray.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    // Shaded QT area
                    let qX = pt(mb.qOnIndex).x
                    let tEndPt = pt(mb.tEndIndex)
                    let qtRect = CGRect(x: qX, y: 0, width: max(5, tEndPt.x - qX), height: size.height)
                    context.fill(Path(qtRect), with: .color(Color.yellow.opacity(0.15)))

                    // Waveform
                    var path = Path()
                    for i in 0..<w.count {
                        let p = pt(i)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    context.stroke(path, with: .color(.white), lineWidth: 3.0)

                    // Tangent line on descending limb
                    let k = mb.kSlopeIndex
                    let m = mb.mSlope
                    let x0 = max(0, k - 15)
                    let x1 = min(w.count - 1, mb.tEndIndex + 10)
                    let p0 = CGPoint(x: pt(x0).x, y: size.height * (1.0 - CGFloat((mb.vSlope + m * Double(x0 - k) - minVal) / range)))
                    let p1 = CGPoint(x: pt(x1).x, y: size.height * (1.0 - CGFloat((mb.vSlope + m * Double(x1 - k) - minVal) / range)))
                    context.stroke(Path { p in
                        p.move(to: p0)
                        p.addLine(to: p1)
                    }, with: .color(.orange), style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))

                    // Markers
                    let marks: [(Int, Color, String)] = [
                        (mb.qOnIndex, .blue, "Q"),
                        (mb.tPeakIndex, .green, "T peak"),
                        (mb.tEndIndex, .red, "T end")
                    ]
                    for (idx, color, _) in marks {
                        let p = pt(idx)
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(color))
                        context.stroke(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(.white), lineWidth: 1.5)
                    }
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 16) {
                    Label("Inizio Q", systemImage: "circle.fill").foregroundStyle(.blue)
                    Label("Picco T", systemImage: "circle.fill").foregroundStyle(.green)
                    Label("Fine T (Tangente)", systemImage: "circle.fill").foregroundStyle(.red)
                }
                .font(.caption2.bold())
            }
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Beat Table

    private func beatTableView(report: ECGAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tabella Battito per Battito (\(report.beats.count) battiti)")
                .font(.subheadline.bold())

            ForEach(report.beats) { beat in
                HStack {
                    Text("#\(beat.beatNumber)")
                        .font(.caption.bold())
                    Spacer()
                    Text("Tempo: \(String(format: "%.1f s", beat.rTimeSec))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("RR: \(String(format: "%.0f ms", beat.rrMs))")
                        .font(.caption2)
                    Spacer()
                    Text("QT: \(String(format: "%.0f ms", beat.qtMs))")
                        .font(.caption.bold())
                    Spacer()
                    Text("QTcF: \(String(format: "%.0f", beat.qtcFridericia))")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                }
                .padding(.vertical, 3)
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
            Text("Grafico di Lorenz (Poincaré: RR_n vs RR_n+1)")
                .font(.subheadline.bold())

            Canvas { context, size in
                let rr = report.rrIntervalsMs
                guard rr.count > 2 else { return }
                let minRR = max(300.0, (rr.min() ?? 500.0) - 100.0)
                let maxRR = min(1500.0, (rr.max() ?? 1000.0) + 100.0)
                let span = max(100.0, maxRR - minRR)

                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.05, green: 0.07, blue: 0.12)))

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
                    context.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: y - 3.5, width: 7, height: 7)), with: .color(.cyan))
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("I punti allineati lungo la diagonale y = x indicano ritmo sinusale fisiologico regolare.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - PDF Export Section

    private func pdfExportSection(report: ECGAnalysisReport) -> some View {
        VStack(spacing: 10) {
            Button {
                #if canImport(UIKit)
                if let url = PDFReportGenerator.generatePDF(for: report, gender: selectedGender, userNotes: userNotes) {
                    self.generatedPDFURL = url
                    self.isSharingPDF = true
                }
                #endif
            } label: {
                HStack {
                    Image(systemName: "doc.richtext.fill")
                    Text("Esporta Referto Medico PDF A4")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if let url = generatedPDFURL {
                ShareLink(item: url) {
                    Label("Invia Referto (Condividi / Salva)", systemImage: "square.and.arrow.up")
                        .font(.footnote.bold())
                }
            }
        }
    }

    // MARK: - Sheets

    private var notesInputSheet: some View {
        NavigationStack {
            Form {
                Section("Sintomi o Note Cliniche") {
                    TextField("Es. Palpitazioni a riposo, dopo caffè...", text: $userNotes, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section("Genere del Paziente") {
                    Picker("Genere", selection: $selectedGender) {
                        ForEach(Gender.allCases) { g in
                            Text(g.rawValue).tag(g)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Dettagli Paziente")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fatto") {
                        isNotesSheetPresented = false
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("Nessun tracciato caricato")
                .font(.headline)
            Text("Seleziona 'Apri CSV da File' nel menu in alto a destra per analizzare un ECG esportato dall'app Salute.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Import & Processing

    private func handleFileImport(result: Result<[URL], Error>) {
        do {
            guard let selectedFile = try result.get().first else { return }
            guard selectedFile.startAccessingSecurityScopedResource() else { return }
            defer { selectedFile.stopAccessingSecurityScopedResource() }

            let content = try String(contentsOf: selectedFile, encoding: .utf8)
            let (meta, samples, fs) = ECGParser.parseCSV(content: content)
            processSignal(samples: samples, fs: fs, metadata: meta, name: selectedFile.lastPathComponent)
        } catch {
            print("Errore caricamento: \(error)")
        }
    }

    private func processSignal(samples: [Double], fs: Double, metadata: ECGMetadata, name: String) {
        guard samples.count > 100 else { return }
        let duration = Double(samples.count) / fs

        let baselineFree = ECGProcessor.removeBaselineWander(signal: samples, fs: fs)
        let rPeaks = ECGProcessor.detectRPeaks(signal: baselineFree, fs: fs)
        let pPeaks = ECGProcessor.detectPWaves(signal: baselineFree, rPeaks: rPeaks, fs: fs)

        var rrIntervals: [Double] = []
        if rPeaks.count > 1 {
            for i in 0..<(rPeaks.count - 1) {
                rrIntervals.append((Double(rPeaks[i + 1] - rPeaks[i]) / fs) * 1000.0)
            }
        }

        let bpm = duration > 0 ? (Double(rPeaks.count) / duration) * 60.0 : 0.0
        let hrv = ECGProcessor.calculateHRV(rrMs: rrIntervals)
        let (summary, medBeat, beats) = ECGProcessor.analyzeQT(signal: baselineFree, rPeaks: rPeaks, fs: fs)

        self.fileName = name
        self.report = ECGAnalysisReport(
            metadata: metadata,
            fs: fs,
            durationSec: duration,
            rawSignal: samples,
            filteredSignal: baselineFree,
            rPeakIndices: rPeaks,
            pPeakIndices: pPeaks,
            bpm: bpm,
            hrv: hrv,
            rrIntervalsMs: rrIntervals,
            qtSummary: summary,
            medianBeat: medBeat,
            beats: beats,
            userNotes: userNotes
        )
        self.generatedPDFURL = nil
    }

    private func loadSample(named: String, hr: Double, qt: Double) {
        let fs = 512.0
        let n = Int(30.0 * fs)
        var synthetic = [Double](repeating: 0.0, count: n)
        let rrSamples = Int((60.0 / hr) * fs)

        for r in stride(from: Int(0.4 * fs), to: n - Int(0.5 * fs), by: rrSamples) {
            synthetic[r] = 0.85
            if r - Int(0.03 * fs) >= 0 { synthetic[r - Int(0.03 * fs)] = -0.15 }
            if r + Int(0.04 * fs) < n { synthetic[r + Int(0.04 * fs)] = -0.25 }
            let tPeak = r + Int((qt * 0.65 / 1000.0) * fs)
            if tPeak < n { synthetic[tPeak] = 0.22 }
            let pPeak = r - Int(0.16 * fs)
            if pPeak >= 0 { synthetic[pPeak] = 0.08 }
        }

        var meta = ECGMetadata()
        meta.recordedDate = "Tracciato Esempio"
        meta.classification = hr > 100 ? "Frequenza cardiaca elevata" : "Ritmo sinusale"
        meta.device = "Apple Watch Series"
        processSignal(samples: synthetic, fs: fs, metadata: meta, name: "\(named) (\(Int(hr)) bpm)")
    }
}
