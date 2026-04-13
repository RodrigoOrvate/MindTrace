#include "BSoidAnalyzer.h"
#include <QFile>
#include <QTextStream>
#include <QDebug>
#include <QVariantMap>
#include <QDir>
#include <QProcess>
#include <QThread>
#include <QCoreApplication>
#include <cmath>
#include <numeric>
#include <random>
#include <limits>
#include <algorithm>
#include <unordered_map>

// ── BSoidAnalyzer ──────────────────────────────────────────────────────────

BSoidAnalyzer::BSoidAnalyzer(QObject* parent) : QObject(parent) {}

void BSoidAnalyzer::analyze(const QString& csvPath, int nClusters)
{
    if (m_running) {
        emit errorOccurred("Análise já em andamento.");
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
    // Seta flag — o worker verifica periodicamente
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

    QFile f(outPath);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) return false;

    QTextStream out(&f);
    out.setEncoding(QStringConverter::Utf8);
    out << "\xEF\xBB\xBF";
    out << "frame,cluster\n";
    for (const auto& fc : m_lastMapping)
        out << fc.frameIdx << ',' << fc.clusterId << '\n';

    return true;
}

QVariantList BSoidAnalyzer::getFrameMapping() const
{
    QVariantList result;
    result.reserve(m_lastMapping.size());
    for (const auto& fc : m_lastMapping) {
        QVariantMap m;
        m["frameIdx"]  = fc.frameIdx;
        m["clusterId"] = fc.clusterId;
        m["ruleLabel"] = fc.ruleLabel;
        result.append(m);
    }
    return result;
}

void BSoidAnalyzer::populateTimelines(QObject* ruleObj, QObject* clusterObj, double fps)
{
    if (!ruleObj || !clusterObj || m_lastMapping.isEmpty()) return;
    const float fpsF = static_cast<float>(fps > 0.0 ? fps : 30.0);
    for (const auto& fc : m_lastMapping) {
        const float t = fc.frameIdx / fpsF;
        QMetaObject::invokeMethod(ruleObj,    "appendPoint",
            Qt::DirectConnection, Q_ARG(float, t), Q_ARG(int, fc.ruleLabel));
        QMetaObject::invokeMethod(clusterObj, "appendPoint",
            Qt::DirectConnection, Q_ARG(float, t), Q_ARG(int, fc.clusterId));
    }
    // Solicita repintura
    QMetaObject::invokeMethod(ruleObj,    "update", Qt::DirectConnection);
    QMetaObject::invokeMethod(clusterObj, "update", Qt::DirectConnection);
}

void BSoidAnalyzer::extractSnippets(const QString& videoPath, const QString& outDir,
                                    double fps, int nPerCluster)
{
    if (m_lastMapping.isEmpty()) {
        emit snippetsDone(false, "", "Nenhum resultado de clustering disponível.");
        return;
    }

    // Copia o mapping antes de entrar na thread
    QVector<FrameCluster> mapping = m_lastMapping;

    auto* thread = QThread::create([this, mapping, videoPath, outDir, fps, nPerCluster]() {
        struct Segment { int start; int end; int clusterId; };

        // ── Encontra segmentos contíguos por cluster ──────────────────────────
        QMap<int, QVector<Segment>> byCluster;
        if (!mapping.isEmpty()) {
            int curCluster = mapping[0].clusterId;
            int segStart   = mapping[0].frameIdx;
            int prevFrame  = mapping[0].frameIdx;

            for (int i = 1; i < mapping.size(); ++i) {
                const auto& fc = mapping[i];
                // Nova sequência: cluster diferente OU gap > 2 frames
                if (fc.clusterId != curCluster || fc.frameIdx > prevFrame + 2) {
                    byCluster[curCluster].push_back({segStart, prevFrame, curCluster});
                    curCluster = fc.clusterId;
                    segStart   = fc.frameIdx;
                }
                prevFrame = fc.frameIdx;
            }
            byCluster[curCluster].push_back({segStart, prevFrame, curCluster});
        }

        // Ordena segmentos por duração decrescente dentro de cada cluster
        for (auto& segs : byCluster) {
            std::sort(segs.begin(), segs.end(), [](const Segment& a, const Segment& b) {
                return (a.end - a.start) > (b.end - b.start);
            });
        }

        // ── Detecta FFmpeg ─────────────────────────────────────────────────────
        QString ffmpeg;
        {
            QString appFfmpeg = QCoreApplication::applicationDirPath() + "/ffmpeg.exe";
            if (QFile::exists(appFfmpeg)) {
                ffmpeg = appFfmpeg;
            } else {
                QProcess test;
                test.start("ffmpeg", {"-version"});
                if (test.waitForFinished(3000) && test.exitCode() == 0)
                    ffmpeg = "ffmpeg";
            }
        }
        const bool hasVideo = !videoPath.isEmpty() && QFile::exists(videoPath) && !ffmpeg.isEmpty();

        // ── Conta total de clips para progresso ───────────────────────────────
        int total = 0;
        for (const auto& segs : byCluster)
            total += qMin(segs.size(), nPerCluster);
        if (total == 0) total = 1;
        int done = 0;

        // ── Extrai por cluster ─────────────────────────────────────────────────
        for (auto it = byCluster.cbegin(); it != byCluster.cend(); ++it) {
            const int            clusterId = it.key();
            const QVector<Segment>& segs  = it.value();

            QString clusterDir = outDir + "/grupo_" + QString::number(clusterId + 1);
            QDir().mkpath(clusterDir);

            // Timestamps CSV (sempre criado — independe de FFmpeg)
            {
                QFile tsFile(clusterDir + "/timestamps.csv");
                if (tsFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
                    QTextStream ts(&tsFile);
                    ts.setEncoding(QStringConverter::Utf8);
                    ts << "\xEF\xBB\xBF";
                    ts << "clip,start_sec,end_sec,duration_sec\n";
                    int n = qMin(segs.size(), nPerCluster);
                    for (int i = 0; i < n; ++i) {
                        double startSec = segs[i].start / fps;
                        double endSec   = segs[i].end   / fps;
                        double durSec   = qMin(endSec - startSec, 5.0);
                        ts << (i + 1) << ',' << startSec << ',' << endSec << ',' << durSec << '\n';
                    }
                }
            }

            // Extração de vídeo com FFmpeg (se disponível)
            if (hasVideo) {
                int n = qMin(segs.size(), nPerCluster);
                for (int i = 0; i < n; ++i) {
                    double startSec = segs[i].start / fps;
                    double durSec   = qMin((segs[i].end - segs[i].start + 1) / fps, 5.0);
                    QString output  = clusterDir + "/clip_" + QString::number(i + 1) + ".mp4";

                    QProcess proc;
                    proc.start(ffmpeg, {
                        "-ss", QString::number(startSec, 'f', 3),
                        "-i",  videoPath,
                        "-t",  QString::number(durSec, 'f', 3),
                        "-c:v", "libx264", "-preset", "ultrafast", "-crf", "28",
                        "-an", "-y",
                        output
                    });
                    proc.waitForFinished(60000);

                    ++done;
                    emit snippetsProgress((done * 100) / total);
                }
            }
        }

        const QString msg = hasVideo
            ? "Clips extraídos com sucesso (FFmpeg)."
            : "FFmpeg não encontrado — apenas timestamps.csv criados em cada pasta de grupo.";
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
        emit error("Não foi possível ler o CSV de features: " + m_csvPath);
        return;
    }
    if (rows.size() < static_cast<size_t>(m_nClusters * 2)) {
        emit error("Dados insuficientes para clustering (mínimo " +
                   QString::number(m_nClusters * 2) + " frames).");
        return;
    }

    emit progress(10);

    // ── Extrai features brutas ─────────────────────────────────────────────
    std::vector<Feature21> data;
    data.reserve(rows.size());
    for (const auto& r : rows) data.push_back(r.features);

    // ── Normalização (z-score por coluna) ─────────────────────────────────
    normalize(data);
    emit progress(25);

    // ── PCA 21 → 6 dimensões ──────────────────────────────────────────────
    auto reduced = reducePca(data);
    emit progress(50);

    // ── K-Means ───────────────────────────────────────────────────────────
    auto labels = kMeans(reduced, m_nClusters);
    emit progress(80);

    // ── Montar resultado ──────────────────────────────────────────────────
    auto groups = buildGroups(rows, labels, m_nClusters);

    // Mapeamento frame → cluster para exportResult() e timelines
    QVector<FrameCluster> mapping;
    mapping.reserve(static_cast<int>(rows.size()));
    for (size_t i = 0; i < rows.size(); ++i)
        mapping.push_back({ rows[i].frameIdx, labels[i], rows[i].ruleLabel });

    emit progress(100);
    emit finished(groups, mapping);
}

// ── loadCsv ───────────────────────────────────────────────────────────────
bool BSoidWorker::loadCsv(std::vector<RawRow>& rows)
{
    QFile f(m_csvPath);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return false;

    QTextStream in(&f);
    // Pula cabeçalho
    if (!in.atEnd()) in.readLine();

    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();
        if (line.isEmpty()) continue;
        QStringList parts = line.split(',');
        // frame + 21 features + rule_label = 23 colunas
        if (parts.size() < 23) continue;

        RawRow row;
        row.frameIdx  = parts[0].toInt();
        for (int i = 0; i < 21; ++i)
            row.features[i] = parts[1 + i].toFloat();
        row.ruleLabel = parts[22].toInt();
        rows.push_back(row);
    }
    return !rows.empty();
}

// ── normalize (z-score por coluna) ────────────────────────────────────────
void BSoidWorker::normalize(std::vector<Feature21>& data)
{
    const size_t N = data.size();
    for (int col = 0; col < 21; ++col) {
        // Média
        float mean = 0.0f;
        for (const auto& row : data) mean += row[col];
        mean /= static_cast<float>(N);

        // Desvio padrão
        float var = 0.0f;
        for (const auto& row : data) {
            float d = row[col] - mean;
            var += d * d;
        }
        float stddev = std::sqrt(var / static_cast<float>(N));
        if (stddev < 1e-8f) stddev = 1.0f; // evita divisão por zero

        for (auto& row : data)
            row[col] = (row[col] - mean) / stddev;
    }
}

// ── reducePca — PCA simplificada via método da potência ───────────────────
// Extrai os primeiros PCA_DIMS componentes principais usando deflação.
// Adequado para dados de comportamento com ~10k–300k frames.
std::vector<BSoidWorker::Feature6> BSoidWorker::reducePca(const std::vector<Feature21>& data)
{
    const int N   = static_cast<int>(data.size());
    const int DIM = 21;

    // Matriz de covariância 21×21
    std::vector<std::vector<double>> cov(DIM, std::vector<double>(DIM, 0.0));
    for (const auto& row : data) {
        for (int i = 0; i < DIM; ++i)
            for (int j = i; j < DIM; ++j) {
                double v = static_cast<double>(row[i]) * static_cast<double>(row[j]);
                cov[i][j] += v;
                if (i != j) cov[j][i] += v;
            }
    }
    for (int i = 0; i < DIM; ++i)
        for (int j = 0; j < DIM; ++j)
            cov[i][j] /= static_cast<double>(N);

    // Extrai PCA_DIMS vetores próprios via método da potência + deflação
    std::vector<std::vector<double>> eigenvecs;
    auto covCopy = cov;

    for (int pc = 0; pc < PCA_DIMS; ++pc) {
        // Inicializa vetor aleatório
        std::vector<double> v(DIM, 0.0);
        v[pc % DIM] = 1.0;

        // Iteração da potência
        for (int iter = 0; iter < 200; ++iter) {
            std::vector<double> nv(DIM, 0.0);
            for (int i = 0; i < DIM; ++i)
                for (int j = 0; j < DIM; ++j)
                    nv[i] += covCopy[i][j] * v[j];

            // Normaliza
            double norm = 0.0;
            for (double x : nv) norm += x * x;
            norm = std::sqrt(norm);
            if (norm < 1e-12) break;
            for (int i = 0; i < DIM; ++i) v[i] = nv[i] / norm;
        }

        eigenvecs.push_back(v);

        // Deflação: remove componente encontrado da covariância
        // eigenvalue ≈ v^T * cov * v
        double eigenval = 0.0;
        std::vector<double> cv(DIM, 0.0);
        for (int i = 0; i < DIM; ++i)
            for (int j = 0; j < DIM; ++j)
                cv[i] += covCopy[i][j] * v[j];
        for (int i = 0; i < DIM; ++i) eigenval += v[i] * cv[i];

        for (int i = 0; i < DIM; ++i)
            for (int j = 0; j < DIM; ++j)
                covCopy[i][j] -= eigenval * v[i] * v[j];
    }

    // Projeta dados nos PCA_DIMS componentes
    std::vector<Feature6> result(data.size());
    for (size_t row = 0; row < data.size(); ++row) {
        for (int pc = 0; pc < PCA_DIMS; ++pc) {
            double proj = 0.0;
            for (int j = 0; j < DIM; ++j)
                proj += eigenvecs[pc][j] * static_cast<double>(data[row][j]);
            result[row][pc] = static_cast<float>(proj);
        }
    }
    return result;
}

// ── kMeans — K-Means padrão (Lloyd's algorithm) ───────────────────────────
std::vector<int> BSoidWorker::kMeans(const std::vector<Feature6>& data, int k)
{
    const int N = static_cast<int>(data.size());

    // Inicialização K-Means++ (melhora convergência vs inicialização aleatória)
    std::mt19937 rng(42); // seed fixo → resultados reproduzíveis
    std::vector<Feature6> centroids;
    centroids.reserve(k);

    // Primeiro centroide: aleatório
    std::uniform_int_distribution<int> distIdx(0, N - 1);
    centroids.push_back(data[distIdx(rng)]);

    for (int c = 1; c < k; ++c) {
        // Distância mínima de cada ponto ao centroide mais próximo
        std::vector<float> dist2(N, std::numeric_limits<float>::max());
        for (int i = 0; i < N; ++i) {
            for (const auto& cen : centroids) {
                float d = 0.0f;
                for (int j = 0; j < PCA_DIMS; ++j) {
                    float diff = data[i][j] - cen[j];
                    d += diff * diff;
                }
                dist2[i] = std::min(dist2[i], d);
            }
        }
        // Amostra proporcional a dist²
        std::discrete_distribution<int> weighted(dist2.begin(), dist2.end());
        centroids.push_back(data[weighted(rng)]);
    }

    // Iterações Lloyd
    std::vector<int> labels(N, 0);
    for (int iter = 0; iter < MAX_ITER; ++iter) {
        bool changed = false;

        // Atribuição
        for (int i = 0; i < N; ++i) {
            int   best  = 0;
            float bestD = std::numeric_limits<float>::max();
            for (int c = 0; c < k; ++c) {
                float d = 0.0f;
                for (int j = 0; j < PCA_DIMS; ++j) {
                    float diff = data[i][j] - centroids[c][j];
                    d += diff * diff;
                }
                if (d < bestD) { bestD = d; best = c; }
            }
            if (labels[i] != best) { labels[i] = best; changed = true; }
        }

        if (!changed) break;

        // Atualização de centróides
        std::vector<Feature6> newCen(k, Feature6{});
        std::vector<int>      counts(k, 0);
        for (int i = 0; i < N; ++i) {
            int c = labels[i];
            for (int j = 0; j < PCA_DIMS; ++j)
                newCen[c][j] += data[i][j];
            ++counts[c];
        }
        for (int c = 0; c < k; ++c) {
            if (counts[c] > 0)
                for (int j = 0; j < PCA_DIMS; ++j)
                    newCen[c][j] /= static_cast<float>(counts[c]);
            else
                newCen[c] = centroids[c]; // cluster vazio: mantém centroide
        }
        centroids = newCen;
    }

    return labels;
}

// ── buildGroups — estatísticas por cluster ────────────────────────────────
QVariantList BSoidWorker::buildGroups(const std::vector<RawRow>& rows,
                                      const std::vector<int>& labels, int k)
{
    struct Stats {
        int   count     = 0;
        float movNose   = 0.0f;
        float movBody   = 0.0f;
        std::unordered_map<int, int> ruleCounts;
    };
    std::vector<Stats> stats(k);

    for (size_t i = 0; i < rows.size(); ++i) {
        int c = labels[i];
        auto& s = stats[c];
        s.count++;
        s.movNose += rows[i].features[0];
        s.movBody += rows[i].features[1];
        s.ruleCounts[rows[i].ruleLabel]++;
    }

    const float total = static_cast<float>(rows.size());
    QVariantList result;

    for (int c = 0; c < k; ++c) {
        const auto& s = stats[c];
        if (s.count == 0) continue;

        int dominantRule = -1;
        int maxRuleCount = 0;
        for (const auto& [rule, cnt] : s.ruleCounts) {
            if (cnt > maxRuleCount) { maxRuleCount = cnt; dominantRule = rule; }
        }

        QVariantMap g;
        g["clusterId"]    = c;
        g["frameCount"]   = s.count;
        g["percentage"]   = static_cast<double>(s.count) / static_cast<double>(total) * 100.0;
        g["avgMovNose"]   = static_cast<double>(s.movNose / static_cast<float>(s.count));
        g["avgMovBody"]   = static_cast<double>(s.movBody / static_cast<float>(s.count));
        g["dominantRule"] = dominantRule;
        result.append(g);
    }

    // Ordena por % decrescente
    std::sort(result.begin(), result.end(), [](const QVariant& a, const QVariant& b) {
        return a.toMap()["percentage"].toDouble() > b.toMap()["percentage"].toDouble();
    });

    return result;
}
