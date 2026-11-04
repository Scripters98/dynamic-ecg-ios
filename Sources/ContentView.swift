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
    @State private var isArchiveSheetPresented: Bool = false
    @State private var isSettingsSheetPresented: Bool = false
    @State private var generatedPDFURL: URL?
    @State private var isSharingPDF: Bool = false
    @State private var timeWindowSec: Double = 10.0
    @State private var timeOffsetSec: Double = 0.0
    
    // 3D VCG rotation states
    @State private var vcgYaw: Double = 35.0
    @State private var vcgPitch: Double = -25.0
    @State private var vcgScale: Double = 1.0
    @State private var vcgAutoRotate: Bool = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard

                    if let report = report {
                        // Multi-lead selector if Holter recording
                        if report.multiLead.hasMultipleLeads {
                            leadSelectorCard(report: report)
                        }

                        // Clinical Interpretation Banner
                        clinicalEvaluationCard(report: report)

                        // KPI Grid (HR, QTc, PR, SDNN)
                        kpiGrid(report: report)

                        // Main 6-Tab Segmented Selector
                        tabSelector

                        // Tab Content View
                        tabContentView(report: report)

                        // PDF Export Section
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
                    toolbarMenu
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.commaSeparatedText, .plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
            .sheet(isPresented: $isNotesSheetPresented) {
                notesSheet
            }
            .sheet(isPresented: $isArchiveSheetPresented) {
                archiveSheet
            }
            .sheet(isPresented: $isSettingsSheetPresented) {
                settingsSheet
            }
            .sheet(isPresented: $isSharingPDF) {
                if let url = generatedPDFURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .onAppear {
                if report == nil {
                    loadClinicalSample(PreloadedSamples.allSamples[0])
                }
            }
        }
    }

    // MARK: - Toolbar Menu

    private var toolbarMenu: some View {
        Menu {
            Button {
                isImporting = true
            } label: {
                Label("Importa CSV da File", systemImage: "doc.badge.plus")
            }

            Button {
                isArchiveSheetPresented = true
            } label: {
                Label("Archivio & Casi Clinici", systemImage: "folder")
            }

            Button {
                isNotesSheetPresented = true
            } label: {
                Label("Note Cliniche", systemImage: "pencil.and.list.clipboard")
            }

            Button {
                isSettingsSheetPresented = true
            } label: {
                Label("Parametri & Calibrazione", systemImage: "slider.horizontal.3")
            }

            Divider()

            Menu("Casi Clinici di Riferimento") {
                ForEach(PreloadedSamples.allSamples, id: \.id) { sample in
                    Button(sample.title) {
                        loadClinicalSample(sample)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.title2)
                    .foregroundColor(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName)
                        .font(.headline)
                        .lineLimit(1)
                    if let report = report {
                        Text("\(report.metadata.device) • \(String(format: "%.0f Hz", report.fs)) • \(String(format: "%.1f s", report.durationSec))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if let report = report {
                    Text(report.selectedLead.rawValue)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.cyan.opacity(0.15))
                        .foregroundColor(.cyan)
                        .cornerRadius(6)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Lead Selector Card

    private func leadSelectorCard(report: ECGAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Derivazione Attiva (Registrazione Multi-Canale):")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            Picker("Derivazione", selection: Binding(
                get: { report.selectedLead },
                set: { newLead in switchLead(to: newLead) }
            )) {
                ForEach(LeadSelection.allCases) { lead in
                    Text(lead.rawValue).tag(lead)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Clinical Evaluation Card

    private func clinicalEvaluationCard(report: ECGAnalysisReport) -> some View {
        let (status, text, isWarn) = report.qtSummary?.evaluate(for: selectedGender) ?? (.normal, "Calcolo non disponibile", false)
        let evalColor = statusColor(for: status)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: isWarn ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .foregroundColor(evalColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.rawValue)
                        .font(.headline)
                        .foregroundColor(evalColor)
                    Text(text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(selectedGender.rawValue)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(6)
            }

            if let qt = report.qtSummary {
                HStack(spacing: 12) {
                    Label(qt.isReliable ? "Affidabile (IQR < 30 ms)" : "Variabilità battiti elevata", systemImage: qt.isReliable ? "shield.checkmark" : "shield.slash")
                        .font(.caption2)
                        .foregroundColor(qt.isReliable ? .green : .orange)
                    Spacer()
                    Text("Battiti analizzati: \(qt.beatsAnalyzed)/\(qt.beatsTotal)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(evalColor.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(evalColor.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private func statusColor(for status: QTcStatus) -> Color {
        switch status {
        case .normal: return .green
        case .borderline: return .yellow
        case .prolonged: return .red
        case .shortened: return .orange
        }
    }

    // MARK: - KPI Grid

    private func kpiGrid(report: ECGAnalysisReport) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            kpiTile(title: "Frequenza Media", value: "\(Int(round(report.bpm))) bpm", icon: "heart.fill", color: .red)
            kpiTile(title: "QTc Fridericia", value: report.qtSummary != nil ? "\(Int(round(report.qtSummary!.qtcFridericia))) ms" : "N/D", icon: "timer", color: .cyan)
            kpiTile(title: "Intervallo PR", value: report.phasorData.meanPRMs > 0 ? "\(Int(round(report.phasorData.meanPRMs))) ms" : "N/D", icon: "wave.3.forward", color: .green)
            kpiTile(title: "Variabilità (SDNN)", value: "\(Int(round(report.hrv.sdnn))) ms", icon: "chart.xyaxis.line", color: .purple)
        }
    }

    private func kpiTile(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            Text(value)
                .font(.title3.bold())
                .foregroundColor(.primary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tabButton(title: "Tracciato", index: 0, icon: "waveform.path.ecg")
                tabButton(title: "Onde P & Fasore", index: 1, icon: "bolt.horizontal")
                tabButton(title: "Variabilità & Lorenz", index: 2, icon: "point.3.filled.connected.triangle.path")
                tabButton(title: "Spettrogramma", index: 3, icon: "chart.bar.xaxis")
                tabButton(title: "QT & Mediano", index: 4, icon: "cross.case")
                tabButton(title: "Loop 3D / VCG", index: 5, icon: "cube")
            }
            .padding(.horizontal, 2)
        }
    }

    private func tabButton(title: String, index: Int, icon: String) -> some View {
        Button {
            selectedTab = index
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedTab == index ? Color.cyan : Color(.secondarySystemBackground))
            .foregroundColor(selectedTab == index ? .black : .primary)
            .cornerRadius(8)
        }
    }

    // MARK: - Tab Content View

    @ViewBuilder
    private func tabContentView(report: ECGAnalysisReport) -> some View {
        switch selectedTab {
        case 0:
            continuousEcgStripView(report: report)
        case 1:
            phasorAndPWaveView(report: report)
        case 2:
            lorenzAndTachogramView(report: report)
        case 3:
            spectrogramAndPanTompkinsView(report: report)
        case 4:
            medianBeatTangentView(report: report)
        default:
            vcg3DView(report: report)
        }
    }

    // MARK: - Tab 0: Continuous Calibrated Strip

    private func continuousEcgStripView(report: ECGAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Striscia Elettrocardiografica Calibrata")
                    .font(.headline)
                Spacer()
                Text("Scala: \(Int(25 * speedScale)) mm/s · \(Int(10 * voltageScale)) mm/mV")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Window zoom / time position slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Finestra: \(String(format: "%.1f", timeOffsetSec))s - \(String(format: "%.1f", min(report.durationSec, timeOffsetSec + timeWindowSec)))s")
                        .font(.caption2.bold())
                    Spacer()
                    Text("Totale: \(String(format: "%.0f", report.durationSec))s")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Slider(value: $timeOffsetSec, in: 0...max(0, report.durationSec - timeWindowSec), step: 0.5)
            }

            // Calibrated Strip Canvas
            calibratedStripCanvas(report: report)
                .frame(height: 220)
                .cornerRadius(8)

            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("Picchi R (Pan-Tompkins)").font(.caption2)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("Onde P (Fasore)").font(.caption2)
                }
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func calibratedStripCanvas(report: ECGAnalysisReport) -> some View {
        Canvas { context, size in
            let fs = report.fs
            let sig = report.filteredSignal
            let startIdx = Int(timeOffsetSec * fs)
            let windowCount = Int(timeWindowSec * fs)
            let endIdx = min(sig.count, startIdx + windowCount)
            guard endIdx > startIdx else { return }

            // Pink medical grid background
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 1.0, green: 0.95, blue: 0.95)))

            // Medical grid lines
            let secWidth = size.width / CGFloat(timeWindowSec)
            let smallBoxW = secWidth * 0.04
            let largeBoxW = secWidth * 0.20
            let boxH: CGFloat = 16.0

            // Small vertical lines
            var gx: CGFloat = 0
            while gx <= size.width {
                var p = Path()
                p.move(to: CGPoint(x: gx, y: 0))
                p.addLine(to: CGPoint(x: gx, y: size.height))
                context.stroke(p, with: .color(Color(red: 1.0, green: 0.80, blue: 0.80, opacity: 0.5)), lineWidth: 0.5)
                gx += smallBoxW
            }

            // Large vertical lines
            gx = 0
            while gx <= size.width {
                var p = Path()
                p.move(to: CGPoint(x: gx, y: 0))
                p.addLine(to: CGPoint(x: gx, y: size.height))
                context.stroke(p, with: .color(Color(red: 0.95, green: 0.60, blue: 0.60, opacity: 0.8)), lineWidth: 1.0)
                gx += largeBoxW
            }

            // Horizontal lines
            var gy: CGFloat = 0
            while gy <= size.height {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: gy))
                p.addLine(to: CGPoint(x: size.width, y: gy))
                context.stroke(p, with: .color(Color(red: 1.0, green: 0.80, blue: 0.80, opacity: 0.5)), lineWidth: 0.5)
                gy += boxH
            }

            let midY = size.height / 2.0
            let yGain: CGFloat = 70.0 * CGFloat(voltageScale)

            // ECG Signal Trace
            var sigPath = Path()
            for i in startIdx..<endIdx {
                let relSec = Double(i - startIdx) / fs
                let px = CGFloat(relSec) * secWidth
                let py = midY - CGFloat(sig[i]) * yGain
                if i == startIdx { sigPath.move(to: CGPoint(x: px, y: py)) } else { sigPath.addLine(to: CGPoint(x: px, y: py)) }
            }
            context.stroke(sigPath, with: .color(.black), lineWidth: 1.3)

            // R-Peaks (Red circles)
            for r in report.rPeakIndices where r >= startIdx && r < endIdx {
                let rx = CGFloat(Double(r - startIdx) / fs) * secWidth
                let ry = midY - CGFloat(sig[r]) * yGain
                context.fill(Path(ellipseIn: CGRect(x: rx - 3, y: ry - 3, width: 6, height: 6)), with: .color(.red))
            }

            // P-Peaks (Green circles)
            for p in report.phasorData.pPeaks where p >= startIdx && p < endIdx {
                let px = CGFloat(Double(p - startIdx) / fs) * secWidth
                let py = midY - CGFloat(sig[p]) * yGain
                context.fill(Path(ellipseIn: CGRect(x: px - 2.5, y: py - 2.5, width: 5, height: 5)), with: .color(.green))
            }
        }
    }

    // MARK: - Tab 1: P-Waves & Phasor Transform

    private func phasorAndPWaveView(report: ECGAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Analisi Onde P & Trasformata Fasoriale")
                .font(.headline)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Intervallo PR Medio")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(round(report.phasorData.meanPRMs))) ms")
                        .font(.title3.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Stato Conduzione AV")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(report.phasorData.prStatus)
                        .font(.caption.bold())
                        .foregroundColor(report.phasorData.meanPRMs > 200 ? .orange : .green)
                }
            }
            .padding(10)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(8)

            // Phasor canvas
            phasorCanvas(report: report)
                .frame(height: 200)
                .background(Color.black.opacity(0.85))
                .cornerRadius(8)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.cyan).frame(width: 14, height: 2)
                    Text("ECG Filtrato").font(.caption2)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.purple).frame(width: 14, height: 2)
                    Text("Segnale Fasoriale atan2(x, rv)").font(.caption2)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Onde P rilevate").font(.caption2)
                }
            }
            .foregroundColor(.secondary)

            Text("💡 La Trasformata Fasoriale enfatizza le variazioni lente di potenziale come le onde P atriali rispetto al fondo iso-elettrico, permettendo la stima accurata della conduzione atrio-ventricolare (PR).")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func phasorCanvas(report: ECGAnalysisReport) -> some View {
        Canvas { context, size in
            let fs = report.fs
            let sig = report.filteredSignal
            let ph = report.phasorData.phasor
            let startIdx = Int(timeOffsetSec * fs)
            let windowCount = Int(min(5.0, timeWindowSec) * fs) // 5s zoom for phasor clarity
            let endIdx = min(sig.count, startIdx + windowCount)
            guard endIdx > startIdx && !ph.isEmpty else { return }

            let dx = size.width / CGFloat(windowCount)
            let midY = size.height / 2.0

            // Grid lines
            var gridPath = Path()
            for x in stride(from: 0, to: size.width, by: 40) {
                gridPath.move(to: CGPoint(x: x, y: 0))
                gridPath.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(gridPath, with: .color(Color.white.opacity(0.1)), lineWidth: 0.5)

            // ECG Trace (Cyan)
            var sigPath = Path()
            for i in startIdx..<endIdx {
                let px = CGFloat(i - startIdx) * dx
                let py = midY - CGFloat(sig[i]) * 60.0
                if i == startIdx { sigPath.move(to: CGPoint(x: px, y: py)) } else { sigPath.addLine(to: CGPoint(x: px, y: py)) }
            }
            context.stroke(sigPath, with: .color(.cyan), lineWidth: 1.2)

            // Phasor Trace (Purple)
            var phPath = Path()
            for i in startIdx..<endIdx {
                let px = CGFloat(i - startIdx) * dx
                let py = midY - CGFloat(ph[i]) * 25.0
                if i == startIdx { phPath.move(to: CGPoint(x: px, y: py)) } else { phPath.addLine(to: CGPoint(x: px, y: py)) }
            }
            context.stroke(phPath, with: .color(.purple), style: StrokeStyle(lineWidth: 1.0, dash: [4, 3]))

            // P peaks
            for p in report.phasorData.pPeaks where p >= startIdx && p < endIdx {
                let px = CGFloat(p - startIdx) * dx
                let py = midY - CGFloat(sig[p]) * 60.0
                context.fill(Path(ellipseIn: CGRect(x: px - 3, y: ry(for: py), width: 6, height: 6)), with: .color(.green))
            }
        }
    }

    private func ry(for val: CGFloat) -> CGFloat {
        return val - 3
    }

    // MARK: - Tab 2: Lorenz Plot & Tachogram

    private func lorenzAndTachogramView(report: ECGAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Grafico di Lorenz (Poincaré) & Tachogramma RR")
                .font(.headline)

            HStack(spacing: 8) {
                lorenzPlotCanvas(report: report)
                    .frame(height: 190)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 6) {
                    statRow(label: "Corr. ρ", value: String(format: "%.2f", report.hrv.correlationRho))
                    statRow(label: "SD1 (rapida)", value: "\(Int(round(report.hrv.sd1))) ms")
                    statRow(label: "SD2 (lunga)", value: "\(Int(round(report.hrv.sd2))) ms")
                    statRow(label: "SD1 / SD2", value: String(format: "%.2f", report.hrv.sd1Sd2Ratio))
                    statRow(label: "RMSSD", value: "\(Int(round(report.hrv.rmssd))) ms")
                    statRow(label: "pNN50", value: String(format: "%.1f%%", report.hrv.pnn50))
                }
                .padding(8)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(8)
            }

            // Continuous Tachogram Curve
            Text("Tachogramma Temporale (RR & BPM Istantanei)")
                .font(.subheadline.bold())

            tachogramCanvas(report: report)
                .frame(height: 150)
                .background(Color.black.opacity(0.85))
                .cornerRadius(8)

            // Beat Table excerpt
            Text("Ultimi Battiti Registrati:")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                ForEach(report.beats.prefix(5)) { b in
                    HStack {
                        Text("Battito #\(b.beatNumber)")
                            .font(.caption2.bold())
                        Spacer()
                        Text("RR: \(Int(round(b.rrMs))) ms")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("QT: \(Int(round(b.qtMs))) ms")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("QTc: \(Int(round(b.qtcFridericia))) ms")
                            .font(.caption2.bold())
                            .foregroundColor(.cyan)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(4)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption2.bold())
        }
    }

    private func lorenzPlotCanvas(report: ECGAnalysisReport) -> some View {
        Canvas { context, size in
            let rrs = report.tachogram.rrIntervalsMs
            guard rrs.count > 1 else { return }

            let minRR = max(300.0, (rrs.min() ?? 600.0) - 100.0)
            let maxRR = min(1600.0, (rrs.max() ?? 1000.0) + 100.0)
            let span = max(100.0, maxRR - minRR)

            // Identity line y = x (Red dashed)
            var idLine = Path()
            idLine.move(to: CGPoint(x: 0, y: size.height))
            idLine.addLine(to: CGPoint(x: size.width, y: 0))
            context.stroke(idLine, with: .color(.red.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // Points
            for i in 0..<(rrs.count - 1) {
                let xNorm = CGFloat((rrs[i] - minRR) / span)
                let yNorm = CGFloat((rrs[i + 1] - minRR) / span)
                let px = xNorm * size.width
                let py = size.height - (yNorm * size.height)
                context.fill(Path(ellipseIn: CGRect(x: px - 3, y: py - 3, width: 6, height: 6)), with: .color(.cyan))
            }
        }
    }

    private func tachogramCanvas(report: ECGAnalysisReport) -> some View {
        Canvas { context, size in
            let rrs = report.tachogram.rrIntervalsMs
            let times = report.tachogram.beatTimesSec
            guard rrs.count > 1 else { return }

            let minRR = max(300.0, (rrs.min() ?? 600.0) - 50.0)
            let maxRR = (rrs.max() ?? 1000.0) + 50.0
            let span = max(100.0, maxRR - minRR)
            let totalT = max(1.0, times.last ?? 30.0)

            var path = Path()
            for i in 0..<rrs.count {
                let px = CGFloat(times[i] / totalT) * size.width
                let py = size.height - CGFloat((rrs[i] - minRR) / span) * size.height
                if i == 0 { path.move(to: CGPoint(x: px, y: py)) } else { path.addLine(to: CGPoint(x: px, y: py)) }
                context.fill(Path(ellipseIn: CGRect(x: px - 2, y: py - 2, width: 4, height: 4)), with: .color(.cyan))
            }
            context.stroke(path, with: .color(.cyan), lineWidth: 1.5)
        }
    }

    // MARK: - Tab 3: Spectrogram & Pan-Tompkins Window

    private func spectrogramAndPanTompkinsView(report: ECGAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Spettrogramma Tempo-Frequenza (0 - 50 Hz)")
                .font(.headline)

            // Heatmap Canvas
            spectrogramCanvas(report: report)
                .frame(height: 180)
                .cornerRadius(8)

            HStack {
                Text("0 Hz (DC / Linea Base)").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("50 Hz (Banda QRS / Rumore)").font(.caption2).foregroundColor(.secondary)
            }

            Divider()

            Text("Energia Integrata Pan-Tompkins (Finestra di Convoluzione)")
                .font(.headline)

            panTompkinsCanvas(report: report)
                .frame(height: 120)
                .background(Color.black.opacity(0.85))
                .cornerRadius(8)

            Text("💡 La finestra integrata di Pan-Tompkins combina derivata e quadratura per isolare le raffiche energetiche dei complessi QRS, superando il rumore e le onde T prominenti.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func spectrogramCanvas(report: ECGAnalysisReport) -> some View {
        Canvas { context, size in
            let spec = report.spectrogramData
            let numF = spec.freqBins.count
            let numT = spec.timeBins.count
            guard numF > 1 && numT > 1 else { return }

            let minDb = spec.minDb
            let maxDb = spec.maxDb
            let span = max(1.0, maxDb - minDb)

            let dx = size.width / CGFloat(numT)
            let dy = size.height / CGFloat(numF)

            for f in 0..<numF {
                for t in 0..<numT {
                    let val = spec.matrix[f][t]
                    let norm = (val - minDb) / span
                    let color = spectrogramColormap(norm: norm)
                    let rect = CGRect(
                        x: CGFloat(t) * dx,
                        y: size.height - CGFloat(f + 1) * dy,
                        width: dx + 0.5,
                        height: dy + 0.5
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }

    private func spectrogramColormap(norm: Double) -> Color {
        let v = max(0.0, min(1.0, norm))
        if v < 0.25 {
            return Color(red: 0, green: v * 4.0 * 0.8, blue: 0.5 + v * 2.0)
        } else if v < 0.5 {
            return Color(red: 0, green: 0.8 + (v - 0.25) * 0.8, blue: 1.0 - (v - 0.25) * 4.0)
        } else if v < 0.75 {
            return Color(red: (v - 0.5) * 4.0, green: 1.0, blue: 0)
        } else {
            return Color(red: 1.0, green: 1.0 - (v - 0.75) * 4.0, blue: 0)
        }
    }

    private func panTompkinsCanvas(report: ECGAnalysisReport) -> some View {
        Canvas { context, size in
            let win = report.panTompkinsData.windowSignal
            let fs = report.fs
            let startIdx = Int(timeOffsetSec * fs)
            let windowCount = Int(timeWindowSec * fs)
            let endIdx = min(win.count, startIdx + windowCount)
            guard endIdx > startIdx else { return }

            let maxVal = win.max() ?? 1.0
            let dx = size.width / CGFloat(windowCount)

            var path = Path()
            for i in startIdx..<endIdx {
                let px = CGFloat(i - startIdx) * dx
                let py = size.height - CGFloat(win[i] / maxVal) * (size.height - 10)
                if i == startIdx { path.move(to: CGPoint(x: px, y: py)) } else { path.addLine(to: CGPoint(x: px, y: py)) }
            }
            context.stroke(path, with: .color(.purple), lineWidth: 1.5)

            // Threshold line (Red dashed)
            let thY = size.height - CGFloat(report.panTompkinsData.threshold / maxVal) * (size.height - 10)
            var thPath = Path()
            thPath.move(to: CGPoint(x: 0, y: thY))
            thPath.addLine(to: CGPoint(x: size.width, y: thY))
            context.stroke(thPath, with: .color(.red.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }

    // MARK: - Tab 4: Median Beat & Tangent Method

    private func medianBeatTangentView(report: ECGAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Battito Mediano d'Insieme & Metodo della Tangente AHA")
                .font(.headline)

            if let mb = report.medianBeat {
                medianBeatCanvas(mb: mb)
                    .frame(height: 240)
                    .background(Color.black.opacity(0.9))
                    .cornerRadius(10)

                // Multi-formula QTc table
                multiFormulaCard(report: report)
            } else {
                Text("Battito mediano non disponibile.").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func medianBeatCanvas(mb: MedianBeatData) -> some View {
        Canvas { context, size in
            let w = mb.wave
            let n = w.count
            guard n > 1 else { return }

            let minV = (w.min() ?? -0.5) - 0.15
            let maxV = (w.max() ?? 1.0) + 0.25
            let span = max(0.5, maxV - minV)

            let dx = size.width / CGFloat(n)
            func py(_ v: Double) -> CGFloat {
                return size.height - CGFloat((v - minV) / span) * size.height
            }

            // Isoelectric baseline (Gray dot)
            let basePy = py(mb.vIso)
            var baseP = Path()
            baseP.move(to: CGPoint(x: 0, y: basePy))
            baseP.addLine(to: CGPoint(x: size.width, y: basePy))
            context.stroke(baseP, with: .color(.gray.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // Tangent Line (Orange)
            let k = mb.kSlopeIndex
            let m = mb.mSlope
            let v = mb.vSlope
            let xs = [max(0, k - 18), min(n - 1, mb.tEndIndex + 12)]
            var tanPath = Path()
            for (idx, x) in xs.enumerated() {
                let tangentV = v + m * Double(x - k)
                let pt = CGPoint(x: CGFloat(x) * dx, y: py(tangentV))
                if idx == 0 { tanPath.move(to: pt) } else { tanPath.addLine(to: pt) }
            }
            context.stroke(tanPath, with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))

            // Waveform (White / Cyan)
            var wPath = Path()
            for i in 0..<n {
                let pt = CGPoint(x: CGFloat(i) * dx, y: py(w[i]))
                if i == 0 { wPath.move(to: pt) } else { wPath.addLine(to: pt) }
            }
            context.stroke(wPath, with: .color(.white), lineWidth: 2.2)

            // Fiducial points
            drawMarker(context: context, x: CGFloat(mb.qOnIndex) * dx, y: py(w[mb.qOnIndex]), color: .blue, label: "Q")
            drawMarker(context: context, x: CGFloat(mb.tPeakIndex) * dx, y: py(w[mb.tPeakIndex]), color: .green, label: "T")
            drawMarker(context: context, x: CGFloat(mb.tEndIndex) * dx, y: py(mb.vIso), color: .red, label: "Fine T")
        }
    }

    private func drawMarker(context: GraphicsContext, x: CGFloat, y: CGFloat, color: Color, label: String) {
        context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(color))
    }

    private func multiFormulaCard(report: ECGAnalysisReport) -> some View {
        guard let qt = report.qtSummary else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("Confronto Formule di Correzione QTc (Linee Guida AHA/ACCF):")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                HStack {
                    formulaTile(name: "Fridericia (Raccom.)", value: "\(Int(round(qt.qtcFridericia))) ms", highlight: true)
                    formulaTile(name: "Bazett", value: "\(Int(round(qt.qtcBazett))) ms", highlight: false)
                }
                HStack {
                    formulaTile(name: "Framingham", value: "\(Int(round(qt.qtcFramingham))) ms", highlight: false)
                    formulaTile(name: "Hodges", value: "\(Int(round(qt.qtcHodges))) ms", highlight: false)
                }
            }
        )
    }

    private func formulaTile(name: String, value: String, highlight: Bool) -> some View {
        HStack {
            Text(name).font(.caption2).foregroundColor(highlight ? .cyan : .secondary)
            Spacer()
            Text(value).font(.caption.bold()).foregroundColor(highlight ? .cyan : .primary)
        }
        .padding(8)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(6)
    }

    // MARK: - Tab 5: 3D Vectorcardiography / Attractor Loop

    private func vcg3DView(report: ECGAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(report.vcgData.isMultiChannel ? "Vectorcardiogramma 3D Reale (3 Derivazioni)" : "Attrattore Spazio delle Fasi 3D (Takens)")
                    .font(.headline)
                Spacer()
                Button {
                    vcgYaw = 35.0
                    vcgPitch = -25.0
                    vcgScale = 1.0
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                }
            }

            // Interactive 3D Canvas
            vcgCanvas(report: report)
                .frame(height: 280)
                .background(Color.black.opacity(0.92))
                .cornerRadius(12)
                .gesture(
                    DragGesture()
                        .onChanged { val in
                            vcgYaw += Double(val.translation.width) * 0.04
                            vcgPitch += Double(val.translation.height) * 0.04
                        }
                )

            HStack {
                Text("Trascina per ruotare in 3D · Scala:").font(.caption2).foregroundColor(.secondary)
                Slider(value: $vcgScale, in: 0.5...2.5)
            }

            Text("💡 La visualizzazione 3D dello spazio delle fasi rivela la morfologia ad anello (loop) della depolarizzazione ventricolare (QRS) e ripolarizzazione (T).")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func vcgCanvas(report: ECGAnalysisReport) -> some View {
        Canvas { context, size in
            let points = report.vcgData.points
            guard points.count > 10 else { return }

            let cx = size.width / 2.0
            let cy = size.height / 2.0

            let yawRad = vcgYaw * .pi / 180.0
            let pitchRad = vcgPitch * .pi / 180.0

            let cosY = cos(yawRad), sinY = sin(yawRad)
            let cosP = cos(pitchRad), sinP = sin(pitchRad)

            var projected: [(p: CGPoint, z: Double)] = []

            for pt in points {
                // Scale factor
                let sx = pt.x * 90.0 * vcgScale
                let sy = pt.y * 90.0 * vcgScale
                let sz = pt.z * 90.0 * vcgScale

                // 3D rotation
                let x1 = sx * cosY + sz * sinY
                let z1 = -sx * sinY + sz * cosY

                let y2 = sy * cosP - z1 * sinP
                let z2 = sy * sinP + z1 * cosP

                // Perspective projection
                let dist = 400.0
                let factor = dist / (dist + z2)
                let px = cx + CGFloat(x1 * factor)
                let py = cy - CGFloat(y2 * factor)

                projected.append((CGPoint(x: px, y: py), z2))
            }

            // Draw connecting lines with depth color
            var path = Path()
            for (idx, item) in projected.enumerated() {
                if idx == 0 { path.move(to: item.p) } else { path.addLine(to: item.p) }
            }
            context.stroke(path, with: .color(.cyan.opacity(0.85)), lineWidth: 1.5)

            // Draw glowing points along trajectory
            for item in projected {
                let alpha = max(0.2, min(1.0, (item.z + 150.0) / 300.0))
                context.fill(Path(ellipseIn: CGRect(x: item.p.x - 2, y: item.p.y - 2, width: 4, height: 4)), with: .color(.cyan.opacity(alpha)))
            }
        }
    }

    // MARK: - PDF Export Section

    private func pdfExportSection(report: ECGAnalysisReport) -> some View {
        VStack(spacing: 12) {
            Button {
                generatePDF(report: report)
            } label: {
                HStack {
                    Image(systemName: "doc.text.fill")
                    Text("Esporta Referto Medico PDF Completo (A4)")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.cyan)
                .foregroundColor(.black)
                .cornerRadius(10)
            }

            if generatedPDFURL != nil {
                Button {
                    isSharingPDF = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Condividi o Salva Referto PDF")
                    }
                    .font(.subheadline)
                    .foregroundColor(.cyan)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 60))
                .foregroundColor(.cyan)
            Text("Benvenuto in Dynamic ECG Pro")
                .font(.title2.bold())
            Text("Importa un file CSV esportato da Apple Watch o seleziona un caso clinico di riferimento per avviare l'analisi completa.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("Carica Ritmo Sinusale Esempio") {
                loadClinicalSample(PreloadedSamples.allSamples[0])
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
        }
        .padding(30)
    }

    // MARK: - Sheets

    private var notesSheet: some View {
        NavigationStack {
            Form {
                Section("Note del Paziente o del Medico") {
                    TextEditor(text: $userNotes)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Note Cliniche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { isNotesSheetPresented = false }
                }
            }
        }
    }

    private var archiveSheet: some View {
        NavigationStack {
            List {
                Section("Casi Clinici di Riferimento Precaricati") {
                    ForEach(PreloadedSamples.allSamples, id: \.id) { sample in
                        Button {
                            loadClinicalSample(sample)
                            isArchiveSheetPresented = false
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.title).font(.subheadline.bold())
                                Text(sample.subtitle).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section("Registrazioni Importate in Memoria") {
                    let saved = StorageManager.shared.listSavedRecordings()
                    if saved.isEmpty {
                        Text("Nessuna registrazione salvata in archivio.").font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(saved) { item in
                            Button {
                                if let str = StorageManager.shared.readCSVContent(fileName: item.fileName) {
                                    analyzeContent(str, name: item.displayName)
                                    isArchiveSheetPresented = false
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName).font(.subheadline.bold())
                                    Text("\(item.dateStr) · \(Int(item.bpm)) bpm · QTc \(Int(item.qtcFridericia)) ms")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for idx in indexSet {
                                StorageManager.shared.deleteRecording(item: saved[idx])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Archivio & Registrazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { isArchiveSheetPresented = false }
                }
            }
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Sesso Biologico (Soglie AHA/ACCF)") {
                    Picker("Genere", selection: $selectedGender) {
                        ForEach(Gender.allCases) { g in
                            Text(g.rawValue).tag(g)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Calibrazione Striscia ECG") {
                    Picker("Velocità Carta", selection: $speedScale) {
                        Text("25 mm/s (Standard)").tag(1.0)
                        Text("50 mm/s (Espansa)").tag(2.0)
                    }
                    Picker("Guadagno Voltaggio", selection: $voltageScale) {
                        Text("10 mm/mV (Standard)").tag(1.0)
                        Text("20 mm/mV (Raddoppiato)").tag(2.0)
                    }
                }
            }
            .navigationTitle("Parametri & Calibrazione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { isSettingsSheetPresented = false }
                }
            }
        }
    }

    // MARK: - Actions & Engine Helpers

    private func handleFileImport(result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        if let data = try? Data(contentsOf: url), let content = String(data: data, encoding: .utf8) {
            analyzeContent(content, name: url.deletingPathExtension().lastPathComponent)
        }
    }

    private func loadClinicalSample(_ sample: ClinicalSample) {
        let (content, dName) = PreloadedSamples.loadSample(sample: sample)
        analyzeContent(content, name: dName)
    }

    private func analyzeContent(_ content: String, name: String) {
        let (meta, multi, fs) = ECGParser.parseCSV(content: content)
        let rep = ECGProcessor.analyze(
            multiLead: multi,
            metadata: meta,
            fs: fs,
            selectedLead: .lead1,
            userNotes: userNotes
        )
        self.fileName = name
        self.report = rep
        self.generatedPDFURL = nil

        // Save to local documents storage
        _ = StorageManager.shared.saveCSV(content: content, originalFileName: name, report: rep)
    }

    private func switchLead(to newLead: LeadSelection) {
        guard let current = report else { return }
        let updated = ECGProcessor.analyze(
            multiLead: current.multiLead,
            metadata: current.metadata,
            fs: current.fs,
            selectedLead: newLead,
            userNotes: userNotes
        )
        self.report = updated
    }

    private func generatePDF(report: ECGAnalysisReport) {
        if let url = PDFReportGenerator.generatePDF(for: report, gender: selectedGender, userNotes: userNotes) {
            self.generatedPDFURL = url
            self.isSharingPDF = true
        }
    }
}

// MARK: - ShareSheet Helper

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
