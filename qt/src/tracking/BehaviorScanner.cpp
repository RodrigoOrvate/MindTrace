#include "BehaviorScanner.h"

#include <QDebug>

BehaviorScanner::BehaviorScanner(int fps) : _fps(fps)
{
    _currentFeatures.resize(FEATURE_COUNT, 0.0f);
}

void BehaviorScanner::reset()
{
    _movementsSumHist.clear();
    _noseProbHist.clear();
    _bodyProbHist.clear();
    _prevNose   = PosePoint{};
    _prevBody   = PosePoint{};
    _frameCount = 0;
    std::fill(_currentFeatures.begin(), _currentFeatures.end(), 0.0f);
}

void BehaviorScanner::clearHistory()
{
    _frameHistory.clear();
    _frameHistory.shrink_to_fit();
}

float BehaviorScanner::getMean(const std::deque<float>& history, size_t window) const
{
    const size_t elementCount = std::min(history.size(), window);
    if (elementCount == 0) return 0.0f;
    float total = 0.0f;
    auto  it    = history.rbegin();
    for (size_t i = 0; i < elementCount; ++i, ++it)
        total += *it;
    return total / static_cast<float>(elementCount);
}

float BehaviorScanner::getSum(const std::deque<float>& history, size_t window) const
{
    const size_t elementCount = std::min(history.size(), window);
    if (elementCount == 0) return 0.0f;
    float total = 0.0f;
    auto  it    = history.rbegin();
    for (size_t i = 0; i < elementCount; ++i, ++it)
        total += *it;
    return total;
}

float BehaviorScanner::getLowProbFraction(float threshold, size_t window) const
{
    const size_t noseCount   = std::min(_noseProbHist.size(), window);
    const size_t bodyCount   = std::min(_bodyProbHist.size(), window);
    const size_t sharedCount = std::min(noseCount, bodyCount);
    if (sharedCount == 0) return 0.0f;

    int  lowProbCount = 0;
    auto noseIt       = _noseProbHist.rbegin();
    auto bodyIt       = _bodyProbHist.rbegin();
    for (size_t i = 0; i < sharedCount; ++i, ++noseIt, ++bodyIt) {
        if (*noseIt < threshold) ++lowProbCount;
        if (*bodyIt < threshold) ++lowProbCount;
    }
    return static_cast<float>(lowProbCount);
}

void BehaviorScanner::setZones(const std::vector<Zone>& zones)
{
    _zones = zones;
}

void BehaviorScanner::setFloorPolygon(const std::vector<std::pair<float, float>>& poly)
{
    _floorPoly = poly;
}

// Ray-casting — mirrors QML isPointInPoly exactly.
bool BehaviorScanner::isInsideFloor(float normX, float normY) const
{
    if (_floorPoly.size() < 3) return false;
    bool      inside      = false;
    const int vertexCount = static_cast<int>(_floorPoly.size());
    for (int i = 0, j = vertexCount - 1; i < vertexCount; j = i++) {
        const float curX  = _floorPoly[i].first;
        const float curY  = _floorPoly[i].second;
        const float prevX = _floorPoly[j].first;
        const float prevY = _floorPoly[j].second;
        if (((curY > normY) != (prevY > normY)) &&
            (normX < (prevX - curX) * (normY - curY) / (prevY - curY) + curX))
            inside = !inside;
    }
    return inside;
}

void BehaviorScanner::setCropSize(int width, int height)
{
    _cropW = width;
    _cropH = height;
}

void BehaviorScanner::setVelocity(float velocity)
{
    _velocity = velocity;
}

bool BehaviorScanner::isNearObject(float cropX, float cropY) const
{
    if (_zones.empty()) return false;
    for (const auto& zone : _zones) {
        const float zoneCenterX = zone.x * static_cast<float>(_cropW);
        const float zoneCenterY = zone.y * static_cast<float>(_cropH);
        const float zoneRadius  = zone.r * static_cast<float>(_cropW);
        const float deltaX      = cropX - zoneCenterX;
        const float deltaY      = cropY - zoneCenterY;
        const float distance    = std::sqrt(deltaX * deltaX + deltaY * deltaY);
        if (distance < zoneRadius * 1.5f)
            return true;
    }
    return false;
}

bool BehaviorScanner::pushFrame(const PosePoint& nose, const PosePoint& body)
{
    constexpr float SCALE_X = TRAINING_W / CROP_W;
    constexpr float SCALE_Y = TRAINING_H / CROP_H;

    float movNose = 0.0f;
    if (_prevNose.p > 0.0f && nose.p > 0.0f) {
        const float deltaX = (nose.x - _prevNose.x) * SCALE_X;
        const float deltaY = (nose.y - _prevNose.y) * SCALE_Y;
        movNose = std::sqrt(deltaX * deltaX + deltaY * deltaY);
    }

    float movBody = 0.0f;
    if (_prevBody.p > 0.0f && body.p > 0.0f) {
        const float deltaX = (body.x - _prevBody.x) * SCALE_X;
        const float deltaY = (body.y - _prevBody.y) * SCALE_Y;
        movBody = std::sqrt(deltaX * deltaX + deltaY * deltaY);
    }

    _prevNose = nose;
    _prevBody = body;

    const float movSum = movNose + movBody;

    constexpr size_t MAX_WINDOW = 450;  // up to 15 s at 30 fps
    if (_movementsSumHist.size() >= MAX_WINDOW) _movementsSumHist.pop_front();

    const size_t probWindow = static_cast<size_t>(_fps);
    if (_noseProbHist.size() >= probWindow) _noseProbHist.pop_front();
    if (_bodyProbHist.size() >= probWindow) _bodyProbHist.pop_front();

    _movementsSumHist.push_back(movSum / 2.0f);
    _noseProbHist.push_back(nose.p);
    _bodyProbHist.push_back(body.p);

    // ── 21 feature extraction ─────────────────────────────────────────────────
    _currentFeatures[0] = movNose;
    _currentFeatures[1] = movBody;
    _currentFeatures[2] = movSum;
    _currentFeatures[3] = movSum / 2.0f;
    _currentFeatures[4] = std::min(movNose, movBody);
    _currentFeatures[5] = std::max(movNose, movBody);

    const size_t window2s  = 2 * static_cast<size_t>(_fps);
    _currentFeatures[6]    = getMean(_movementsSumHist, window2s);
    _currentFeatures[7]    = getSum (_movementsSumHist, window2s);

    const size_t window5s  = 5 * static_cast<size_t>(_fps);
    _currentFeatures[8]    = getMean(_movementsSumHist, window5s);
    _currentFeatures[9]    = getSum (_movementsSumHist, window5s);

    const size_t window6s  = 6 * static_cast<size_t>(_fps);
    _currentFeatures[10]   = getMean(_movementsSumHist, window6s);
    _currentFeatures[11]   = getSum (_movementsSumHist, window6s);

    const size_t window7s  = static_cast<size_t>(7.5f * static_cast<float>(_fps));
    _currentFeatures[12]   = getMean(_movementsSumHist, window7s);
    _currentFeatures[13]   = getSum (_movementsSumHist, window7s);

    const size_t window15s = 15 * static_cast<size_t>(_fps);
    _currentFeatures[14]   = getMean(_movementsSumHist, window15s);
    _currentFeatures[15]   = getSum (_movementsSumHist, window15s);

    _currentFeatures[16] = nose.p + body.p;
    _currentFeatures[17] = (nose.p + body.p) / 2.0f;

    _currentFeatures[18] = getLowProbFraction(0.1f,  probWindow);
    _currentFeatures[19] = getLowProbFraction(0.5f,  probWindow);
    _currentFeatures[20] = getLowProbFraction(0.75f, probWindow);

    // ── Record frame for B-SOiD post-session analysis ─────────────────────────
    if (nose.p > 0.0f || body.p > 0.0f) {
        FrameRecord rec;
        rec.frameIdx  = _frameCount;
        rec.ruleLabel = classifySimple();
        for (size_t i = 0; i < FEATURE_COUNT; ++i)
            rec.features[i] = _currentFeatures[i];
        _frameHistory.push_back(std::move(rec));
    }
    ++_frameCount;

    return (nose.p > 0.0f && body.p > 0.0f);
}

std::vector<float> BehaviorScanner::getFeatures() const
{
    return _currentFeatures;
}

int BehaviorScanner::classifySimple() const
{
    const float movNose    = _currentFeatures[0];
    const float movBody    = _currentFeatures[1];
    const float roll2sMean = _currentFeatures[6];

    const float noseX        = _prevNose.x;
    const float noseY        = _prevNose.y;
    const float bodyX        = _prevBody.x;
    const float bodyY        = _prevBody.y;
    const bool  hasValidNose = (_prevNose.p > 0.1f);
    const bool  hasValidPose = (hasValidNose && _prevBody.p > 0.1f);
    const bool  hasZones     = !_zones.empty();

    // Priority 1: Sniffing — nose inside an object zone (overrides velocity).
    if (hasZones && hasValidNose && isNearObject(noseX, noseY))
        return BEHAVIOR_SNIFFING;

    // Priority 2: Rearing — nose outside floor polygon, body still inside.
    if (hasValidPose && _floorPoly.size() >= 3) {
        const float normNoseX = noseX / static_cast<float>(_cropW);
        const float normNoseY = noseY / static_cast<float>(_cropH);
        const float normBodyX = bodyX / static_cast<float>(_cropW);
        const float normBodyY = bodyY / static_cast<float>(_cropH);
        if (!isInsideFloor(normNoseX, normNoseY) && isInsideFloor(normBodyX, normBodyY))
            return BEHAVIOR_REARING;
    }

    // Priority 3: Resting — body velocity below threshold.
    if (_velocity < 0.05f)
        return BEHAVIOR_RESTING;

    // Priority 4: Grooming — body nearly still, nose highly active.
    if (movBody < 1.5f && movNose > 5.0f)
        return BEHAVIOR_GROOMING;

    // Priority 5: Walking — body in motion.
    if (movBody > 2.0f || roll2sMean > 3.0f)
        return BEHAVIOR_WALKING;

    return BEHAVIOR_RESTING;
}
