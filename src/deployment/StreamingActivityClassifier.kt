package com.example.bandana.ml

import java.util.ArrayDeque
import kotlin.math.exp

/**
 * Production-Ready Real-Time Streaming Activity Classifier for Android.
 *
 * Implements:
 * 1. 100-sample double-buffered FIFO window buffer (2.5s @ 40 Hz).
 * 2. Stride execution: triggers inference every 25 incoming samples (625 ms / ~1.6 Hz).
 * 3. Temporal Hysteresis Filter: 3-window rolling majority vote to prevent state flickering.
 * 4. Pluggable ONNX Runtime / TFLite native execution interface.
 */
data class ClassificationResult(
    val activity: String,
    val classIndex: Int,
    val confidence: Float,
    val rawActivity: String,
    val rawConfidence: Float,
    val timestampMs: Long = System.currentTimeMillis()
)

interface ModelInferenceRunner {
    /**
     * Executes neural inference on aligned 100-sample window.
     * @param wristData FloatArray of shape [1, 6, 100] in flattened row-major format
     * @param ankleData FloatArray of shape [1, 6, 100] in flattened row-major format
     * @return FloatArray of raw class logits
     */
    fun runInference(wristData: FloatArray, ankleData: FloatArray): FloatArray
}

class TemporalHysteresisDebouncer(
    private val historySize: Int = 3,
    private val minConfidenceThreshold: Float = 0.40f
) {
    private val history = ArrayDeque<Pair<Int, Float>>(historySize)
    private var currentStableState: Int? = null

    fun update(rawClass: Int, confidence: Float): Pair<Int, Float> {
        if (history.size >= historySize) {
            history.removeFirst()
        }
        history.addLast(Pair(rawClass, confidence))

        if (history.size < 2) {
            currentStableState = rawClass
            return Pair(rawClass, confidence)
        }

        // Weighted voting in recent history
        val votes = mutableMapOf<Int, Float>()
        history.forEachIndexed { index, (cls, conf) ->
            val recencyWeight = 1.0f + (index.toFloat() / history.size) * 0.5f
            votes[cls] = (votes[cls] ?: 0f) + (conf * recencyWeight)
        }

        val bestCandidate = votes.maxByOrNull { it.value }?.key ?: rawClass

        // Hysteresis transition requirement
        val stable = currentStableState
        if (stable != null && bestCandidate != stable) {
            val countForCandidate = history.count { it.first == bestCandidate }
            val majorityThreshold = (historySize / 2) + 1
            if (countForCandidate >= majorityThreshold) {
                currentStableState = bestCandidate
            }
        } else {
            currentStableState = bestCandidate
        }

        val activeState = currentStableState ?: rawClass
        val matchingConfs = history.filter { it.first == activeState }.map { it.second }
        val avgConf = if (matchingConfs.isNotEmpty()) matchingConfs.average().toFloat() else confidence

        return Pair(activeState, avgConf)
    }

    fun reset() {
        history.clear()
        currentStableState = null
    }
}

class StreamingActivityClassifier(
    private val classLabels: List<String>,
    private val inferenceRunner: ModelInferenceRunner,
    val windowSize: Int = 100,
    val strideSamples: Int = 25
) {
    // Channel-separated buffers: each holds [windowSize] samples of 6 floats
    private val wristBuffer = ArrayDeque<FloatArray>(windowSize)
    private val ankleBuffer = ArrayDeque<FloatArray>(windowSize)
    private var newSamplesCount = 0

    private val debouncer = TemporalHysteresisDebouncer(historySize = 3)

    /**
     * Feed incoming synchronized 6-axis wrist and ankle IMU samples.
     * @param wristSample 6 floats: [ax, ay, az, gx, gy, gz]
     * @param ankleSample 6 floats: [ax, ay, az, gx, gy, gz]
     * @return ClassificationResult when 25 new samples are received, or null if accumulating.
     */
    @Synchronized
    fun onSampleReceived(
        wristSample: FloatArray,
        ankleSample: FloatArray
    ): ClassificationResult? {
        require(wristSample.size == 6) { "Wrist sample must contain 6 axes" }
        require(ankleSample.size == 6) { "Ankle sample must contain 6 axes" }

        if (wristBuffer.size >= windowSize) wristBuffer.removeFirst()
        if (ankleBuffer.size >= windowSize) ankleBuffer.removeFirst()

        wristBuffer.addLast(wristSample.copyOf())
        ankleBuffer.addLast(ankleSample.copyOf())
        newSamplesCount++

        if (wristBuffer.size == windowSize && ankleBuffer.size == windowSize && newSamplesCount >= strideSamples) {
            newSamplesCount = 0
            return executeInference()
        }

        return null
    }

    private fun executeInference(): ClassificationResult {
        // Flatten into channels-first layout [1, 6, 100]
        val flatWrist = FloatArray(6 * windowSize)
        val flatAnkle = FloatArray(6 * windowSize)

        val wristSnapshot = wristBuffer.toList()
        val ankleSnapshot = ankleBuffer.toList()

        for (ch in 0 until 6) {
            for (t in 0 until windowSize) {
                flatWrist[ch * windowSize + t] = wristSnapshot[t][ch]
                flatAnkle[ch * windowSize + t] = ankleSnapshot[t][ch]
            }
        }

        // Run neural inference
        val logits = inferenceRunner.runInference(flatWrist, flatAnkle)
        val probs = softmax(logits)

        var rawClass = 0
        var maxProb = probs[0]
        for (i in 1 until probs.size) {
            if (probs[i] > maxProb) {
                maxProb = probs[i]
                rawClass = i
            }
        }

        // Apply debouncing filter
        val (stableClass, stableConf) = debouncer.update(rawClass, maxProb)

        val stableLabel = if (stableClass in classLabels.indices) classLabels[stableClass] else "Unknown"
        val rawLabel = if (rawClass in classLabels.indices) classLabels[rawClass] else "Unknown"

        return ClassificationResult(
            activity = stableLabel,
            classIndex = stableClass,
            confidence = stableConf,
            rawActivity = rawLabel,
            rawConfidence = maxProb
        )
    }

    private fun softmax(logits: FloatArray): FloatArray {
        var maxLogit = Float.NEGATIVE_INFINITY
        for (v in logits) if (v > maxLogit) maxLogit = v

        val exps = FloatArray(logits.size)
        var sum = 0.0f
        for (i in logits.indices) {
            exps[i] = exp(logits[i] - maxLogit)
            sum += exps[i]
        }
        for (i in exps.indices) {
            exps[i] /= (sum + 1e-9f)
        }
        return exps
    }

    fun reset() {
        wristBuffer.clear()
        ankleBuffer.clear()
        newSamplesCount = 0
        debouncer.reset()
    }
}
