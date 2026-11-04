import Foundation

// MARK: - ECG Universal Parser (Apple Watch & Multi-Channel Holter)

public final class ECGParser {
    public static func parseCSV(content: String) -> (metadata: ECGMetadata, multiLead: MultiLeadData, fs: Double) {
        var meta = ECGMetadata()
        var fs = 512.0
        var lines = content.components(separatedBy: .newlines)
        
        var isMultiChannel = false
        var colLead1 = -1
        var colLead2 = -1
        var colLead3 = -1
        var colTime = -1
        
        var samples1: [Double] = []
        var samples2: [Double] = []
        var samples3: [Double] = []
        
        // Scan headers and comments
        for (idx, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let lower = line.lowercased()
            
            // Check metadata in comment or early lines
            if line.hasPrefix("#") || idx < 30 {
                if lower.contains("sample_rate:") || lower.contains("sample_rate,") || lower.contains("hertz") || lower.contains("hz") {
                    let cleaned = line.replacingOccurrences(of: "#", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                        .replacingOccurrences(of: ":", with: ",")
                    let parts = cleaned.components(separatedBy: ",")
                    for p in parts {
                        let sub = p.trimmingCharacters(in: .whitespaces)
                        let comps = sub.components(separatedBy: " ")
                        if let first = comps.first {
                            let cleanNum = first.replacingOccurrences(of: ",", with: ".")
                            if let val = Double(cleanNum), val >= 50.0 && val <= 2000.0 {
                                fs = val
                                meta.sampleRate = val
                            }
                        }
                    }
                }
                if lower.contains("date:") || lower.contains("date,") || lower.contains("data di registrazione") {
                    let parts = line.replacingOccurrences(of: "#", with: "").components(separatedBy: ":")
                    if parts.count >= 2 {
                        meta.recordedDate = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                    }
                }
                if lower.contains("classification") || lower.contains("classificazione") {
                    let parts = line.replacingOccurrences(of: "#", with: "").components(separatedBy: ":")
                    if parts.count >= 2 {
                        meta.classification = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                    }
                }
                if lower.contains("device") || lower.contains("dispositivo") {
                    let parts = line.replacingOccurrences(of: "#", with: "").components(separatedBy: ":")
                    if parts.count >= 2 {
                        meta.device = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                    }
                }
                if lower.contains("symptoms") || lower.contains("sintomi") {
                    let parts = line.replacingOccurrences(of: "#", with: "").components(separatedBy: ":")
                    if parts.count >= 2 {
                        meta.symptoms = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            
            // Check if header row contains Holter columns
            if (lower.contains("channel_1") || lower.contains("channel_2") || lower.contains("lead_1")) && !isMultiChannel {
                let headers = lower.components(separatedBy: ",")
                for (cIdx, h) in headers.enumerated() {
                    let hTrim = h.trimmingCharacters(in: .whitespaces)
                    if hTrim.contains("channel_1") || hTrim.contains("lead_1") || hTrim == "lead1" { colLead1 = cIdx }
                    if hTrim.contains("channel_2") || hTrim.contains("lead_2") || hTrim == "lead2" { colLead2 = cIdx }
                    if hTrim.contains("channel_3") || hTrim.contains("lead_3") || hTrim == "lead3" { colLead3 = cIdx }
                    if hTrim.contains("time") { colTime = cIdx }
                }
                if colLead1 >= 0 {
                    isMultiChannel = true
                    meta.lead = "Holter 3 Canali"
                    meta.device = "Holter / Multi-Derivazione"
                }
                continue
            }
            
            if line.hasPrefix("#") { continue }
            
            let trimmed = line.replacingOccurrences(of: "\"", with: "")
            let cells = trimmed.components(separatedBy: ",")
            
            if isMultiChannel {
                if cells.count > max(colLead1, max(colLead2, colLead3)) {
                    if colLead1 >= 0, let v1 = Double(cells[colLead1].trimmingCharacters(in: .whitespaces)) {
                        samples1.append(v1 / 1000.0) // uV to mV
                    }
                    if colLead2 >= 0, let v2 = Double(cells[colLead2].trimmingCharacters(in: .whitespaces)) {
                        samples2.append(v2 / 1000.0)
                    }
                    if colLead3 >= 0, let v3 = Double(cells[colLead3].trimmingCharacters(in: .whitespaces)) {
                        samples3.append(v3 / 1000.0)
                    }
                }
            } else {
                // Apple Watch single lead format
                if cells.count == 2, let _ = Int(cells[0]), let _ = Int(cells[1]) {
                    if let val = Double("\(cells[0]).\(cells[1])") {
                        samples1.append(val / 1000.0)
                        continue
                    }
                }
                if let firstCell = cells.first {
                    let candidate = firstCell.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
                    if let val = Double(candidate) {
                        samples1.append(val / 1000.0)
                    }
                }
            }
        }
        
        var avgSamples: [Double] = []
        if isMultiChannel && !samples1.isEmpty && !samples2.isEmpty && !samples3.isEmpty {
            let count = min(samples1.count, min(samples2.count, samples3.count))
            avgSamples = (0..<count).map { (samples1[$0] + samples2[$0] + samples3[$0]) / 3.0 }
        } else {
            avgSamples = samples1
        }
        
        let multi = MultiLeadData(
            hasMultipleLeads: isMultiChannel,
            lead1: samples1,
            lead2: samples2.isEmpty ? samples1 : samples2,
            lead3: samples3.isEmpty ? samples1 : samples3,
            average: avgSamples
        )
        
        return (meta, multi, fs)
    }
}

// MARK: - Mathematical & Signal Processing Engine

public final class ECGProcessor {

    // MARK: - Zero-Phase Digital Filtering (filtfilt)

    private static func lfilter(b: [Double], a: [Double], x: [Double]) -> [Double] {
        guard !x.isEmpty else { return [] }
        let n = x.count
        var y = [Double](repeating: 0.0, count: n)
        let a0 = a[0] != 0.0 ? a[0] : 1.0
        let normB = b.map { $0 / a0 }
        let normA = a.map { $0 / a0 }
        let order = max(normB.count, normA.count)
        var z = [Double](repeating: 0.0, count: order)

        for i in 0..<n {
            let xi = x[i]
            let yi = normB[0] * xi + z[0]
            y[i] = yi
            for j in 1..<order {
                let bj = j < normB.count ? normB[j] : 0.0
                let aj = j < normA.count ? normA[j] : 0.0
                let nextZ = j < (order - 1) ? z[j] : 0.0
                z[j - 1] = nextZ + bj * xi - aj * yi
            }
        }
        return y
    }

    public static func filtfilt(b: [Double], a: [Double], x: [Double]) -> [Double] {
        guard x.count > (max(b.count, a.count) * 3) else { return x }
        let forward = lfilter(b: b, a: a, x: x)
        let reversed = Array(forward.reversed())
        let backward = lfilter(b: b, a: a, x: reversed)
        return Array(backward.reversed())
    }

    public static func removeBaselineWander(signal: [Double], fs: Double) -> [Double] {
        let fc = 0.5
        let w = tan(.pi * fc / fs)
        let k = 1.0 + sqrt(2.0) * w + w * w
        let b = [1.0 / k, -2.0 / k, 1.0 / k]
        let a = [1.0, (2.0 * (w * w - 1.0)) / k, (1.0 - sqrt(2.0) * w + w * w) / k]
        return filtfilt(b: b, a: a, x: signal)
    }

    public static func smoothSignal(signal: [Double], fs: Double) -> [Double] {
        let fc = 35.0
        let w = tan(.pi * fc / fs)
        let k = 1.0 + sqrt(2.0) * w + w * w
        let b = [(w * w) / k, (2.0 * w * w) / k, (w * w) / k]
        let a = [1.0, (2.0 * (w * w - 1.0)) / k, (1.0 - sqrt(2.0) * w + w * w) / k]
        return filtfilt(b: b, a: a, x: signal)
    }

    public static func bandpassFilter(signal: [Double], fs: Double) -> [Double] {
        let fL = 5.0, fH = 15.0
        let wL = tan(.pi * fL / fs), wH = tan(.pi * fH / fs)
        let bw = wH - wL, w02 = wL * wH
        let d = 1.0 + sqrt(2.0) * bw + w02
        let b = [bw / d, 0.0, -bw / d]
        let a = [1.0, (2.0 * (w02 - 1.0)) / d, (1.0 - sqrt(2.0) * bw + w02) / d]
        return filtfilt(b: b, a: a, x: signal)
    }

    // MARK: - Pan-Tompkins R-Wave Detection & Integrated Energy Window

    public static func detectRPeaksAndWindow(signal: [Double], fs: Double) -> (rPeaks: [Int], windowSignal: [Double], threshold: Double) {
        let n = signal.count
        guard n > Int(fs * 2.0) else { return ([], [], 0.0) }

        let bp = bandpassFilter(signal: signal, fs: fs)

        // Derivative & Squaring
        var deriv = [Double](repeating: 0.0, count: n)
        for i in 1..<(n - 1) {
            deriv[i] = (bp[i + 1] - bp[i - 1]) * 0.5
        }
        let squared = deriv.map { $0 * $0 }

        // Moving window integration (~120 ms)
        let winSize = max(5, Int(0.12 * fs))
        var integrated = [Double](repeating: 0.0, count: n)
        var sum = 0.0
        for i in 0..<n {
            sum += squared[i]
            if i >= winSize { sum -= squared[i - winSize] }
            integrated[i] = sum / Double(winSize)
        }

        let maxVal = integrated.max() ?? 1.0
        let threshold = maxVal * 0.22
        let refractory = Int(0.22 * fs)

        var candidatePeaks: [Int] = []
        var lastPeak = -refractory

        for i in 1..<(n - 1) {
            if integrated[i] > threshold && integrated[i] > integrated[i - 1] && integrated[i] >= integrated[i + 1] {
                if (i - lastPeak) > refractory {
                    candidatePeaks.append(i)
                    lastPeak = i
                }
            }
        }

        // Snap to true R extremum on signal
        let half = Int(0.05 * fs)
        var refined: [Int] = []
        for p in candidatePeaks {
            let lo = max(0, p - half)
            let hi = min(n - 1, p + half)
            var bestIdx = p
            var bestAbs = 0.0
            for j in lo...hi {
                let a = abs(signal[j])
                if a > bestAbs {
                    bestAbs = a
                    bestIdx = j
                }
            }
            if refined.isEmpty || (bestIdx - refined.last!) > refractory {
                refined.append(bestIdx)
            }
        }

        // Recover missed beats
        if refined.count >= 4 {
            var rrs = [Double]()
            for k in 0..<(refined.count - 1) {
                rrs.append(Double(refined[k + 1] - refined[k]))
            }
            rrs.sort()
            let medRR = rrs[rrs.count / 2]
            var recovered: [Int] = []
            for k in 0..<(refined.count - 1) {
                recovered.append(refined[k])
                let gap = refined[k + 1] - refined[k]
                if Double(gap) > (1.65 * medRR) {
                    let searchStart = refined[k] + Int(0.35 * medRR)
                    let searchEnd = refined[k + 1] - Int(0.35 * medRR)
                    if searchEnd > searchStart {
                        var subMax = 0.0
                        var subIdx = -1
                        for s in searchStart...searchEnd {
                            if integrated[s] > subMax {
                                subMax = integrated[s]
                                subIdx = s
                            }
                        }
                        if subIdx > 0 && subMax > (threshold * 0.45) {
                            let sLo = max(0, subIdx - half)
                            let sHi = min(n - 1, subIdx + half)
                            var snapIdx = subIdx
                            var snapAbs = 0.0
                            for j in sLo...sHi {
                                if abs(signal[j]) > snapAbs {
                                    snapAbs = abs(signal[j])
                                    snapIdx = j
                                }
                            }
                            recovered.append(snapIdx)
                        }
                    }
                }
            }
            recovered.append(refined.last!)
            refined = recovered.sorted()
        }

        return (refined, integrated, threshold)
    }

    // MARK: - Phasor Transform & P-Wave / PR Analysis

    public static func detectPWavesAndPhasor(signal: [Double], rPeaks: [Int], fs: Double) -> PhasorAnalysisData {
        guard !signal.isEmpty && !rPeaks.isEmpty else {
            return PhasorAnalysisData(signal: signal, phasor: [], pPeaks: [], prIntervalsMs: [], meanPRMs: 0.0, prStatus: "N/D")
        }
        let rv = 0.001
        let phasor = signal.map { atan2($0, rv) }
        let maxPhasor = phasor.max() ?? 1.0
        let threshold = maxPhasor * 0.35

        var pPeaks: [Int] = []
        let refractory = Int(0.15 * fs)
        var lastP = -refractory

        for i in 1..<(phasor.count - 1) {
            if phasor[i] > threshold && phasor[i] > phasor[i - 1] && phasor[i] >= phasor[i + 1] {
                if (i - lastP) > refractory {
                    let isNearR = rPeaks.contains { abs($0 - i) < Int(0.06 * fs) }
                    if !isNearR {
                        pPeaks.append(i)
                        lastP = i
                    }
                }
            }
        }

        // PR Intervals: find P-wave preceding each R peak (within 100-350 ms)
        var prIntervals: [Double] = []
        let minPRSamples = Int(0.08 * fs)
        let maxPRSamples = Int(0.38 * fs)

        for r in rPeaks {
            let candidates = pPeaks.filter { $0 < r && (r - $0) >= minPRSamples && (r - $0) <= maxPRSamples }
            if let bestP = candidates.max() {
                let prMs = (Double(r - bestP) / fs) * 1000.0
                prIntervals.append(prMs)
            }
        }

        let meanPR = prIntervals.isEmpty ? 0.0 : (prIntervals.reduce(0.0, +) / Double(prIntervals.count))
        var prStatus = "Normale"
        if meanPR <= 0 {
            prStatus = "Non valutabile"
        } else if meanPR < 120.0 {
            prStatus = "Accorciato (< 120 ms, pre-eccitazione)"
        } else if meanPR <= 200.0 {
            prStatus = "Normale (120 - 200 ms)"
        } else {
            prStatus = "Allungato (> 200 ms, BAV I grado)"
        }

        return PhasorAnalysisData(
            signal: signal,
            phasor: phasor,
            pPeaks: pPeaks,
            prIntervalsMs: prIntervals,
            meanPRMs: meanPR,
            prStatus: prStatus
        )
    }

    // MARK: - HRV, Lorenz & Tachogram

    public static func calculateHRVAndLorenz(rrMs: [Double], beatTimesSec: [Double]) -> (hrv: HRVMetrics, tachogram: TachogramData) {
        guard rrMs.count > 1 else {
            return (
                HRVMetrics(meanRR: 0, sdnn: 0, rmssd: 0, pnn50: 0),
                TachogramData(beatTimesSec: [], rrIntervalsMs: [], instantBpm: [])
            )
        }

        let mean = rrMs.reduce(0.0, +) / Double(rrMs.count)
        let variance = rrMs.map { pow($0 - mean, 2) }.reduce(0.0, +) / Double(rrMs.count)
        let sdnn = sqrt(variance)

        var diffSqSum = 0.0
        var count50 = 0
        for i in 0..<(rrMs.count - 1) {
            let diff = abs(rrMs[i + 1] - rrMs[i])
            diffSqSum += diff * diff
            if diff > 50.0 { count50 += 1 }
        }
        let rmssd = sqrt(diffSqSum / Double(rrMs.count - 1))
        let pnn50 = (Double(count50) / Double(rrMs.count - 1)) * 100.0

        // Poincaré / Lorenz SD1 and SD2
        let rr_n = Array(rrMs.dropLast())
        let rr_n1 = Array(rrMs.dropFirst())
        let rho = pearsonCorrelation(rr_n, rr_n1)

        let diffArr = (0..<rr_n.count).map { rr_n1[$0] - rr_n[$0] }
        let diffMean = diffArr.reduce(0.0, +) / Double(diffArr.count)
        let varDiff = diffArr.map { pow($0 - diffMean, 2) }.reduce(0.0, +) / Double(diffArr.count)
        let sd1 = sqrt(varDiff * 0.5)

        let sumArr = (0..<rr_n.count).map { rr_n1[$0] + rr_n[$0] }
        let sumMean = sumArr.reduce(0.0, +) / Double(sumArr.count)
        let varSum = sumArr.map { pow($0 - sumMean, 2) }.reduce(0.0, +) / Double(sumArr.count)
        let sd2 = sqrt(varSum * 0.5)
        let ratio = sd2 > 0 ? (sd1 / sd2) : 0.0

        let instantBpm = rrMs.map { $0 > 0 ? (60000.0 / $0) : 0.0 }
        let hrv = HRVMetrics(
            meanRR: mean,
            sdnn: sdnn,
            rmssd: rmssd,
            pnn50: pnn50,
            sd1: sd1,
            sd2: sd2,
            sd1Sd2Ratio: ratio,
            correlationRho: rho
        )
        let tachogram = TachogramData(
            beatTimesSec: beatTimesSec,
            rrIntervalsMs: rrMs,
            instantBpm: instantBpm
        )

        return (hrv, tachogram)
    }

    // MARK: - QTc Formulas

    public static func calculateQTc(qtMs: Double, rrMs: Double, hrBpm: Double) -> (bazett: Double, fridericia: Double, framingham: Double, hodges: Double) {
        guard qtMs > 0, rrMs > 0 else { return (0, 0, 0, 0) }
        let rrSec = rrMs / 1000.0
        let hr = hrBpm > 0 ? hrBpm : (60.0 / rrSec)
        let bazett = qtMs / sqrt(rrSec)
        let fridericia = qtMs / cbrt(rrSec)
        let framingham = qtMs + 154.0 * (1.0 - rrSec)
        let hodges = qtMs + 1.75 * (hr - 60.0)
        return (bazett, fridericia, framingham, hodges)
    }

    // MARK: - AHA/ACCF Tangent Method Median Beat QT/QTc

    public static func analyzeQT(signal: [Double], rPeaks: [Int], fs: Double) -> (summary: QTAnalysisSummary?, medianBeat: MedianBeatData?, beats: [QTBeatResult]) {
        guard rPeaks.count >= 4 else { return (nil, nil, []) }

        let preMs = 200.0, postMs = 500.0
        let preSamples = Int((preMs / 1000.0) * fs)
        let postSamples = Int((postMs / 1000.0) * fs)
        let beatLen = preSamples + postSamples

        var beatWaves: [[Double]] = []
        var validRIndices: [Int] = []
        var validRRMs: [Double] = []

        for i in 1..<rPeaks.count {
            let r = rPeaks[i]
            let start = r - preSamples
            let end = r + postSamples
            if start >= 0 && end <= signal.count {
                let slice = Array(signal[start..<end])
                beatWaves.append(slice)
                validRIndices.append(r)
                let rr = (Double(r - rPeaks[i - 1]) / fs) * 1000.0
                validRRMs.append(rr)
            }
        }

        guard beatWaves.count >= 3 else { return (nil, nil, []) }

        // Ensemble Median Beat
        var medianWave = [Double](repeating: 0.0, count: beatLen)
        for s in 0..<beatLen {
            var col = [Double]()
            for b in 0..<beatWaves.count {
                col.append(beatWaves[b][s])
            }
            col.sort()
            medianWave[s] = col[col.count / 2]
        }

        let timeRelMs = (0..<beatLen).map { (Double($0 - preSamples) / fs) * 1000.0 }
        let medRRMs = validRRMs.reduce(0.0, +) / Double(validRRMs.count)

        // Delineate Median Beat
        guard let medDel = delineateSingleBeat(wave: medianWave, rIdx: preSamples, fs: fs, rrMs: medRRMs) else {
            return (nil, nil, [])
        }

        let hrBpm = medRRMs > 0 ? (60000.0 / medRRMs) : 0.0
        let (baz, frid, fram, hodg) = calculateQTc(qtMs: medDel.qtMs, rrMs: medRRMs, hrBpm: hrBpm)

        let medianBeat = MedianBeatData(
            wave: medianWave,
            timeRelMs: timeRelMs,
            rIndex: preSamples,
            qOnIndex: medDel.qOnIdx,
            tPeakIndex: medDel.tPeakIdx,
            tEndIndex: medDel.tEndIdx,
            kSlopeIndex: medDel.kSlopeIdx,
            mSlope: medDel.mSlope,
            vSlope: medDel.vSlope,
            vIso: medDel.vIso,
            qtMs: medDel.qtMs,
            qrsMs: medDel.qrsMs,
            rrMs: medRRMs,
            qtcBazett: baz,
            qtcFridericia: frid,
            qtcFramingham: fram,
            qtcHodges: hodg
        )

        // Delineate individual beats
        var beatResults: [QTBeatResult] = []
        var individualQTs: [Double] = []

        for b in 0..<beatWaves.count {
            let r = validRIndices[b]
            let rr = validRRMs[b]
            if let d = delineateSingleBeat(wave: beatWaves[b], rIdx: preSamples, fs: fs, rrMs: rr) {
                let (bBaz, bFrid, _, _) = calculateQTc(qtMs: d.qtMs, rrMs: rr, hrBpm: 60000.0 / rr)
                let res = QTBeatResult(
                    beatNumber: b + 1,
                    rTimeSec: Double(r) / fs,
                    rIndex: r,
                    qOnIndex: r - preSamples + d.qOnIdx,
                    tPeakIndex: r - preSamples + d.tPeakIdx,
                    tEndIndex: r - preSamples + d.tEndIdx,
                    rrMs: rr,
                    qtMs: d.qtMs,
                    qtcBazett: bBaz,
                    qtcFridericia: bFrid
                )
                beatResults.append(res)
                individualQTs.append(d.qtMs)
            }
        }

        // Reliability check via IQR
        individualQTs.sort()
        var iqr = 0.0
        var medianQtVal = medDel.qtMs
        if individualQTs.count >= 4 {
            let q1 = individualQTs[individualQTs.count / 4]
            let q3 = individualQTs[(3 * individualQTs.count) / 4]
            iqr = q3 - q1
            medianQtVal = individualQTs[individualQTs.count / 2]
        }
        let isReliable = iqr < 30.0

        let summary = QTAnalysisSummary(
            qtMs: medDel.qtMs,
            qtcBazett: baz,
            qtcFridericia: frid,
            qtcFramingham: fram,
            qtcHodges: hodg,
            rrMs: medRRMs,
            hrBpm: hrBpm,
            qrsMs: medDel.qrsMs,
            isReliable: isReliable,
            beatsAnalyzed: beatResults.count,
            beatsTotal: rPeaks.count - 1,
            beatQtMedian: medianQtVal,
            beatQtIqr: iqr
        )

        return (summary, medianBeat, beatResults)
    }

    private struct SingleBeatDelineation {
        let qOnIdx: Int
        let tPeakIdx: Int
        let tEndIdx: Int
        let kSlopeIdx: Int
        let mSlope: Double
        let vSlope: Double
        let vIso: Double
        let qtMs: Double
        let qrsMs: Double
    }

    private static func delineateSingleBeat(wave: [Double], rIdx: Int, fs: Double, rrMs: Double) -> SingleBeatDelineation? {
        let n = wave.count
        guard rIdx > 20 && (rIdx + 40) < n else { return nil }

        // Isoelectric baseline (median of pre-QRS -120 to -60 ms)
        let isoStart = max(0, rIdx - Int(0.12 * fs))
        let isoEnd = max(isoStart + 2, rIdx - Int(0.06 * fs))
        var isoSlice = Array(wave[isoStart..<isoEnd])
        isoSlice.sort()
        let vIso = isoSlice[isoSlice.count / 2]

        // Q-onset (backward from R to find baseline return)
        let qSearchStart = max(0, rIdx - Int(0.10 * fs))
        var qOnIdx = max(0, rIdx - Int(0.04 * fs))
        for j in stride(from: rIdx - 2, through: qSearchStart, by: -1) {
            if abs(wave[j] - vIso) < 0.035 {
                qOnIdx = j
                break
            }
        }

        // T-peak search window (120 ms to min(460 ms, 0.65 * RR))
        let tStart = rIdx + Int(0.12 * fs)
        let maxLimit = min(Double(n - 1), Double(rIdx) + (min(460.0, rrMs * 0.65) / 1000.0) * fs)
        let tEndSearch = max(tStart + 5, Int(maxLimit))
        guard tStart < tEndSearch && tEndSearch <= n else { return nil }

        var tPeakIdx = tStart
        var maxDev = 0.0
        for j in tStart..<tEndSearch {
            let dev = abs(wave[j] - vIso)
            if dev > maxDev {
                maxDev = dev
                tPeakIdx = j
            }
        }

        // Tangent Method: Steepest downslope after T-peak
        let slopeEnd = min(n - 2, tPeakIdx + Int(0.18 * fs))
        guard slopeEnd > (tPeakIdx + 1) else { return nil }

        var kSlopeIdx = tPeakIdx + 1
        var minSlope = 0.0 // steepest descent is most negative
        let tSign = (wave[tPeakIdx] - vIso) >= 0 ? 1.0 : -1.0

        for j in (tPeakIdx + 1)..<slopeEnd {
            let slope = (wave[j + 1] - wave[j - 1]) * 0.5 * tSign
            if slope < minSlope {
                minSlope = slope
                kSlopeIdx = j
            }
        }

        let mSlope = (wave[kSlopeIdx + 1] - wave[kSlopeIdx - 1]) * 0.5
        let vSlope = wave[kSlopeIdx]

        // Tangent intersection with baseline: vIso = vSlope + mSlope * (tEnd - kSlope)
        var tEndIdx: Int
        if abs(mSlope) > 1e-5 {
            let dSamples = (vIso - vSlope) / mSlope
            tEndIdx = kSlopeIdx + Int(round(dSamples))
        } else {
            tEndIdx = kSlopeIdx + Int(0.04 * fs)
        }

        // Clamp tEnd to reasonable bounds
        let minTEnd = tPeakIdx + Int(0.02 * fs)
        let maxTEnd = min(n - 1, tPeakIdx + Int(0.24 * fs))
        tEndIdx = max(minTEnd, min(maxTEnd, tEndIdx))

        let qtMs = (Double(tEndIdx - qOnIdx) / fs) * 1000.0
        let qrsMs = (Double(rIdx - qOnIdx) * 2.0 / fs) * 1000.0

        guard qtMs >= 200.0 && qtMs <= 700.0 else { return nil }

        return SingleBeatDelineation(
            qOnIdx: qOnIdx,
            tPeakIdx: tPeakIdx,
            tEndIdx: tEndIdx,
            kSlopeIdx: kSlopeIdx,
            mSlope: mSlope,
            vSlope: vSlope,
            vIso: vIso,
            qtMs: qtMs,
            qrsMs: qrsMs
        )
    }

    private static func pearsonCorrelation(_ x: [Double], _ y: [Double]) -> Double {
        guard x.count == y.count && x.count > 1 else { return 0.0 }
        let n = Double(x.count)
        let meanX = x.reduce(0.0, +) / n
        let meanY = y.reduce(0.0, +) / n
        var num = 0.0, denX = 0.0, denY = 0.0
        for i in 0..<x.count {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            num += dx * dy
            denX += dx * dx
            denY += dy * dy
        }
        let den = sqrt(denX * denY)
        return den > 0 ? (num / den) : 0.0
    }

    // MARK: - Time-Frequency Spectrogram (STFT 0-50 Hz)

    public static func calculateSpectrogram(signal: [Double], fs: Double) -> SpectrogramData {
        let winSize = 128
        let hopSize = 32
        guard signal.count >= winSize else {
            return SpectrogramData(timeBins: [], freqBins: [], matrix: [], minDb: -60, maxDb: 0)
        }

        // Hann window
        var hann = [Double](repeating: 0.0, count: winSize)
        for i in 0..<winSize {
            hann[i] = 0.5 * (1.0 - cos(2.0 * .pi * Double(i) / Double(winSize - 1)))
        }

        // Target frequencies up to 50 Hz
        let maxK = min(winSize / 2, Int(ceil(50.0 * Double(winSize) / fs)))
        var freqBins = [Double]()
        for k in 0...maxK {
            freqBins.append((Double(k) * fs) / Double(winSize))
        }

        let numFrames = (signal.count - winSize) / hopSize
        var timeBins = [Double]()
        var matrix = [[Double]](repeating: [Double](repeating: 0.0, count: numFrames), count: maxK + 1)

        var globalMin = 1e9
        var globalMax = -1e9

        for f in 0..<numFrames {
            let start = f * hopSize
            timeBins.append(Double(start + winSize / 2) / fs)

            // Direct DFT for bins 0...maxK
            for k in 0...maxK {
                var re = 0.0, im = 0.0
                let angleStep = 2.0 * .pi * Double(k) / Double(winSize)
                for n in 0..<winSize {
                    let val = signal[start + n] * hann[n]
                    let angle = angleStep * Double(n)
                    re += val * cos(angle)
                    im -= val * sin(angle)
                }
                let power = re * re + im * im
                let db = 10.0 * log10(power + 1e-7)
                matrix[k][f] = db
                if db < globalMin { globalMin = db }
                if db > globalMax { globalMax = db }
            }
        }

        return SpectrogramData(
            timeBins: timeBins,
            freqBins: freqBins,
            matrix: matrix,
            minDb: globalMin,
            maxDb: globalMax
        )
    }

    // MARK: - 3D Vectorcardiography / Attractor Engine

    public static func calculateVCG(multiLead: MultiLeadData, singleLead: [Double], phasor: [Double], fs: Double) -> VCGData {
        var points: [VCGPoint3D] = []

        if multiLead.hasMultipleLeads && multiLead.lead1.count > 200 {
            // True 3-lead Vectorcardiography loop: (Lead 1, Lead 2, Lead 3)
            let count = min(multiLead.lead1.count, min(multiLead.lead2.count, multiLead.lead3.count))
            let strideStep = max(1, count / 800) // ~800 points for silky smooth rendering
            for i in stride(from: 0, to: count, by: strideStep) {
                points.append(VCGPoint3D(x: multiLead.lead1[i], y: multiLead.lead2[i], z: multiLead.lead3[i]))
            }
            return VCGData(points: points, isMultiChannel: true)
        } else {
            // Single lead delay-coordinate embedding: (x(t), x(t - tau), phasor(t))
            let tau = max(2, Int(0.025 * fs)) // 25 ms delay
            let count = singleLead.count
            guard count > (tau * 2) else { return VCGData(points: [], isMultiChannel: false) }
            let strideStep = max(1, (count - tau) / 800)
            for i in stride(from: tau, to: count - tau, by: strideStep) {
                let x = singleLead[i]
                let y = singleLead[i - tau]
                let z = (i < phasor.count ? (phasor[i] / 5.0) : (singleLead[i + tau]))
                points.append(VCGPoint3D(x: x, y: y, z: z))
            }
            return VCGData(points: points, isMultiChannel: false)
        }
    }

    // MARK: - Master Pipeline Execution

    public static func analyze(
        multiLead: MultiLeadData,
        metadata: ECGMetadata,
        fs: Double,
        selectedLead: LeadSelection = .lead1,
        userNotes: String = ""
    ) -> ECGAnalysisReport {
        // Pick signal according to selected lead
        let rawSignal: [Double]
        switch selectedLead {
        case .lead1:
            rawSignal = multiLead.lead1
        case .lead2:
            rawSignal = multiLead.lead2
        case .lead3:
            rawSignal = multiLead.lead3
        case .average:
            rawSignal = multiLead.average
        }

        // Filtering
        let baselineFree = removeBaselineWander(signal: rawSignal, fs: fs)
        let smoothed = smoothSignal(signal: baselineFree, fs: fs)

        // R peaks and Pan-Tompkins window
        let (rPeaks, windowSignal, threshold) = detectRPeaksAndWindow(signal: smoothed, fs: fs)

        // P-waves & Phasor
        let phasorData = detectPWavesAndPhasor(signal: smoothed, rPeaks: rPeaks, fs: fs)

        // RR intervals & Tachogram
        var rrMs: [Double] = []
        var beatTimes: [Double] = []
        if rPeaks.count > 1 {
            for i in 0..<(rPeaks.count - 1) {
                let diffSamples = rPeaks[i + 1] - rPeaks[i]
                rrMs.append((Double(diffSamples) / fs) * 1000.0)
                beatTimes.append(Double(rPeaks[i + 1]) / fs)
            }
        }

        let (hrv, tachogram) = calculateHRVAndLorenz(rrMs: rrMs, beatTimesSec: beatTimes)

        let duration = Double(rawSignal.count) / fs
        let bpm = duration > 0 ? (Double(rPeaks.count) / duration) * 60.0 : 0.0

        // QT analysis
        let (summary, medBeat, beats) = analyzeQT(signal: smoothed, rPeaks: rPeaks, fs: fs)

        // Spectrogram
        let spectrogram = calculateSpectrogram(signal: smoothed, fs: fs)

        // 3D VCG
        let vcg = calculateVCG(multiLead: multiLead, singleLead: smoothed, phasor: phasorData.phasor, fs: fs)

        let panTompkins = PanTompkinsAnalysisData(
            windowSignal: windowSignal,
            rPeaks: rPeaks,
            threshold: threshold
        )

        return ECGAnalysisReport(
            metadata: metadata,
            fs: fs,
            durationSec: duration,
            selectedLead: selectedLead,
            multiLead: multiLead,
            rawSignal: rawSignal,
            filteredSignal: smoothed,
            rPeakIndices: rPeaks,
            bpm: bpm,
            hrv: hrv,
            tachogram: tachogram,
            phasorData: phasorData,
            panTompkinsData: panTompkins,
            spectrogramData: spectrogram,
            vcgData: vcg,
            qtSummary: summary,
            medianBeat: medBeat,
            beats: beats,
            userNotes: userNotes
        )
    }
}
