#include "BSoidAnalyzer.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QThread>
#include <QTextStream>
#include <QVariantMap>

#include <algorithm>
#include <cmath>
#include <limits>
#include <numeric>
#include <random>
#include <unordered_map>

// ── BSoidAnalyzer ──────────────────────────────────────────────────────────

BSoidAnalyzer::BSoidAnalyzer(QObject* parent) : QObject(parent) {}

void BSoidAnalyzer::analyze(const QString& csvPath, int nClusters)
{
    if (m_running) {
        emit errorOccurred("Analysis already in progress.");
        return;
    }
    m_running = true;
    m_lastMapping.clear();

    auto* worker = new BSoidWorker(csvPath, nClusters);
    m_thread = new QThread(this);
    worker->moveToThread(m_thread);

    connect(m_thread, &QThread::started,  worker, &BSoidWorker::run);
    connect(worker, &BSoidWorker::progress, this, &BSoidAnalyzer::progress);
    connect(worker, &BSoidWorker::error,    this, [this](const QString& msg) {
        m_running = false;
        emit errorOccurred(msg);
    });
    connect(worker, &BSoidWorker::finished, this, &BSoidAnalyzer::onWorkerFinished);
    connect(worker, &BSoidWorker::finished, m_thread, &QThread::quit);
    connect(m_thread, &QThread::finished,  worker,   &QObject::deleteLater);
    connect(m_thread, &QThread::finished,  m_thread, &QObject::deleteLater);

    m_thread->start();
}

void BSoidAnalyzer::cancel()
{
    m_running = false;
}

void BSoidAnalyzer::onWorkerFinished(QVariantList groups, QVector<FrameCluster> mapping)
{
    m_running     = false;
    m_lastMapping = mapping;
    emit analysisReady(groups);
}

bool BSoidAnalyzer::exportResult(const QString& outPath) const
{
    if (m_lastMapping.isEmpty()) return false;

    QFile outputFile(outPath);
    if (!outputFile.open(QIODevice::WriteOnly | QIODevice::Text)) return false;

    QTextStream out(&outputFile);
    out.setEncoding(QStringConverter::Utf8);
    out << "\xEF\xBB\xBF";
    out << "frame,cluster\n";
    for (const FrameCluster &frameCluster : m_lastMapping)
        out << frameCluster.frameIdx << ',' << frameCluster.clusterId << '\n';

    return true;
}

QVariantList BSoidAnalyzer::getFrameMapping() const
{
    QVariantList result;
    result.reserve(m_lastMapping.size());
    for (const FrameCluster &frameCluster : m_lastMapping) {
        QVariantMap frameMap;
        frameMap["frameIdx"]  = frameCluster.frameIdx;
        frameMap["clusterId"] = frameCluster.clusterId;
        frameMap["ruleLabel"] = frameCluster.ruleLabel;
        result.append(frameMap);
    }
    return result;
}

void BSoidAnalyzer::populateTimelines(QObject* ruleObj, QObject* clusterObj, double fps)
{
    if (!ruleObj || !clusterObj || m_lastMapping.isEmpty()) return;
    const float fpsF = static_cast<float>(fps > 0.0 ? fps : 30.0);
    for (const FrameCluster &frameCluster : m_lastMapping) {
        const float timeSec = frameCluster.frameIdx / fpsF;
        QMetaObject::invokeMethod(ruleObj,    "appendPoint",
            Qt::DirectConnection, Q_ARG(float, timeSec), Q_ARG(int, frameCluster.ruleLabel));
        QMetaObject::invokeMethod(clusterObj, "appendPoint",
            Qt::DirectConnection, Q_ARG(float, timeSec), Q_ARG(int, frameCluster.clusterId));
    }
    QMetaObject::invokeMethod(ruleObj,    "update", Qt::DirectConnection);
    QMetaObject::invokeMethod(clusterObj, "update", Qt::DirectConnection);
}

void BSoidAnalyzer::extractSnippets(const QString& videoPath, const QString& outDir,
                                    double fps, int nPerCluster)
{
    if (m_lastMapping.isEmpty()) {
        emit snippetsDone(false, "", "No clustering result available.");
        return;
    }

    QVector<FrameCluster> mapping = m_lastMapping;

    auto* thread = QThread::create([this, mapping, videoPath, outDir, fps, nPerCluster]() {
        struct Segment { int start; int end; int clusterId; };

        // Find contiguous segments per cluster
        QMap<int, QVector<Segment>> byCluster;
        if (!mapping.isEmpty()) {
            int curCluster = mapping[0].clusterId;
            int segStart   = mapping[0].frameIdx;
            int prevFrame  = mapping[0].frameIdx;

            for (int segIdx = 1; segIdx < mapping.size(); ++segIdx) {
                const FrameCluster &frameCluster = mapping[segIdx];
                // New sequence: different cluster OR gap > 2 frames
                if (frameCluster.clusterId != curCluster || frameCluster.frameIdx > prevFrame + 2) {
                    byCluster[curCluster].push_back({segStart, prevFrame, curCluster});
                    curCluster = frameCluster.clusterId;
                    segStart   = frameCluster.frameIdx;
                }
                prevFrame = frameCluster.frameIdx;
            }
            byCluster[curCluster].push_back({segStart, prevFrame, curCluster});
        }

        for (auto &segs : byCluster) {
            std::sort(segs.begin(), segs.end(), [](const Segment &a, const Segment &b) {
                return (a.end - a.start) > (b.end - b.start);
            });
        }

        QString ffmpegExe;
        {
            const QString appFfmpeg = QCoreApplication::applicationDirPath() + "/ffmpeg.exe";
            if (QFile::exists(appFfmpeg)) {
                ffmpegExe = appFfmpeg;
            } else {
                QProcess test;
                test.start("ffmpeg", {"-version"});
                if (test.waitForFinished(3000) && test.exitCode() == 0)
                    ffmpegExe = "ffmpeg";
            }
        }
        const bool hasVideo = !videoPath.isEmpty() && QFile::exists(videoPath) && !ffmpegExe.isEmpty();

        int totalClips = 0;
        for (const auto &segs : byCluster)
            totalClips += qMin(segs.size(), nPerCluster);
        if (totalClips == 0) totalClips = 1;
        int clipsExtracted = 0;

        for (auto it = byCluster.cbegin(); it != byCluster.cend(); ++it) {
            const int               clusterId = it.key();
            const QVector<Segment> &segs      = it.value();

            const QString clusterDir = outDir + "/grupo_" + QString::number(clusterId + 1);
            QDir().mkpath(clusterDir);

            // Always write timestamps CSV — FFmpeg is optional
            {
                QFile tsFile(clusterDir + "/timestamps.csv");
                if (tsFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
                    QTextStream ts(&tsFile);
                    ts.setEncoding(QStringConverter::Utf8);
                    ts << "\xEF\xBB\xBF";
                    ts << "clip,start_sec,end_sec,duration_sec\n";
                    const int clipCount = qMin(segs.size(), nPerCluster);
                    for (int clipIdx = 0; clipIdx < clipCount; ++clipIdx) {
                        const double startSec = segs[clipIdx].start / fps;
                        const double endSec   = segs[clipIdx].end   / fps;
                        const double durSec   = qMin(endSec - startSec, 5.0);
                        ts << (clipIdx + 1) << ',' << startSec << ',' << endSec << ',' << durSec << '\n';
                    }
                }
            }

            if (hasVideo) {
                const int clipCount = qMin(segs.size(), nPerCluster);
                for (int clipIdx = 0; clipIdx < clipCount; ++clipIdx) {
                    const double startSec  = segs[clipIdx].start / fps;
                    const double durSec    = qMin((segs[clipIdx].end - segs[clipIdx].start + 1) / fps, 5.0);
                    const QString clipPath = clusterDir + "/clip_" + QString::number(clipIdx + 1) + ".mp4";

                    QProcess proc;
                    proc.start(ffmpegExe, {
                        "-ss", QString::number(startSec, 'f', 3),
                        "-i",  videoPath,
                        "-t",  QString::number(durSec, 'f', 3),
                        "-c:v", "libx264", "-preset", "ultrafast", "-crf", "28",
                        "-an", "-y",
                        clipPath
                    });
                    proc.waitForFinished(60000);

                    ++clipsExtracted;
                    emit snippetsProgress((clipsExtracted * 100) / totalClips);
                }
            }
        }

        const QString msg = hasVideo
            ? "Clips extracted successfully (FFmpeg)."
            : "FFmpeg not found — only timestamps.csv written per cluster folder.";
        emit snippetsDone(true, outDir, msg);
    });

    thread->setParent(this);
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);
    emit snippetsProgress(0);
    thread->start();
}

// ── BSoidWorker ────────────────────────────────────────────────────────────

BSoidWorker::BSoidWorker(const QString& csvPath, int nClusters, QObject* parent)
    : QObject(parent), m_csvPath(csvPath), m_nClusters(nClusters) {}

void BSoidWorker::run()
{
    std::vector<RawRow> rows;
    emit progress(0);

    if (!loadCsv(rows)) {
        emit error("Could not read feature CSV: " + m_csvPath);
        return;
    }
    if (rows.size() < static_cast<size_t>(m_nClusters * 2)) {
        emit error("Insufficient data for clustering (minimum " +
                   QString::number(m_nClusters * 2) + " frames).");
        return;
    }

    emit progress(10);

    std::vector<Feature21> data;
    data.reserve(rows.size());
    for (const RawRow &rawRow : rows) data.push_back(rawRow.features);

    normalize(data);
    emit progress(25);

    auto reduced = reducePca(data);
    emit progress(50);

    auto labels = kMeans(reduced, m_nClusters);
    emit progress(80);

    auto groups = buildGroups(rows, labels, m_nClusters);

    QVector<FrameCluster> mapping;
    mapping.reserve(static_cast<int>(rows.size()));
    for (size_t rowIdx = 0; rowIdx < rows.size(); ++rowIdx)
        mapping.push_back({ rows[rowIdx].frameIdx, labels[rowIdx], rows[rowIdx].ruleLabel });

    emit progress(100);
    emit finished(groups, mapping);
}

// ── loadCsv ───────────────────────────────────────────────────────────────
bool BSoidWorker::loadCsv(std::vector<RawRow>& rows)
{
    QFile csvFile(m_csvPath);
    if (!csvFile.open(QIODevice::ReadOnly | QIODevice::Text)) return false;

    QTextStream csvStream(&csvFile);
    if (!csvStream.atEnd()) csvStream.readLine(); // skip header

    while (!csvStream.atEnd()) {
        const QString line = csvStream.readLine().trimmed();
        if (line.isEmpty()) continue;
        const QStringList parts = line.split(',');
        // frame + 21 features + rule_label = 23 columns
        if (parts.size() < 23) continue;

        RawRow row;
        row.frameIdx  = parts[0].toInt();
        for (int featureIdx = 0; featureIdx < 21; ++featureIdx)
            row.features[featureIdx] = parts[1 + featureIdx].toFloat();
        row.ruleLabel = parts[22].toInt();
        rows.push_back(row);
    }
    return !rows.empty();
}

// ── normalize (z-score por coluna) ────────────────────────────────────────
void BSoidWorker::normalize(std::vector<Feature21>& data)
{
    const size_t N = data.size();
    for (int colIdx = 0; colIdx < 21; ++colIdx) {
        float mean = 0.0f;
        for (const auto& row : data) mean += row[colIdx];
        mean /= static_cast<float>(N);

        float var = 0.0f;
        for (const auto& row : data) {
            const float delta = row[colIdx] - mean;
            var += delta * delta;
        }
        float stddev = std::sqrt(var / static_cast<float>(N));
        if (stddev < 1e-8f) stddev = 1.0f; // guard against zero-variance columns

        for (auto& row : data)
            row[colIdx] = (row[colIdx] - mean) / stddev;
    }
}

/// Reduces 21-dimensional features to PCA_DIMS via power iteration + deflation.
std::vector<BSoidWorker::Feature6> BSoidWorker::reducePca(const std::vector<Feature21>& data)
{
    const int N   = static_cast<int>(data.size());
    const int DIM = 21;

    // Build 21×21 covariance matrix
    std::vector<std::vector<double>> covMatrix(DIM, std::vector<double>(DIM, 0.0));
    for (const auto& row : data) {
        for (int i = 0; i < DIM; ++i)
            for (int j = i; j < DIM; ++j) {
                const double product = static_cast<double>(row[i]) * static_cast<double>(row[j]);
                covMatrix[i][j] += product;
                if (i != j) covMatrix[j][i] += product;
            }
    }
    for (int i = 0; i < DIM; ++i)
        for (int j = 0; j < DIM; ++j)
            covMatrix[i][j] /= static_cast<double>(N);

    std::vector<std::vector<double>> eigenvecs;
    auto deflatedCov = covMatrix;

    for (int pcIdx = 0; pcIdx < PCA_DIMS; ++pcIdx) {
        std::vector<double> eigenVec(DIM, 0.0);
        eigenVec[pcIdx % DIM] = 1.0;

        for (int iter = 0; iter < 200; ++iter) {
            std::vector<double> matVecProduct(DIM, 0.0);
            for (int i = 0; i < DIM; ++i)
                for (int j = 0; j < DIM; ++j)
                    matVecProduct[i] += deflatedCov[i][j] * eigenVec[j];

            double eigenVecNorm = 0.0;
            for (double x : matVecProduct) eigenVecNorm += x * x;
            eigenVecNorm = std::sqrt(eigenVecNorm);
            if (eigenVecNorm < 1e-12) break;
            for (int i = 0; i < DIM; ++i) eigenVec[i] = matVecProduct[i] / eigenVecNorm;
        }

        eigenvecs.push_back(eigenVec);

        // Deflation: subtract found component — eigenvalue ≈ v^T * cov * v
        double eigenvalue = 0.0;
        std::vector<double> covTimesVec(DIM, 0.0);
        for (int i = 0; i < DIM; ++i)
            for (int j = 0; j < DIM; ++j)
                covTimesVec[i] += deflatedCov[i][j] * eigenVec[j];
        for (int i = 0; i < DIM; ++i) eigenvalue += eigenVec[i] * covTimesVec[i];

        for (int i = 0; i < DIM; ++i)
            for (int j = 0; j < DIM; ++j)
                deflatedCov[i][j] -= eigenvalue * eigenVec[i] * eigenVec[j];
    }

    std::vector<Feature6> result(data.size());
    for (size_t rowIdx = 0; rowIdx < data.size(); ++rowIdx) {
        for (int pcIdx = 0; pcIdx < PCA_DIMS; ++pcIdx) {
            double proj = 0.0;
            for (int j = 0; j < DIM; ++j)
                proj += eigenvecs[pcIdx][j] * static_cast<double>(data[rowIdx][j]);
            result[rowIdx][pcIdx] = static_cast<float>(proj);
        }
    }
    return result;
}

/// K-Means++ init followed by Lloyd's algorithm. Fixed seed for reproducibility.
std::vector<int> BSoidWorker::kMeans(const std::vector<Feature6>& data, int k)
{
    const int N = static_cast<int>(data.size());

    std::mt19937 rng(42); // fixed seed — reproducible results
    std::vector<Feature6> centroids;
    centroids.reserve(k);

    std::uniform_int_distribution<int> distIdx(0, N - 1);
    centroids.push_back(data[distIdx(rng)]);

    for (int centroidIdx = 1; centroidIdx < k; ++centroidIdx) {
        std::vector<float> minDistSquared(N, std::numeric_limits<float>::max());
        for (int i = 0; i < N; ++i) {
            for (const auto& cen : centroids) {
                float distSquared = 0.0f;
                for (int j = 0; j < PCA_DIMS; ++j) {
                    const float diff = data[i][j] - cen[j];
                    distSquared += diff * diff;
                }
                minDistSquared[i] = std::min(minDistSquared[i], distSquared);
            }
        }
        // Sample next centroid proportional to squared distance (K-Means++ criterion)
        std::discrete_distribution<int> weighted(minDistSquared.begin(), minDistSquared.end());
        centroids.push_back(data[weighted(rng)]);
    }

    std::vector<int> labels(N, 0);
    for (int iter = 0; iter < MAX_ITER; ++iter) {
        bool changed = false;

        for (int i = 0; i < N; ++i) {
            int   bestCluster = 0;
            float bestDist    = std::numeric_limits<float>::max();
            for (int c = 0; c < k; ++c) {
                float distSquared = 0.0f;
                for (int j = 0; j < PCA_DIMS; ++j) {
                    const float diff = data[i][j] - centroids[c][j];
                    distSquared += diff * diff;
                }
                if (distSquared < bestDist) { bestDist = distSquared; bestCluster = c; }
            }
            if (labels[i] != bestCluster) { labels[i] = bestCluster; changed = true; }
        }

        if (!changed) break;

        std::vector<Feature6> updatedCentroids(k, Feature6{});
        std::vector<int>      clusterCounts(k, 0);
        for (int i = 0; i < N; ++i) {
            const int c = labels[i];
            for (int j = 0; j < PCA_DIMS; ++j)
                updatedCentroids[c][j] += data[i][j];
            ++clusterCounts[c];
        }
        for (int c = 0; c < k; ++c) {
            if (clusterCounts[c] > 0)
                for (int j = 0; j < PCA_DIMS; ++j)
                    updatedCentroids[c][j] /= static_cast<float>(clusterCounts[c]);
            else
                updatedCentroids[c] = centroids[c]; // empty cluster: keep previous centroid
        }
        centroids = updatedCentroids;
    }

    return labels;
}

QVariantList BSoidWorker::buildGroups(const std::vector<RawRow>& rows,
                                      const std::vector<int>& labels, int k)
{
    struct ClusterStats {
        int   count     = 0;
        float movNose   = 0.0f;
        float movBody   = 0.0f;
        std::unordered_map<int, int> ruleCounts;
    };
    std::vector<ClusterStats> stats(k);

    for (size_t rowIdx = 0; rowIdx < rows.size(); ++rowIdx) {
        const int clusterIdx = labels[rowIdx];
        ClusterStats &clusterStats = stats[clusterIdx];
        clusterStats.count++;
        clusterStats.movNose += rows[rowIdx].features[0];
        clusterStats.movBody += rows[rowIdx].features[1];
        clusterStats.ruleCounts[rows[rowIdx].ruleLabel]++;
    }

    const float totalFrames = static_cast<float>(rows.size());
    QVariantList result;

    for (int clusterIdx = 0; clusterIdx < k; ++clusterIdx) {
        const ClusterStats &clusterStats = stats[clusterIdx];
        if (clusterStats.count == 0) continue;

        int dominantRule = -1;
        int maxRuleCount = 0;
        for (const auto& [rule, cnt] : clusterStats.ruleCounts) {
            if (cnt > maxRuleCount) { maxRuleCount = cnt; dominantRule = rule; }
        }

        QVariantMap groupMap;
        groupMap["clusterId"]    = clusterIdx;
        groupMap["frameCount"]   = clusterStats.count;
        groupMap["percentage"]   = static_cast<double>(clusterStats.count) / static_cast<double>(totalFrames) * 100.0;
        groupMap["avgMovNose"]   = static_cast<double>(clusterStats.movNose / static_cast<float>(clusterStats.count));
        groupMap["avgMovBody"]   = static_cast<double>(clusterStats.movBody / static_cast<float>(clusterStats.count));
        groupMap["dominantRule"] = dominantRule;
        result.append(groupMap);
    }

    std::sort(result.begin(), result.end(), [](const QVariant& a, const QVariant& b) {
        return a.toMap()["percentage"].toDouble() > b.toMap()["percentage"].toDouble();
    });

    return result;
}
