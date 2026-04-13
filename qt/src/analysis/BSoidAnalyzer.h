#pragma once
// ── BSoidAnalyzer ──────────────────────────────────────────────────────────
// Análise comportamental pós-sessão inspirada em B-SOiD.
// Pipeline: lê CSV de features[21] → normaliza → PCA 21→6 → K-Means k=N →
//           emite grupos descobertos via sinal analysisReady().
//
// Roda em QThread (runAnalysis()) para não bloquear a UI.
// Entrada: CSV exportado por InferenceController::exportBehaviorFeatures().
// Saída:   vetor de BsoidGroup com estatísticas de cada cluster.

#include <QObject>
#include <QThread>
#include <QString>
#include <QVariantList>
#include <vector>
#include <array>

// ── Resultado por cluster ──────────────────────────────────────────────────
struct BsoidGroup {
    int   clusterId    = 0;
    int   frameCount   = 0;
    float percentage   = 0.0f;   // % do total de frames
    float avgMovNose   = 0.0f;   // movement_nose médio no cluster
    float avgMovBody   = 0.0f;   // movement_body médio no cluster
    int   dominantRule = -1;     // ruleLabel mais frequente no cluster
};

// ── Mapeamento frame→cluster ───────────────────────────────────────────────
struct FrameCluster {
    int frameIdx  = 0;
    int clusterId = 0;
    int ruleLabel = 0;  // ruleLabel da regra nativa (BehaviorScanner::BEHAVIOR_*)
};

class BSoidAnalyzer : public QObject
{
    Q_OBJECT
public:
    explicit BSoidAnalyzer(QObject* parent = nullptr);

    // Carrega CSV e roda análise em background (non-blocking).
    // csvPath: saída de exportBehaviorFeatures(); nClusters: 4–12 (padrão 7)
    Q_INVOKABLE void analyze(const QString& csvPath, int nClusters = 7);

    // Para análise em andamento (não espera terminar)
    Q_INVOKABLE void cancel();

    // Exporta resultado de clustering como CSV
    Q_INVOKABLE bool exportResult(const QString& outPath) const;

    // Retorna o mapeamento frame→{cluster,ruleLabel} como QVariantList para QML
    Q_INVOKABLE QVariantList getFrameMapping() const;

    // Preenche dois BehaviorTimeline diretamente de C++ (evita alocar QVariantList grande)
    // ruleTimeline e clusterTimeline são ponteiros para objetos BehaviorTimeline em QML
    Q_INVOKABLE void populateTimelines(QObject* ruleTimeline, QObject* clusterTimeline, double fps);

    // Extrai clips de vídeo representativos para cada cluster usando FFmpeg.
    // Cria <outDir>/grupo_N/clip_M.mp4 + timestamps.csv por cluster.
    // Se FFmpeg não estiver disponível, cria apenas os timestamps.csv.
    Q_INVOKABLE void extractSnippets(const QString& videoPath, const QString& outDir,
                                     double fps, int nPerCluster = 3);

signals:
    void progress(int percent);                          // 0–100
    void analysisReady(QVariantList groups);             // lista de QVariantMap por cluster
    void errorOccurred(const QString& msg);
    void snippetsProgress(int percent);                  // 0–100 para extração de clips
    void snippetsDone(bool ok, const QString& outDir, const QString& message);

private slots:
    void onWorkerFinished(QVariantList groups, QVector<FrameCluster> mapping);

private:
    QThread*                m_thread  = nullptr;
    bool                    m_running = false;
    QVector<FrameCluster>   m_lastMapping;
};

// ── Worker (roda no QThread) ───────────────────────────────────────────────
class BSoidWorker : public QObject
{
    Q_OBJECT
public:
    static constexpr int PCA_DIMS = 6;    // redução 21 → 6
    static constexpr int MAX_ITER = 100;  // iterações K-Means

    explicit BSoidWorker(const QString& csvPath, int nClusters, QObject* parent = nullptr);

public slots:
    void run();

signals:
    void progress(int percent);
    void finished(QVariantList groups, QVector<FrameCluster> mapping);
    void error(const QString& msg);

private:
    // Tipos internos
    using Feature21 = std::array<float, 21>;
    using Feature6  = std::array<float, PCA_DIMS>;

    struct RawRow {
        int       frameIdx  = 0;
        Feature21 features  = {};
        int       ruleLabel = 0;
    };

    // Etapas do pipeline
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
