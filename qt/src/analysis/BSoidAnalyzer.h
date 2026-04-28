#pragma once
// ── BSoidAnalyzer ──────────────────────────────────────────────────────────
// Post-session behavioural analysis inspired by B-SOiD.
// Pipeline: reads features[21] CSV -> normalise -> PCA 21->6 -> K-Means k=N
//           -> emits discovered groups via analysisReady() signal.
//
// Runs on a QThread (runAnalysis()) to avoid blocking the UI.
// Input:  CSV exported by InferenceController::exportBehaviorFeatures().
// Output: vector of BsoidGroup with per-cluster statistics.

#include <QObject>
#include <QString>
#include <QThread>
#include <QVariantList>
#include <array>
#include <vector>

/// Per-cluster statistics produced by BSoidAnalyzer::analyze().
struct BsoidGroup {
    int   clusterId    = 0;
    int   frameCount   = 0;
    float percentage   = 0.0f;   ///< fraction of total frames (0–100)
    float avgMovNose   = 0.0f;   ///< mean movement_nose in this cluster
    float avgMovBody   = 0.0f;   ///< mean movement_body in this cluster
    int   dominantRule = -1;     ///< most frequent BehaviorScanner rule label
};

/// Per-frame cluster assignment emitted after a successful analysis.
struct FrameCluster {
    int frameIdx  = 0;
    int clusterId = 0;
    int ruleLabel = 0;  ///< BehaviorScanner::BEHAVIOR_* label at this frame
};

/// Post-session behavioural analysis inspired by B-SOiD.
/// Pipeline: reads features[21] CSV → normalises → PCA 21→6 → K-Means k=N →
/// emits discovered groups via analysisReady().
/// Runs in a QThread (analyze()) to avoid blocking the UI.
class BSoidAnalyzer : public QObject
{
    Q_OBJECT
public:
    explicit BSoidAnalyzer(QObject* parent = nullptr);

    /// Load CSV and run analysis in background (non-blocking).
    /// @param csvPath  output of InferenceController::exportBehaviorFeatures()
    /// @param nClusters  number of K-Means clusters (4–12, default 7)
    Q_INVOKABLE void analyze(const QString& csvPath, int nClusters = 7);

    /// Request cancellation of the running analysis (does not block).
    Q_INVOKABLE void cancel();

    /// Export last clustering result as a CSV file.
    Q_INVOKABLE bool exportResult(const QString& outPath) const;

    /// Return the frame→{cluster,ruleLabel} mapping as a QVariantList for QML.
    Q_INVOKABLE QVariantList getFrameMapping() const;

    /// Fill two BehaviorTimeline objects directly from C++ (avoids allocating a large QVariantList).
    /// @param ruleTimeline     pointer to a BehaviorTimeline QML object (rule colours)
    /// @param clusterTimeline  pointer to a BehaviorTimeline QML object (cluster colours)
    Q_INVOKABLE void populateTimelines(QObject* ruleTimeline, QObject* clusterTimeline, double fps);

    /// Extract representative video clips for each cluster using FFmpeg.
    /// Creates \c <outDir>/grupo_N/clip_M.mp4 + \c timestamps.csv per cluster.
    /// If FFmpeg is unavailable, only \c timestamps.csv files are written.
    Q_INVOKABLE void extractSnippets(const QString& videoPath, const QString& outDir,
                                     double fps, int nPerCluster = 3);

signals:
    void progress(int percent);                          ///< 0–100 during PCA + K-Means
    void analysisReady(QVariantList groups);             ///< QVariantMap per cluster
    void errorOccurred(const QString& msg);
    void snippetsProgress(int percent);                  ///< 0–100 during clip extraction
    void snippetsDone(bool ok, const QString& outDir, const QString& message);

private slots:
    void onWorkerFinished(QVariantList groups, QVector<FrameCluster> mapping);

private:
    QThread*                m_thread  = nullptr;
    bool                    m_running = false;
    QVector<FrameCluster>   m_lastMapping;
};

/// Background worker that runs PCA + K-Means on the feature CSV.
/// Owned by BSoidAnalyzer; moved to its own QThread for the duration of analyze().
class BSoidWorker : public QObject
{
    Q_OBJECT
public:
    static constexpr int PCA_DIMS = 6;    ///< PCA output dimensionality (21 → 6)
    static constexpr int MAX_ITER = 100;  ///< K-Means iteration limit

    explicit BSoidWorker(const QString& csvPath, int nClusters, QObject* parent = nullptr);

public slots:
    void run();

signals:
    void progress(int percent);
    void finished(QVariantList groups, QVector<FrameCluster> mapping);
    void error(const QString& msg);

private:
    using Feature21 = std::array<float, 21>;
    using Feature6  = std::array<float, PCA_DIMS>;

    struct RawRow {
        int       frameIdx  = 0;
        Feature21 features  = {};
        int       ruleLabel = 0;
    };

    bool             loadCsv(std::vector<RawRow>& rows);
    void             normalize(std::vector<Feature21>& data);
    std::vector<Feature6> reducePca(const std::vector<Feature21>& data);
    std::vector<int> kMeans(const std::vector<Feature6>& data, int k);
    QVariantList     buildGroups(const std::vector<RawRow>& rows,
                                 const std::vector<int>& labels, int k);

    QString m_csvPath;
    int     m_nClusters;
    bool    m_cancelled = false;
};
