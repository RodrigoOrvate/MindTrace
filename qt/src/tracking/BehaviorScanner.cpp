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
    _frameCount = 0;
    std::fill(_currentFeatures.begin(), _currentFeatures.end(), 0.0f);
}

void BehaviorScanner::clearHistory() {
    _frameHistory.clear();
    _frameHistory.shrink_to_fit();
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

void BehaviorScanner::setFloorPolygon(const std::vector<std::pair<float,float>>& poly) {
    _floorPoly = poly;
}

// Ray-casting — espelho exato do isPointInPoly do QML
bool BehaviorScanner::isInsideFloor(float nx, float ny) const {
    if (_floorPoly.size() < 3) return false;
    bool inside = false;
    int n = static_cast<int>(_floorPoly.size());
    for (int i = 0, j = n - 1; i < n; j = i++) {
        float xi = _floorPoly[i].first,  yi = _floorPoly[i].second;
        float xj = _floorPoly[j].first,  yj = _floorPoly[j].second;
        if (((yi > ny) != (yj > ny)) &&
            (nx < (xj - xi) * (ny - yi) / (yj - yi) + xi)) {
            inside = !inside;
        }
    }
    return inside;
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

    // ── Registrar frame no histórico B-SOiD ───────────────────────────────
    // Só grava se pelo menos um keypoint é válido (evita linhas de ruído puro).
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

std::vector<float> BehaviorScanner::getFeatures() const {
    return _currentFeatures;
}

int BehaviorScanner::classifySimple() const {
    const float movNose    = _currentFeatures[0];
    const float movBody    = _currentFeatures[1];
    const float roll2sMean = _currentFeatures[6];

    const float noseX = _prevNose.x;
    const float noseY = _prevNose.y;
    const float bodyX = _prevBody.x;
    const float bodyY = _prevBody.y;
    const bool hasValidNose = (_prevNose.p > 0.1f);
    const bool hasValidPose = (hasValidNose && _prevBody.p > 0.1f);
    const bool hasZones     = !_zones.empty();

    // ── Prioridade 1: Sniffing — nose na zona do objeto ────────────────────────
    // Maior prioridade: independente da velocidade, se o focinho está dentro da
    // área de um objeto → sniffing. Corrige o bug onde resting vencia sniffing.
    if (hasZones && hasValidNose && isNearObject(noseX, noseY)) {
        return BEHAVIOR_SNIFFING;
    }

    // ── Prioridade 2: Rearing — nose fora do chão, body ainda no chão ─────────
    // Usa o mesmo polígono do chão (floorPoints) que o QML usa para CA/CC.
    // Se o nose cruzou a fronteira do chão para a área colorida (parede) e o
    // body continua dentro do chão → rato está em pé → rearing.
    // Prioritário sobre velocidade: rato parado em pé = rearing, não resting.
    if (hasValidPose && _floorPoly.size() >= 3) {
        const float W = static_cast<float>(_cropW);
        const float H = static_cast<float>(_cropH);
        const float normNoseX = noseX / W;
        const float normNoseY = noseY / H;
        const float normBodyX = bodyX / W;
        const float normBodyY = bodyY / H;

        if (!isInsideFloor(normNoseX, normNoseY) && isInsideFloor(normBodyX, normBodyY)) {
            return BEHAVIOR_REARING;
        }
    }

    // ── Prioridade 3: Resting — velocidade abaixo do limiar ────────────────────
    // _velocity em m/s vinda do QML (mesmo limiar usado para coloração da UI).
    // Rato praticamente parado → resting.
    if (_velocity < 0.05f) {
        return BEHAVIOR_RESTING;
    }

    // ── Prioridade 4: Grooming — corpo parado + nose muito ativo ───────────────
    // Velocidade presente mas corpo quase imóvel enquanto o nariz se move muito.
    if (movBody < 1.5f && movNose > 5.0f) {
        return BEHAVIOR_GROOMING;
    }

    // ── Prioridade 5: Walking — corpo em movimento, fora de objeto e no chão ───
    if (movBody > 2.0f || roll2sMean > 3.0f) {
        return BEHAVIOR_WALKING;
    }

    // Fallback: resting (velocidade leve mas sem deslocamento claro)
    return BEHAVIOR_RESTING;
}
