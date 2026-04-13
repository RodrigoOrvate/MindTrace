#pragma once
#include <vector>
#include <deque>
#include <cmath>
#include <numeric>
#include <algorithm>
#include <array>

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

// ── Registro por frame para análise B-SOiD pós-sessão ─────────────────────
// Armazena as 21 features e o label da regra nativa para cada frame processado.
// Gravado em CSV ao final da sessão para input do BSoidAnalyzer.
struct FrameRecord {
    int   frameIdx = 0;
    std::array<float, 21> features = {};
    int   ruleLabel = 0;          // resultado de classifySimple()
};

class BehaviorScanner {
public:
    BehaviorScanner(int fps = 30);
    ~BehaviorScanner() = default;

    bool pushFrame(const PosePoint& nose, const PosePoint& body);
    std::vector<float> getFeatures() const;
    void reset();

    void setZones(const std::vector<Zone>& zones);
    void setFloorPolygon(const std::vector<std::pair<float,float>>& poly); // {x,y} norm 0-1
    void setCropSize(int w, int h);
    void setVelocity(float velocity);  // m/s do corpo para classifySimple

    // ── Histórico B-SOiD ──────────────────────────────────────────────────
    void clearHistory();
    const std::vector<FrameRecord>& frameHistory() const { return _frameHistory; }

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
    int _frameCount = 0;          // contador de frames para FrameRecord::frameIdx

    std::deque<float> _movementsSumHist;
    std::deque<float> _noseProbHist;
    std::deque<float> _bodyProbHist;

    std::vector<float>       _currentFeatures;
    std::vector<Zone>        _zones;
    std::vector<std::pair<float,float>> _floorPoly; // polígono do chão em coords norm 0-1
    std::vector<FrameRecord> _frameHistory;          // buffer B-SOiD (cresce por sessão)

    PosePoint _prevNose;
    PosePoint _prevBody;
    float _velocity = 0.0f;  // m/s (velocidade do corpo)

    float getMean(const std::deque<float>& d, size_t window) const;
    float getSum(const std::deque<float>& d, size_t window) const;
    float getLowProbFraction(float threshold, size_t window) const;
    bool isNearObject(float x, float y) const;
    bool isInsideFloor(float normX, float normY) const; // ray-cast no polígono do chão
};
