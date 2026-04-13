#pragma once
#include <vector>
#include <deque>
#include <cmath>
#include <numeric>
#include <algorithm>

struct PosePoint {
    float x = -1.0f;
    float y = -1.0f;
    float p = 0.0f;
};

struct Zone {
    float x = 0.0f;      // center X (0-1 normalized)
    float y = 0.0f;      // center Y (0-1 normalized)
    float r = 0.0f;      // radius as fraction of arena size
};

class BehaviorScanner {
public:
    BehaviorScanner(int fps = 30);
    ~BehaviorScanner() = default;

    bool pushFrame(const PosePoint& nose, const PosePoint& body);
    std::vector<float> getFeatures() const;
    void reset();

    void setZones(const std::vector<Zone>& zones);
    void setCropSize(int w, int h);
    void setVelocity(float velocity);  // m/s do corpo para classifySimple

    static constexpr size_t FEATURE_COUNT = 21;

    static constexpr float TRAINING_W = 330.0f;
    static constexpr float TRAINING_H = 240.0f;
    static constexpr float CROP_W     = 360.0f;
    static constexpr float CROP_H     = 240.0f;

    static constexpr int BEHAVIOR_WALKING  = 0;
    static constexpr int BEHAVIOR_SNIFFING = 1;
    static constexpr int BEHAVIOR_GROOMING = 2;
    static constexpr int BEHAVIOR_RESTING  = 3;
    static constexpr int BEHAVIOR_REARING  = 4;

    int classifySimple() const;

private:
    int _fps;
    int _cropW = 360;
    int _cropH = 240;
    
    std::deque<float> _movementsSumHist;
    std::deque<float> _noseProbHist;
    std::deque<float> _bodyProbHist;

    std::vector<float> _currentFeatures;
    std::vector<Zone> _zones;

    PosePoint _prevNose;
    PosePoint _prevBody;
    float _velocity = 0.0f;  // m/s (velocidade do corpo)

    float getMean(const std::deque<float>& d, size_t window) const;
    float getSum(const std::deque<float>& d, size_t window) const;
    float getLowProbFraction(float threshold, size_t window) const;
    bool isNearObject(float x, float y) const;
};
