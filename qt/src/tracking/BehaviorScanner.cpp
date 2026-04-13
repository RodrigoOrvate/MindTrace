#include "BehaviorScanner.h"
#include <QDebug>

BehaviorScanner::BehaviorScanner(int fps) : _fps(fps) {
    _currentFeatures.resize(FEATURE_COUNT, 0.0f);
}

void BehaviorScanner::reset() {
    _movementsSumHist.clear();
    _noseProbHist.clear();
    _bodyProbHist.clear();
    _prevNose = PosePoint{};
    _prevBody = PosePoint{};
    std::fill(_currentFeatures.begin(), _currentFeatures.end(), 0.0f);
}

float BehaviorScanner::getMean(const std::deque<float>& d, size_t window) const {
    size_t n = std::min(d.size(), window);
    if (n == 0) return 0.0f;
    float sum = 0.0f;
    auto it = d.rbegin();
    for (size_t i = 0; i < n; ++i, ++it) {
        sum += *it;
    }
    return sum / static_cast<float>(n);
}

float BehaviorScanner::getSum(const std::deque<float>& d, size_t window) const {
    size_t n = std::min(d.size(), window);
    if (n == 0) return 0.0f;
    float sum = 0.0f;
    auto it = d.rbegin();
    for (size_t i = 0; i < n; ++i, ++it) {
        sum += *it;
    }
    return sum;
}

float BehaviorScanner::getLowProbFraction(float threshold, size_t window) const {
    size_t nNose = std::min(_noseProbHist.size(), window);
    size_t nBody = std::min(_bodyProbHist.size(), window);
    size_t n = std::min(nNose, nBody);

    if (n == 0) return 0.0f;
    int count = 0;
    auto itN = _noseProbHist.rbegin();
    auto itB = _bodyProbHist.rbegin();
    for (size_t i = 0; i < n; ++i, ++itN, ++itB) {
        if (*itN < threshold) count++;
        if (*itB < threshold) count++;
    }
    return static_cast<float>(count);
}

void BehaviorScanner::setZones(const std::vector<Zone>& zones) {
    _zones = zones;
}

void BehaviorScanner::setCropSize(int w, int h) {
    _cropW = w;
    _cropH = h;
}

void BehaviorScanner::setVelocity(float velocity) {
    _velocity = velocity;
}

bool BehaviorScanner::isNearObject(float x, float y) const {
    if (_zones.empty()) return false;
    
    for (const auto& z : _zones) {
        float zoneCenterX = z.x * static_cast<float>(_cropW);
        float zoneCenterY = z.y * static_cast<float>(_cropH);
        float zoneRadius = z.r * static_cast<float>(_cropW);
        
        float dx = x - zoneCenterX;
        float dy = y - zoneCenterY;
        float dist = std::sqrt(dx*dx + dy*dy);
        
        if (dist < zoneRadius * 1.5f) {
            return true;
        }
    }
    return false;
}

bool BehaviorScanner::pushFrame(const PosePoint& nose, const PosePoint& body) {
    // Scale coordinates to training space
    constexpr float SX = TRAINING_W / CROP_W;
    constexpr float SY = TRAINING_H / CROP_H;

    float movNose = 0.0f;
    if (_prevNose.p > 0.0f && nose.p > 0.0f) {
        float dx = (nose.x - _prevNose.x) * SX;
        float dy = (nose.y - _prevNose.y) * SY;
        movNose = std::sqrt(dx*dx + dy*dy);
    }

    float movBody = 0.0f;
    if (_prevBody.p > 0.0f && body.p > 0.0f) {
        float dx = (body.x - _prevBody.x) * SX;
        float dy = (body.y - _prevBody.y) * SY;
        movBody = std::sqrt(dx*dx + dy*dy);
    }

    _prevNose = nose;
    _prevBody = body;

    float movSum = movNose + movBody;

    constexpr size_t MAX_WINDOW = 450; // up to 15s at 30fps
    if (_movementsSumHist.size() >= MAX_WINDOW) _movementsSumHist.pop_front();
    
    size_t probWindow = static_cast<size_t>(_fps);
    if (_noseProbHist.size() >= probWindow) _noseProbHist.pop_front();
    if (_bodyProbHist.size() >= probWindow) _bodyProbHist.pop_front();

    _movementsSumHist.push_back(movSum / 2.0f);
    _noseProbHist.push_back(nose.p);
    _bodyProbHist.push_back(body.p);

    // Compute 21 features
    _currentFeatures[0] = movNose;
    _currentFeatures[1] = movBody;
    _currentFeatures[2] = movSum;
    _currentFeatures[3] = movSum / 2.0f;
    _currentFeatures[4] = std::min(movNose, movBody);
    _currentFeatures[5] = std::max(movNose, movBody);

    size_t w2 = 2 * _fps;
    _currentFeatures[6] = getMean(_movementsSumHist, w2);
    _currentFeatures[7] = getSum(_movementsSumHist, w2);

    size_t w5 = 5 * _fps;
    _currentFeatures[8] = getMean(_movementsSumHist, w5);
    _currentFeatures[9] = getSum(_movementsSumHist, w5);

    size_t w6 = 6 * _fps;
    _currentFeatures[10] = getMean(_movementsSumHist, w6);
    _currentFeatures[11] = getSum(_movementsSumHist, w6);

    size_t w7_5 = static_cast<size_t>(7.5f * _fps);
    _currentFeatures[12] = getMean(_movementsSumHist, w7_5);
    _currentFeatures[13] = getSum(_movementsSumHist, w7_5);

    size_t w15 = 15 * _fps;
    _currentFeatures[14] = getMean(_movementsSumHist, w15);
    _currentFeatures[15] = getSum(_movementsSumHist, w15);

    _currentFeatures[16] = nose.p + body.p;
    _currentFeatures[17] = (nose.p + body.p) / 2.0f;

    _currentFeatures[18] = getLowProbFraction(0.1f, probWindow);
    _currentFeatures[19] = getLowProbFraction(0.5f, probWindow);
    _currentFeatures[20] = getLowProbFraction(0.75f, probWindow);

    return (nose.p > 0.0f && body.p > 0.0f);
}

std::vector<float> BehaviorScanner::getFeatures() const {
    return _currentFeatures;
}

int BehaviorScanner::classifySimple() const {
    const float movNose = _currentFeatures[0];
    const float movBody = _currentFeatures[1];
    const float roll2sMean = _currentFeatures[6];

    const float noseY = _prevNose.y;
    const float bodyX = _prevBody.x;
    const float bodyY = _prevBody.y;
    const bool hasZones = !_zones.empty();

    // ── Regra de velocidade: resting se muito lento ─────────────────────────────
    // Se velocidade < 0.05 m/s → resting (mesmo que em pé)
    if (_velocity < 0.05f) {
        return BEHAVIOR_RESTING;
    }

    // ── Rearing: focinho muito alto (passando do chão para a parede) ───────────
    // O focinho muito acima do corpo indica que o rato está em pé
    // threshold de 30px de diferença = focinho bem acima do corpo
    const bool isUpright = (noseY < bodyY - 30.0f);
    const bool nearEdges = (bodyX < 20 || bodyX > 340 || bodyY < 15 || bodyY > 225);
    
    // Rearing:rato em pé (focinho bem acima do corpo) E nas bordas (parede)
    if (isUpright && nearEdges) {
        return BEHAVIOR_REARING;
    }

    // ── Sniffing: only when zones exist AND nose near object ─────────────────────
    // Regra reforçada: se o focinho está na área do objeto, é sniffing
    if (hasZones) {
        const float noseX = _prevNose.x;
        if (isNearObject(noseX, noseY)) {
            return BEHAVIOR_SNIFFING;
        }
    }

    // ── Resting: body stopped ─────────────────────────────────────────────────
    if (movBody < 0.3f) {
        return BEHAVIOR_RESTING;
    }

    // ── Walking: body moving significantly ─────────────────────────────────────
    if (movBody > 3.0f || roll2sMean > 5.0f) {
        return BEHAVIOR_WALKING;
    }

    // ── Grooming: nose very active while body mostly still ───────────────────
    if (movBody < 2.0f && movNose > 4.0f) {
        return BEHAVIOR_GROOMING;
    }

    // Default: resting
    return BEHAVIOR_RESTING;
}
