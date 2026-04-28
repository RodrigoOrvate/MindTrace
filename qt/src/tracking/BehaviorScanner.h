#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <deque>
#include <numeric>
#include <vector>

/// A 2D keypoint detected by the pose model with a likelihood score.
struct PosePoint {
    float x = -1.0f;  ///< Pixel X in crop space (360-wide). Negative default = undetected.
    float y = -1.0f;  ///< Pixel Y in crop space (240-high).
    float p = 0.0f;   ///< Likelihood score [0, 1].
};

/// A circular object zone in normalised [0, 1] arena coordinates.
struct Zone {
    float x = 0.0f;  ///< Centre X (0=left, 1=right).
    float y = 0.0f;  ///< Centre Y (0=top, 1=bottom).
    float r = 0.0f;  ///< Radius as a fraction of arena width.
};

/// Per-frame snapshot stored for post-session B-SOiD analysis.
struct FrameRecord {
    int frameIdx = 0;
    std::array<float, 21> features = {};
    int ruleLabel = 0;  ///< Result of BehaviorScanner::classifySimple().
};

/// Extracts movement features from successive pose keypoints and classifies
/// the current behaviour using a priority-ordered rule chain.
class BehaviorScanner {
public:
    explicit BehaviorScanner(int fps = 30);
    ~BehaviorScanner() = default;

    /// Process one frame. Returns true when both nose and body have valid likelihoods.
    bool pushFrame(const PosePoint& nose, const PosePoint& body);

    /// Current 21-element feature vector. Valid after the first pushFrame() call.
    std::vector<float> getFeatures() const;

    /// Reset rolling history and frame counters. Does NOT clear B-SOiD history.
    void reset();

    /// Override the zone list used for sniffing detection.
    void setZones(const std::vector<Zone>& zones);

    /// Override the floor polygon (normalised 0–1) used for rearing detection.
    void setFloorPolygon(const std::vector<std::pair<float, float>>& poly);

    void setCropSize(int width, int height);

    /// Receive the current body velocity in m/s from the QML layer.
    void setVelocity(float velocity);

    // ── B-SOiD history ────────────────────────────────────────────────────────
    void clearHistory();
    const std::vector<FrameRecord>& frameHistory() const { return _frameHistory; }

    // Scale factors: crop space (360×240 output) → training space (330×240).
    static constexpr size_t FEATURE_COUNT = 21;
    static constexpr float  TRAINING_W    = 330.0f;
    static constexpr float  TRAINING_H    = 240.0f;
    static constexpr float  CROP_W        = 360.0f;
    static constexpr float  CROP_H        = 240.0f;

    static constexpr int BEHAVIOR_WALKING  = 0;
    static constexpr int BEHAVIOR_SNIFFING = 1;
    static constexpr int BEHAVIOR_GROOMING = 2;
    static constexpr int BEHAVIOR_RESTING  = 3;
    static constexpr int BEHAVIOR_REARING  = 4;

    /// Rule-based classifier. Call after pushFrame().
    int classifySimple() const;

private:
    int _fps;
    int _cropW      = 360;
    int _cropH      = 240;
    int _frameCount = 0;

    std::deque<float> _movementsSumHist;
    std::deque<float> _noseProbHist;
    std::deque<float> _bodyProbHist;

    std::vector<float>                   _currentFeatures;
    std::vector<Zone>                    _zones;
    std::vector<std::pair<float, float>> _floorPoly;
    std::vector<FrameRecord>             _frameHistory;

    PosePoint _prevNose;
    PosePoint _prevBody;
    float     _velocity = 0.0f;

    /// Rolling mean of the last *window* entries in *history*.
    float getMean(const std::deque<float>& history, size_t window) const;

    /// Rolling sum of the last *window* entries in *history*.
    float getSum(const std::deque<float>& history, size_t window) const;

    /// Count of keypoints whose likelihood fell below *threshold* in the last *window* frames.
    float getLowProbFraction(float threshold, size_t window) const;

    /// True when the given crop-space point is within 1.5× of any configured zone radius.
    bool isNearObject(float cropX, float cropY) const;

    /// Ray-casting point-in-polygon test mirroring the QML isPointInPoly helper.
    bool isInsideFloor(float normX, float normY) const;
};
