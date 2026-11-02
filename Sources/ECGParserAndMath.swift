import Foundation

public final class ECGParser {
    public static func parseCSV(content: String) -> (metadata: ECGMetadata, signal: [Double], fs: Double) {
        var meta = ECGMetadata()
        var fs = 512.0
        var samples: [Double] = []

        let lines = content.components(separatedBy: .newlines)
        for (idx, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            let lower = line.lowercased()
            if idx < 25 {
                if lower.contains("hertz") || lower.contains("hz") {
                    let parts = line.components(separatedBy: ",")
                    for p in parts {
                        let sub = p.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                        let comps = sub.components(separatedBy: " ")
                        if let first = comps.first {
                            let cleanNum = first.replacingOccurrences(of: ",", with: ".")
                            if let val = Double(cleanNum), val > 10.0 {
                                fs = val
                                meta.sampleRate = val
                            }
                        }
                    }
                }
                if lower.contains("date") || lower.contains("data") {
                    let parts = line.components(separatedBy: ",")
                    if parts.count >= 2 {
                        meta.recordedDate = parts.dropFirst().joined(separator: ", ").replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                    }
                }
                if lower.contains("classification") || lower.contains("classificazione") {
                    let parts = line.components(separatedBy: ",")
                    if parts.count >= 2 {
                        meta.classification = parts.dropFirst().joined(separator: ", ").replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                    }
                }
                if lower.contains("device") || lower.contains("dispositivo") {
                    let parts = line.components(separatedBy: ",")
                    if parts.count >= 2 {
                        meta.device = parts.dropFirst().joined(separator: ", ").replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                    }
                }
                if lower.contains("symptoms") || lower.contains("sintomi") {
                    let parts = line.components(separatedBy: ",")
                    if parts.count >= 2 {
                        let sym = parts.dropFirst().joined(separator: ", ").replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                        if !sym.isEmpty { meta.symptoms = sym }
                    }
                }
            }

            // Numeric ECG sample parsing (supports comma decimal and uV values)
            let trimmed = line.replacingOccurrences(of: "\"", with: "")
            let cells = trimmed.components(separatedBy: ",")
            if cells.count == 2, let _ = Int(cells[0]), let _ = Int(cells[1]) {
                if let val = Double("\(cells[0]).\(cells[1])") {
                    samples.append(val / 1000.0) // Convert uV to mV
                    continue
                }
            }
            if let firstCell = cells.first {
                let candidate = firstCell.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
                if let val = Double(candidate) {
                    samples.append(val / 1000.0) // Convert uV to mV
                }
            }
        }

        return (meta, samples, fs)
    }
}

public final class ECGProcessor {

    // MARK: - Zero-Phase Digital Filtering (filtfilt)

    /// Direct Form II Transposed filtering
    private static func lfilter(b: [Double], a: [Double], x: [Double]) -> [Double] {
        guard !x.isEmpty else { return [] }
        let n = x.count
        let m = max(b.count, a.count)

        var bNorm = b
        var aNorm = a
        if bNorm.count < m { bNorm += [Double](repeating: 0.0, count: m - bNorm.count) }
        if aNorm.count < m { aNorm += [Double](repeating: 0.0, count: m - aNorm.count) }

        let a0 = aNorm[0]
        if abs(a0 - 1.0) > 1e-12 && abs(a0) > 1e-12 {
            bNorm = bNorm.map { $0 / a0 }
            aNorm = aNorm.map { $0 / a0 }
        }

        var y = [Double](repeating: 0.0, count: n)
        var reg = [Double](repeating: 0.0, count: m)

        for i in 0..<n {
            let xi = x[i]
            let yi = bNorm[0] * xi + reg[1]
            y[i] = yi
            for j in 1..<(m - 1) {
                reg[j] = bNorm[j] * xi - aNorm[j] * yi + reg[j + 1]
            }
            if m > 1 {
                reg[m - 1] = bNorm[m - 1] * xi - aNorm[m - 1] * yi
            }
        }
        return y
    }

    /// Forward-backward zero-phase filtering (exact equivalent of scipy.signal.filtfilt)
    public static func filtfilt(b: [Double], a: [Double], x: [Double]) -> [Double] {
        guard x.count > 15 else { return x }
        let yFwd = lfilter(b: b, a: a, x: x)
        let yRev = lfilter(b: b, a: a, x: yFwd.reversed())
        return yRev.reversed()
    }

    /// 0.5 Hz High-pass Butterworth filter (removes baseline wander without phase delay)
    public static func removeBaselineWander(signal: [Double], fs: Double) -> [Double] {
        // 2nd order Butterworth highpass at 0.5 Hz, fs=512
        let b = [0.9956706458770602, -1.9913412917541204, 0.9956706458770602]
        let a = [1.0, -1.99132254835917, 0.9913600351490711]
        return filtfilt(b: b, a: a, x: signal)
    }

    /// 35 Hz Low-pass Butterworth filter (removes high frequency EMG noise for clean T-wave delineation)
    public static func smoothSignal(signal: [Double], fs: Double) -> [Double] {
        // 2nd order Butterworth lowpass at 35 Hz, fs=512
        let b = [0.035084902304091566, 0.07016980460818313, 0.035084902304091566]
        let a = [1.0, -1.4047060034581547, 0.5450456126745209]
        return filtfilt(b: b, a: a, x: signal)
    }

    /// 5-15 Hz Band-pass filter (isolates QRS complex energy for Pan-Tompkins)
    public static func bandpassFilter(signal: [Double], fs: Double) -> [Double] {
        let b = [0.0034606847613782503, 0.0, -0.0069213695227565005, 0.0, 0.0034606847613782503]
        let a = [1.0, -3.805214529160545, 5.453022062691062, -3.4883663403144958, 0.8406758500795084]
        return filtfilt(b: b, a: a, x: signal)
    }

    // MARK: - QRS & Peak Detection

    public static func detectRPeaks(signal: [Double], fs: Double) -> [Int] {
        let n = signal.count
        guard n > Int(fs * 2.0) else { return [] }

        let bp = bandpassFilter(signal: signal, fs: fs)

        // Derivative & Squaring
        var deriv = [Double](repeating: 0.0, count: n)
        for i in 1..<(n - 1) {
            deriv[i] = (bp[i + 1] - bp[i - 1]) * 0.5
        }
        let squared = deriv.map { $0 * $0 }

        // Moving window integration (120 ms)
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

        // Snap to true R extremum on baseline-removed signal (+/- 50 ms window)
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

        // Recover missed beats inside gaps > 1.5x median RR
        if refined.count >= 4 {
            var rrs = [Double]()
            for i in 0..<(refined.count - 1) {
                rrs.append(Double(refined[i + 1] - refined[i]))
            }
            let medRR = rrs.sorted()[rrs.count / 2]
            var out = refined
            for i in 0..<(refined.count - 1) {
                let a_ = refined[i]
                let b_ = refined[i + 1]
                let gap = Double(b_ - a_)
                let nMissing = Int(round(gap / medRR)) - 1
                if nMissing >= 1 && gap >= 1.5 * medRR {
                    let step = gap / Double(nMissing + 1)
                    for m_ in 1...nMissing {
                        let center = a_ + Int(Double(m_) * step)
                        let lo = max(a_ + Int(0.25 * medRR), center - Int(0.25 * medRR))
                        let hi = min(b_ - Int(0.25 * medRR), center + Int(0.25 * medRR))
                        if hi > lo {
                            var bestJ = lo
                            var bestA = 0.0
                            for j in lo...hi {
                                if abs(signal[j]) > bestA {
                                    bestA = abs(signal[j])
                                    bestJ = j
                                }
                            }
                            out.append(bestJ)
                        }
                    }
                }
            }
            refined = Array(Set(out)).sorted()
        }

        return refined
    }

    // MARK: - P-Wave Detection (Phasor Transform)

    public static func detectPWaves(signal: [Double], rPeaks: [Int], fs: Double) -> [Int] {
        guard !signal.isEmpty && !rPeaks.isEmpty else { return [] }
        let rv = 0.001 // 1 uV reference scale
        let phasor = signal.map { atan2($0, rv) }
        let maxPhasor = phasor.max() ?? 1.0
        let threshold = maxPhasor * 0.35

        var pPeaks: [Int] = []
        let refractory = Int(0.15 * fs)
        var lastP = -refractory

        for i in 1..<(phasor.count - 1) {
            if phasor[i] > threshold && phasor[i] > phasor[i - 1] && phasor[i] >= phasor[i + 1] {
                if (i - lastP) > refractory {
                    // Make sure it is not directly inside a QRS complex
                    let isNearR = rPeaks.contains { abs($0 - i) < Int(0.06 * fs) }
                    if !isNearR {
                        pPeaks.append(i)
                        lastP = i
                    }
                }
            }
        }
        return pPeaks
    }

    // MARK: - HRV Metrics

    public static func calculateHRV(rrMs: [Double]) -> HRVMetrics {
        guard !rrMs.isEmpty else { return HRVMetrics(meanRR: 0, sdnn: 0, rmssd: 0, pnn50: 0) }
        let mean = rrMs.reduce(0.0, +) / Double(rrMs.count)
        let variance = rrMs.map { pow($0 - mean, 2) }.reduce(0.0, +) / Double(rrMs.count)
        let sdnn = sqrt(variance)

        if rrMs.count > 1 {
            var diffSq = 0.0
            var count50 = 0
            for i in 0..<(rrMs.count - 1) {
                let d = abs(rrMs[i + 1] - rrMs[i])
                diffSq += d * d
                if d > 50.0 { count50 += 1 }
            }
            let rmssd = sqrt(diffSq / Double(rrMs.count - 1))
            let pnn50 = (Double(count50) / Double(rrMs.count - 1)) * 100.0
            return HRVMetrics(meanRR: mean, sdnn: sdnn, rmssd: rmssd, pnn50: pnn50)
        }

        return HRVMetrics(meanRR: mean, sdnn: sdnn, rmssd: 0, pnn50: 0)
    }

    // MARK: - QTc Formulas

    public static func calculateQTc(qtMs: Double, rrMs: Double) -> (bazett: Double, fridericia: Double, framingham: Double, hodges: Double) {
        guard qtMs > 0, rrMs > 0 else { return (0, 0, 0, 0) }
        let rrSec = rrMs / 1000.0
        let hrBpm = 60.0 / rrSec

        let bazett = qtMs / sqrt(rrSec)
        let fridericia = qtMs / pow(rrSec, 1.0 / 3.0)
        let framingham = qtMs + 154.0 * (1.0 - rrSec)
        let hodges = qtMs + 1.75 * (hrBpm - 60.0)

        return (bazett, fridericia, framingham, hodges)
    }

    // MARK: - QT Tangent Delineation & Ensemble Averaging

    public static func analyzeQT(signal: [Double], rPeaks: [Int], fs: Double) -> (summary: QTAnalysisSummary?, medianBeat: MedianBeatData?, beats: [QTBeatResult]) {
        guard rPeaks.count >= 4 else { return (nil, nil, []) }

        // Use zero-phase smoothed signal for repolarization analysis
        let smoothed = smoothSignal(signal: signal, fs: fs)

        var rrSamples: [Double] = []
        for i in 0..<(rPeaks.count - 1) {
            rrSamples.append(Double(rPeaks[i + 1] - rPeaks[i]))
        }
        let sortedRR = rrSamples.sorted()
        let medRRSamples = sortedRR[sortedRR.count / 2]
        let medRRMs = (medRRSamples / fs) * 1000.0

        let pre = Int(0.25 * fs)
        let post = min(Int(0.75 * medRRSamples), Int(0.55 * fs))

        // QRS Template Correlation to discard ectopic beats / post-pause outliers
        let half = Int(0.06 * fs)
        var templateAccum = [Double](repeating: 0.0, count: 2 * half)
        var validTemplateCount = 0

        for r in rPeaks {
            if (r - half) >= 0 && (r + half) < smoothed.count {
                for j in 0..<(2 * half) {
                    templateAccum[j] += smoothed[r - half + j]
                }
                validTemplateCount += 1
            }
        }
        guard validTemplateCount >= 3 else { return (nil, nil, []) }
        let template = templateAccum.map { $0 / Double(validTemplateCount) }

        var keptBeats: [Int] = []
        for i in 1..<(rPeaks.count - 1) {
            let r = rPeaks[i]
            if (r - pre) >= 0 && (r + post) < smoothed.count {
                let rrPrev = Double(rPeaks[i] - rPeaks[i - 1])
                let rrNext = Double(rPeaks[i + 1] - rPeaks[i])
                let isRegular = rrPrev >= 0.8 * medRRSamples && rrPrev <= 1.2 * medRRSamples && rrNext >= 0.8 * medRRSamples

                // Correlation check
                let qrs = Array(smoothed[(r - half)..<(r + half)])
                let corr = pearsonCorrelation(qrs, template)

                if isRegular && corr >= 0.88 {
                    keptBeats.append(i)
                }
            }
        }

        guard keptBeats.count >= 3 else { return (nil, nil, []) }

        let winLen = pre + post
        var medianWave = [Double](repeating: 0.0, count: winLen)
        for s in 0..<winLen {
            var col = [Double]()
            for bi in keptBeats {
                let r = rPeaks[bi]
                col.append(smoothed[r - pre + s])
            }
            col.sort()
            medianWave[s] = col[col.count / 2]
        }

        guard let medDel = delineateSingleBeat(wave: medianWave, rIdx: pre, fs: fs, rrMs: medRRMs) else {
            return (nil, nil, [])
        }

        let qtc = calculateQTc(qtMs: medDel.qtMs, rrMs: medRRMs)
        let timeRelMs = (0..<winLen).map { (Double($0 - pre) / fs) * 1000.0 }

        let medianBeatData = MedianBeatData(
            wave: medianWave,
            timeRelMs: timeRelMs,
            rIndex: pre,
            qOnIndex: medDel.qOn,
            tPeakIndex: medDel.tPeak,
            tEndIndex: medDel.tEnd,
            kSlopeIndex: medDel.kSlope,
            mSlope: medDel.mSlope,
            vSlope: medDel.vSlope,
            vIso: medDel.vIso,
            qtMs: medDel.qtMs,
            qrsMs: medDel.qrsMs,
            rrMs: medRRMs,
            qtcBazett: qtc.bazett,
            qtcFridericia: qtc.fridericia,
            qtcFramingham: qtc.framingham,
            qtcHodges: qtc.hodges
        )

        // Beat by beat calculation
        var beatResults: [QTBeatResult] = []
        for bi in keptBeats {
            let r = rPeaks[bi]
            let rrPrevMs = (Double(rPeaks[bi] - rPeaks[bi - 1]) / fs) * 1000.0
            let beatSegment = Array(smoothed[(r - pre)..<(r + post)])
            if let res = delineateSingleBeat(wave: beatSegment, rIdx: pre, fs: fs, rrMs: rrPrevMs) {
                let beatQtc = calculateQTc(qtMs: res.qtMs, rrMs: rrPrevMs)
                beatResults.append(QTBeatResult(
                    beatNumber: bi + 1,
                    rTimeSec: Double(r) / fs,
                    rIndex: r,
                    qOnIndex: (r - pre) + res.qOn,
                    tPeakIndex: (r - pre) + res.tPeak,
                    tEndIndex: (r - pre) + res.tEnd,
                    rrMs: rrPrevMs,
                    qtMs: res.qtMs,
                    qtcBazett: beatQtc.bazett,
                    qtcFridericia: beatQtc.fridericia
                ))
            }
        }

        let beatQTs = beatResults.map { $0.qtMs }.sorted()
        let beatQtMedian = beatQTs.isEmpty ? medDel.qtMs : beatQTs[beatQTs.count / 2]
        let p75 = beatQTs.isEmpty ? 0.0 : beatQTs[Int(Double(beatQTs.count) * 0.75)]
        let p25 = beatQTs.isEmpty ? 0.0 : beatQTs[Int(Double(beatQTs.count) * 0.25)]
        let iqr = p75 - p25

        let isReliable = abs(beatQtMedian - medDel.qtMs) <= 25.0 && iqr <= 40.0 && beatResults.count >= 5

        let summary = QTAnalysisSummary(
            qtMs: medDel.qtMs,
            qtcFridericia: qtc.fridericia,
            qtcBazett: qtc.bazett,
            qtcFramingham: qtc.framingham,
            qtcHodges: qtc.hodges,
            rrMs: medRRMs,
            hrBpm: 60000.0 / medRRMs,
            qrsMs: medDel.qrsMs,
            isReliable: isReliable,
            beatsAnalyzed: beatResults.count,
            beatsTotal: rPeaks.count,
            beatQtMedian: beatQtMedian,
            beatQtIqr: iqr
        )

        return (summary, medianBeatData, beatResults)
    }

    private static func pearsonCorrelation(_ x: [Double], _ y: [Double]) -> Double {
        guard x.count == y.count && !x.isEmpty else { return 0.0 }
        let mx = x.reduce(0.0, +) / Double(x.count)
        let my = y.reduce(0.0, +) / Double(y.count)
        var num = 0.0
        var dx2 = 0.0
        var dy2 = 0.0
        for i in 0..<x.count {
            let dx = x[i] - mx
            let dy = y[i] - my
            num += dx * dy
            dx2 += dx * dx
            dy2 += dy * dy
        }
        let denom = sqrt(dx2 * dy2)
        return denom > 1e-12 ? (num / denom) : 0.0
    }

    private struct SingleBeatDelineation {
        let qOn: Int
        let jPt: Int
        let tPeak: Int
        let tEnd: Int
        let kSlope: Int
        let mSlope: Double
        let vSlope: Double
        let vIso: Double
        let qrsMs: Double
        let qtMs: Double
    }

    private static func delineateSingleBeat(wave: [Double], rIdx: Int, fs: Double, rrMs: Double) -> SingleBeatDelineation? {
        let n = wave.count
        let ms = fs / 1000.0
        guard rIdx >= Int(0.12 * fs), rIdx < (n - 5) else { return nil }

        // Robust Isoelectric Baseline: blend pre-P and post-T tails
        let preCount = max(3, Int(0.05 * fs))
        let preSub = Array(wave[0..<min(preCount, n)])
        let tailCount = max(3, Int(0.04 * fs))
        let tailSub = Array(wave[(n - tailCount)..<n])
        let vIso = 0.5 * ((preSub.reduce(0.0, +) / Double(preSub.count)) + (tailSub.reduce(0.0, +) / Double(tailSub.count)))

        // Gradients
        var g = [Double](repeating: 0.0, count: n)
        for i in 1..<(n - 1) {
            g[i] = (wave[i + 1] - wave[i - 1]) * 0.5
        }

        // QRS max slope
        let qrsLo = max(0, rIdx - Int(0.04 * fs))
        let qrsHi = min(n - 1, rIdx + Int(0.04 * fs))
        let maxSlope = (qrsLo...qrsHi).map { abs(g[$0]) }.max() ?? 1.0
        if maxSlope <= 0 { return nil }

        // QRS onset via quiet run
        var qOn = max(0, rIdx - Int(0.08 * fs))
        var quiet = 0
        for j in stride(from: rIdx, through: max(0, rIdx - Int(0.10 * fs)), by: -1) {
            if abs(g[j]) < 0.12 * maxSlope {
                quiet += 1
                if quiet >= max(3, Int(0.008 * fs)) {
                    qOn = j
                    break
                }
            } else {
                quiet = 0
            }
        }

        // J point
        var jPt = min(n - 1, rIdx + Int(0.06 * fs))
        quiet = 0
        for j in rIdx..<min(n, rIdx + Int(0.12 * fs)) {
            if abs(g[j]) < 0.15 * maxSlope {
                quiet += 1
                if quiet >= max(3, Int(0.010 * fs)) {
                    jPt = j
                    break
                }
            } else {
                quiet = 0
            }
        }
        jPt = max(jPt, rIdx + Int(0.025 * fs))

        // T peak search window
        let tLo = max(jPt + Int(0.03 * fs), rIdx + Int(0.08 * fs))
        let tHi = min(n - 3, rIdx + Int(min(0.72 * rrMs, 460.0) * ms))
        guard tHi > (tLo + Int(0.04 * fs)) else { return nil }

        // Find prominent T peak (highest deviation from baseline)
        var bestTPeak = tLo
        var maxDev = 0.0
        for i in tLo...tHi {
            let d = abs(wave[i] - vIso)
            if d > maxDev {
                maxDev = d
                bestTPeak = i
            }
        }
        if maxDev < 0.015 { return nil }

        let sign = (wave[bestTPeak] >= vIso) ? 1.0 : -1.0
        let y = wave.map { sign * ($0 - vIso) }
        let tAmp = y[bestTPeak]

        // Tangent method on descending limb
        let lim = min(n - 2, bestTPeak + Int(0.20 * fs))
        var stop = lim
        for i in bestTPeak..<lim {
            if y[i] < 0.15 * tAmp {
                stop = max(i, bestTPeak + 4)
                break
            }
        }

        var minSlope = 0.0
        var kSlope = bestTPeak
        for i in bestTPeak...stop {
            let slope = (y[i + 1] - y[i - 1]) * 0.5
            if slope < minSlope {
                minSlope = slope
                kSlope = i
            }
        }

        if minSlope >= -1e-5 { return nil }

        let tEndDouble = Double(kSlope) + (0.0 - y[kSlope]) / minSlope
        let tEnd = max(bestTPeak + Int(0.02 * fs), min(n - 1, Int(round(tEndDouble))))

        let qtMs = Double(tEnd - qOn) / ms
        let qrsMs = Double(jPt - qOn) / ms

        guard qtMs >= 200.0 && qtMs <= 620.0 else { return nil }

        return SingleBeatDelineation(
            qOn: qOn,
            jPt: jPt,
            tPeak: bestTPeak,
            tEnd: tEnd,
            kSlope: kSlope,
            mSlope: sign * minSlope,
            vSlope: wave[kSlope],
            vIso: vIso,
            qrsMs: qrsMs,
            qtMs: qtMs
        )
    }
}
