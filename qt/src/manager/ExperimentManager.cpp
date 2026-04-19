#include "ExperimentManager.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTextStream>

// ===========================================================================
// ExperimentListModel
// ===========================================================================

ExperimentListModel::ExperimentListModel(QObject *parent)
    : QAbstractListModel(parent)
{}

int ExperimentListModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return m_names.size();
}

QVariant ExperimentListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_names.size())
        return QVariant();

    switch (role) {
    case NameRole:    return m_names.at(index.row());
    case PathRole:    return m_paths.at(index.row());
    case ContextRole: return m_contexts.at(index.row());
    case AparatoRole: return m_aparatos.at(index.row());
    default:          return QVariant();
    }
}

QHash<int, QByteArray> ExperimentListModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[NameRole]    = "name";
    roles[PathRole]    = "path";
    roles[ContextRole] = "context";
    roles[AparatoRole] = "aparato";
    return roles;
}

void ExperimentListModel::setSourceData(const QStringList &names,
                                        const QStringList &paths,
                                        const QStringList &contexts,
                                        const QStringList &aparatos)
{
    beginResetModel();
    m_allNames    = names;
    m_allPaths    = paths;
    m_allContexts = contexts;
    m_allAparatos = aparatos;
    m_names       = names;
    m_paths       = paths;
    m_contexts    = contexts;
    m_aparatos    = aparatos;
    endResetModel();
    emit countChanged();
}

void ExperimentListModel::applyFilter(const QString &query)
{
    beginResetModel();
    m_names.clear();
    m_paths.clear();
    m_contexts.clear();
    m_aparatos.clear();

    for (int i = 0; i < m_allNames.size(); ++i) {
        if (m_allNames.at(i).contains(query, Qt::CaseInsensitive)) {
            m_names.append(m_allNames.at(i));
            m_paths.append(m_allPaths.at(i));
            m_contexts.append(m_allContexts.at(i));
            m_aparatos.append(m_allAparatos.at(i));
        }
    }
    endResetModel();
    emit countChanged();
}

// ===========================================================================
// ExperimentManager
// ===========================================================================

ExperimentManager::ExperimentManager(QObject *parent)
    : QObject(parent), m_model(new ExperimentListModel(this)), m_inSearchMode(false)
{
}

ExperimentListModel *ExperimentManager::model()        const { return m_model; }
QString              ExperimentManager::activeContext() const { return m_activeContext; }

QString ExperimentManager::basePath() const
{
    // Localiza a pasta "Meus Documentos" do usuário
    QString docsPath = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    
    // Define o novo caminho unificado
    return docsPath + QStringLiteral("/MindTrace_Data/Experimentos");
}

// Varre o diretório do contexto ativo e atualiza o modelo — sempre executa.
void ExperimentManager::scanAndUpdateModel(const QString &aparatoFilter)
{
    QStringList names, paths, contexts, aparatos;

    auto checkAndAdd = [&](const QString &name, const QString &path, const QString &ctx) {
        if (paths.contains(path, Qt::CaseInsensitive)) return;

        QVariantMap meta = readMetadataFromPath(path);
        QString apa = meta["aparato"].toString();
        
        if (aparatoFilter.isEmpty() || apa == aparatoFilter) {
            names << name;
            paths << path;
            contexts << ctx;
            aparatos << apa;
        }
    };

    // 1. Pastas do diretório padrão
    const QString contextPath = basePath() + QLatin1Char('/') + m_activeContext;
    QDir dir(contextPath);
    if (dir.exists()) {
        const QFileInfoList entries = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QFileInfo &info : entries) {
            checkAndAdd(info.fileName(), info.absoluteFilePath(), m_activeContext);
        }
    }

    // 2. Experimentos em diretórios livres (registry)
    QFile regFile(basePath() + QStringLiteral("/registry.json"));
    if (regFile.open(QIODevice::ReadOnly)) {
        QJsonArray arr = QJsonDocument::fromJson(regFile.readAll()).array();
        for (const auto& v : arr) {
            QJsonObject obj = v.toObject();
            if (obj["context"].toString() == m_activeContext) {
                checkAndAdd(obj["name"].toString(), obj["path"].toString(), m_activeContext);
            }
        }
    }

    m_model->setSourceData(names, paths, contexts, aparatos);
}

void ExperimentManager::scanAndUpdateModel()
{
    scanAndUpdateModel(m_aparatoFilter);
}

void ExperimentManager::loadContext(const QString &context, const QString &aparatoFilter)
{
    m_inSearchMode = false;
    m_aparatoFilter = aparatoFilter;
    setActiveContext(context);
    scanAndUpdateModel(m_aparatoFilter);
}

bool ExperimentManager::createExperiment(const QString &name)
{
    // Delega para o método completo com colunas padrão
    QStringList defaultCols;
    defaultCols << QStringLiteral("Animal ID")
                << QStringLiteral("Grupo")
                << QStringLiteral("Sessão")
                << QStringLiteral("Vídeo");
    return createExperimentWithConfig(name, 1, defaultCols);
}

bool ExperimentManager::createExperimentWithConfig(const QString    &name,
                                                    int               animalCount,
                                                    const QStringList &columns)
{
    if (m_activeContext.isEmpty() || name.trimmed().isEmpty()) {
        emit errorOccurred(QStringLiteral("Contexto ou nome inválido."));
        return false;
    }
    if (columns.isEmpty()) {
        emit errorOccurred(QStringLiteral("Defina ao menos uma coluna."));
        return false;
    }

    const QString trimmedName = name.trimmed();
    const QString folderPath  = basePath() + QLatin1Char('/')
                                + m_activeContext + QLatin1Char('/') + trimmedName;

    QDir dir;
    if (!dir.mkpath(folderPath)) {
        emit errorOccurred(QStringLiteral("Não foi possível criar a pasta: ") + folderPath);
        return false;
    }

    // Normalize columns: ensure they match the expected NOR schema
    QStringList norms = columns;
    if (columns.size() >= 5) {
        norms[0] = QStringLiteral("Diretório do Vídeo");
        norms[1] = QStringLiteral("Animal");
        norms[2] = QStringLiteral("Campo");
        norms[3] = QStringLiteral("Dia");
        norms[4] = QStringLiteral("Par de Objetos");
        if (norms.size() > 5)
            norms[5] = QStringLiteral("Droga");
    }

    writeMetadata(folderPath, trimmedName, animalCount, norms);
    writeCsv(folderPath, norms, animalCount);

    scanAndUpdateModel();
    emit experimentCreated(trimmedName, folderPath);
    return true;
}

void ExperimentManager::setFilter(const QString &query)
{
    m_model->applyFilter(query);
}

QString ExperimentManager::experimentPath(const QString &name, const QString &context) const
{
    QString effectiveContext = context.isEmpty() ? m_activeContext : context;
    if (effectiveContext.isEmpty()) return QString();
    
    // Check registry first
    QFile regFile(basePath() + QStringLiteral("/registry.json"));
    if (regFile.open(QIODevice::ReadOnly)) {
        QJsonArray arr = QJsonDocument::fromJson(regFile.readAll()).array();
        for (int i = 0; i < arr.size(); ++i) {
            QJsonObject obj = arr[i].toObject();
            if (obj["context"].toString() == effectiveContext && obj["name"].toString() == name) {
                return obj["path"].toString();
            }
        }
    }
    
    // Default fallback
    return basePath() + QLatin1Char('/') + effectiveContext + QLatin1Char('/') + name;
}

bool ExperimentManager::deleteExperiment(const QString &name, const QString &context)
{
    const QString trimmed = name.trimmed();
    QString effectiveContext = context.isEmpty() ? m_activeContext : context;

    if (trimmed.isEmpty()) {
        emit errorOccurred(QStringLiteral("Nome inválido."));
        return false;
    }

    // Usa experimentPath() para encontrar o caminho real (padrão ou registry)
    const QString folderPath = experimentPath(trimmed, effectiveContext);
    if (folderPath.isEmpty()) {
        emit errorOccurred(QStringLiteral("Experimento não encontrado: ") + trimmed);
        return false;
    }
    QDir dir(folderPath);
    if (!dir.exists()) {
        // Pasta já não existe (excluída externamente) — limpa o registry e atualiza
        removeFromRegistry(trimmed, effectiveContext);
        refreshModel();
        emit experimentDeleted(trimmed);
        return true;
    }
    if (!dir.removeRecursively()) {
        emit errorOccurred(QStringLiteral("Não foi possível excluir (pode estar em uso): ") + trimmed);
        return false;
    }
    removeFromRegistry(trimmed, effectiveContext);
    refreshModel();
    emit experimentDeleted(trimmed);
    return true;
}

bool ExperimentManager::insertSessionResult(const QString &experimentName,
                                             const QVariantList &rows)
{
    if (rows.isEmpty()) return true;

    const QString trimmed = experimentName.trimmed();
    if (trimmed.isEmpty()) {
        emit errorOccurred(QStringLiteral("Nome de experimento vazio."));
        return false;
    }

    const QString csvPath = experimentPath(trimmed)
                            + QStringLiteral("/tracking_data.csv");

    {   // Escopo garante que QFile é *fechado* (não apenas flushed) ANTES do sinal.
        // ~QTextStream() faz flush para o buffer do QFile; ~QFile() faz flush + close
        // para o OS. Só então loadCsv() enxerga as linhas novas em disco.
        QFile file(csvPath);
        if (!file.open(QIODevice::Append | QIODevice::Text)) {
            emit errorOccurred(QStringLiteral("Não foi possível abrir o CSV: ") + csvPath);
            return false;
        }
        QTextStream out(&file);
        for (const QVariant &rowVar : rows) {
            // Aceita tanto QStringList quanto QVariantList vindos do QML
            const QStringList cols = rowVar.toStringList();
            if (!cols.isEmpty())
                out << cols.join(QLatin1Char(',')) << QLatin1Char('\n');
        }
    }   // out destruído → flush ao QFile; file destruído → close + flush ao OS

    emit sessionDataInserted(trimmed);
    return true;
}

bool ExperimentManager::insertBehaviorResult(const QString &experimentName,
                                             const QVariantList &rows)
{
    if (rows.isEmpty()) return true;

    const QString trimmed = experimentName.trimmed();
    if (trimmed.isEmpty()) {
        emit errorOccurred(QStringLiteral("Nome de experimento vazio."));
        return false;
    }

    const QString csvPath = experimentPath(trimmed)
                            + QStringLiteral("/behavior_summary.csv");

    bool isNew = !QFile::exists(csvPath);

    {
        QFile file(csvPath);
        if (!file.open(QIODevice::Append | QIODevice::Text)) {
            emit errorOccurred(QStringLiteral("Não foi possível abrir o CSV: ") + csvPath);
            return false;
        }
        
        if (isNew) {
            file.write("\xEF\xBB\xBF"); // BOM para Excel
            QTextStream header(&file);
            header << "Video,Animal,Campo,Comportamento,Tempo (s),Sessao (%)\n";
        }
        
        QTextStream out(&file);
        for (const QVariant &rowVar : rows) {
            const QStringList cols = rowVar.toStringList();
            if (!cols.isEmpty())
                out << cols.join(QLatin1Char(',')) << QLatin1Char('\n');
        }
    }

    return true;
}

bool ExperimentManager::createExperimentFull(const QString    &name,
                                               const QStringList &columns,
                                               const QString     &pair1,
                                               const QString     &pair2,
                                               const QString     &pair3,
                                               bool               includeDrug,
                                               bool               hasReactivation,
                                               const QString     &savePath,
                                               const QString     &aparato,
                                               int                numCampos,
                                               double             centroRatio,
                                               bool               hasObjectZones,
                                               int                sessionMinutes,
                                               int                sessionDays)
{
    if (m_activeContext.isEmpty() || name.trimmed().isEmpty()) {
        emit errorOccurred(QStringLiteral("Contexto ou nome inválido."));
        return false;
    }
    if (columns.isEmpty()) {
        emit errorOccurred(QStringLiteral("Defina ao menos uma coluna."));
        return false;
    }

    const QString trimmedName = name.trimmed();
    QString folderPath;
    
    if (savePath.isEmpty()) {
        folderPath = basePath() + QLatin1Char('/') + m_activeContext + QLatin1Char('/') + trimmedName;
    } else {
        folderPath = savePath.startsWith("file:///") ? savePath.mid(8) : savePath;
        folderPath += QLatin1Char('/') + trimmedName;
        
        QDir().mkpath(basePath());
        QFile regFile(basePath() + QStringLiteral("/registry.json"));
        QJsonArray arr;
        if (regFile.open(QIODevice::ReadOnly)) {
            arr = QJsonDocument::fromJson(regFile.readAll()).array();
            regFile.close();
        }
        QJsonObject newExp;
        newExp["name"] = trimmedName;
        newExp["context"] = m_activeContext;
        newExp["path"] = folderPath;
        arr.append(newExp);
        if (regFile.open(QIODevice::WriteOnly)) {
            regFile.write(QJsonDocument(arr).toJson());
        }
    }

    QDir dir;
    if (!dir.mkpath(folderPath)) {
        emit errorOccurred(QStringLiteral("Não foi possível criar a pasta: ") + folderPath);
        return false;
    }

    writeMetadata(folderPath, trimmedName, 0, columns, pair1, pair2, pair3, includeDrug, hasReactivation, aparato, numCampos, centroRatio, hasObjectZones, sessionMinutes, sessionDays);
    writeCsv(folderPath, columns, 0);

    scanAndUpdateModel();
    emit experimentCreated(trimmedName, folderPath);
    return true;
}

void ExperimentManager::loadAllContexts(const QString &aparatoFilter)
{
    m_aparatoFilter = aparatoFilter;
    QString rootPath = basePath();
    QDir base(rootPath);
    base.mkpath(rootPath);

    QStringList ctxFolders = base.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    QStringList names, paths, contexts, aparatos;

    auto checkAndAdd = [&](const QString &name, const QString &path, const QString &ctx) {
        if (paths.contains(path, Qt::CaseInsensitive)) return;

        QVariantMap meta = readMetadataFromPath(path);
        QString apa = meta["aparato"].toString();
        
        if (aparatoFilter.isEmpty() || apa == aparatoFilter) {
            names << name;
            paths << path;
            contexts << ctx;
            aparatos << apa;
        }
    };

    for (const QString &ctx : ctxFolders) {
        QDir ctxDir(rootPath + "/" + ctx);
        QFileInfoList entries = ctxDir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QFileInfo &info : entries) {
            checkAndAdd(info.fileName(), info.absoluteFilePath(), ctx);
        }
    }

    // Registry
    QFile regFile(basePath() + QStringLiteral("/registry.json"));
    if (regFile.open(QIODevice::ReadOnly)) {
        QJsonArray arr = QJsonDocument::fromJson(regFile.readAll()).array();
        for (const auto& v : arr) {
            QJsonObject obj = v.toObject();
            checkAndAdd(obj["name"].toString(), obj["path"].toString(), obj["context"].toString());
        }
    }

    m_inSearchMode = true;
    m_aparatoFilter = aparatoFilter;
    m_model->setSourceData(names, paths, contexts, aparatos);
}

void ExperimentManager::clearFilter()
{
    m_aparatoFilter = "";
    if (m_inSearchMode) {
        loadAllContexts("");
    } else {
        scanAndUpdateModel("");
    }
}

void ExperimentManager::setActiveContext(const QString &context)
{
    if (m_activeContext != context) {
        m_activeContext = context;
        emit activeContextChanged();
        
        // Se NÃO estivermos em modo de pesquisa, trocamos a sidebar para mostrar apenas esse contexto.
        // Se ESTIVERMOS em modo pesquisa, mantemos a lista global (resultados da busca).
        if (!m_inSearchMode && !m_activeContext.isEmpty()) {
            scanAndUpdateModel();
        }
    }
}

bool ExperimentManager::experimentExists(const QString &context, const QString &name) const
{
    const QString trimmedName = name.trimmed();
    if (context.isEmpty() || trimmedName.isEmpty()) return false;
    const QString folderPath = basePath() + QLatin1Char('/') + context
                               + QLatin1Char('/') + trimmedName;
    return QDir(folderPath).exists();
}

QVariantMap ExperimentManager::readMetadataFromPath(const QString &folderPath) const
{
    QVariantMap result;
    result[QStringLiteral("pair1")]           = QString();
    result[QStringLiteral("pair2")]           = QString();
    result[QStringLiteral("pair3")]           = QString();
    result[QStringLiteral("includeDrug")]     = true;
    result[QStringLiteral("hasReactivation")] = false;
    result[QStringLiteral("context")]         = QString();
    result[QStringLiteral("aparato")]         = QStringLiteral("nor");
    result[QStringLiteral("numCampos")]       = 3;
    result[QStringLiteral("centroRatio")]     = 0.5;

    QFile file(folderPath + QStringLiteral("/metadata.json"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return result;

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject())
        return result;

    const QJsonObject obj = doc.object();
    result[QStringLiteral("pair1")]           = obj[QStringLiteral("pair1")].toString();
    result[QStringLiteral("pair2")]           = obj[QStringLiteral("pair2")].toString();
    result[QStringLiteral("pair3")]           = obj[QStringLiteral("pair3")].toString();
    result[QStringLiteral("includeDrug")]     = obj[QStringLiteral("includeDrug")].toBool(true);
    result[QStringLiteral("hasReactivation")] = obj[QStringLiteral("hasReactivation")].toBool(false);
    result[QStringLiteral("context")]         = obj[QStringLiteral("context")].toString();
    result[QStringLiteral("aparato")]         = obj.contains(QStringLiteral("aparato"))
                                                ? obj[QStringLiteral("aparato")].toString()
                                                : QStringLiteral("nor");
    result[QStringLiteral("numCampos")]       = obj.contains(QStringLiteral("numCampos"))
                                                ? obj[QStringLiteral("numCampos")].toInt(3)
                                                : 3;
    result[QStringLiteral("centroRatio")]     = obj.contains(QStringLiteral("centroRatio"))
                                                ? obj[QStringLiteral("centroRatio")].toDouble(0.5)
                                                : 0.5;
    result[QStringLiteral("hasObjectZones")]  = obj.contains(QStringLiteral("hasObjectZones"))
                                                ? obj[QStringLiteral("hasObjectZones")].toBool(true)
                                                : true;
    result[QStringLiteral("sessionMinutes")] = obj.contains(QStringLiteral("sessionMinutes"))
                                                ? obj[QStringLiteral("sessionMinutes")].toInt(5)
                                                : 5;
    result[QStringLiteral("sessionDays")]    = obj.contains(QStringLiteral("sessionDays"))
                                                ? obj[QStringLiteral("sessionDays")].toInt(5)
                                                : 5;
    return result;
}

QVariantMap ExperimentManager::readMetadata(const QString &name) const
{
    QVariantMap result;
    result[QStringLiteral("pair1")]           = QString();
    result[QStringLiteral("pair2")]           = QString();
    result[QStringLiteral("pair3")]           = QString();
    result[QStringLiteral("includeDrug")]     = true;
    result[QStringLiteral("hasReactivation")] = false;
    result[QStringLiteral("context")]         = QString();
    result[QStringLiteral("aparato")]         = QStringLiteral("nor");
    result[QStringLiteral("numCampos")]       = 3;
    result[QStringLiteral("centroRatio")]     = 0.5;

    const QString path = experimentPath(name.trimmed())
                         + QStringLiteral("/metadata.json");
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return result;

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject())
        return result;

    const QJsonObject obj = doc.object();
    result[QStringLiteral("pair1")]           = obj[QStringLiteral("pair1")].toString();
    result[QStringLiteral("pair2")]           = obj[QStringLiteral("pair2")].toString();
    result[QStringLiteral("pair3")]           = obj[QStringLiteral("pair3")].toString();
    result[QStringLiteral("includeDrug")]     = obj[QStringLiteral("includeDrug")].toBool(true);
    result[QStringLiteral("hasReactivation")] = obj[QStringLiteral("hasReactivation")].toBool(false);
    result[QStringLiteral("context")]         = obj[QStringLiteral("context")].toString();
    result[QStringLiteral("aparato")]         = obj.contains(QStringLiteral("aparato"))
                                                 ? obj[QStringLiteral("aparato")].toString()
                                                 : QStringLiteral("nor");
    result[QStringLiteral("numCampos")]       = obj.contains(QStringLiteral("numCampos"))
                                                ? obj[QStringLiteral("numCampos")].toInt(3)
                                                : 3;
    result[QStringLiteral("centroRatio")]     = obj.contains(QStringLiteral("centroRatio"))
                                                ? obj[QStringLiteral("centroRatio")].toDouble(0.5)
                                                : 0.5;
    result[QStringLiteral("hasObjectZones")]  = obj.contains(QStringLiteral("hasObjectZones"))
                                                ? obj[QStringLiteral("hasObjectZones")].toBool(true)
                                                : true;
    result[QStringLiteral("sessionMinutes")] = obj.contains(QStringLiteral("sessionMinutes"))
                                                ? obj[QStringLiteral("sessionMinutes")].toInt(5)
                                                : 5;
    result[QStringLiteral("sessionDays")]    = obj.contains(QStringLiteral("sessionDays"))
                                                ? obj[QStringLiteral("sessionDays")].toInt(5)
                                                : 5;
    return result;
}

bool ExperimentManager::updatePairs(const QString &folderPath,
                                     const QString &pair1,
                                     const QString &pair2,
                                     const QString &pair3)
{
    const QString metaPath = folderPath + QStringLiteral("/metadata.json");
    QFile file(metaPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        emit errorOccurred(QStringLiteral("Não foi possível abrir metadata.json: ") + metaPath);
        return false;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    if (!doc.isObject()) {
        emit errorOccurred(QStringLiteral("metadata.json inválido: ") + metaPath);
        return false;
    }

    QJsonObject obj = doc.object();
    obj[QStringLiteral("pair1")] = pair1;
    obj[QStringLiteral("pair2")] = pair2;
    obj[QStringLiteral("pair3")] = pair3;

    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit errorOccurred(QStringLiteral("Não foi possível salvar metadata.json: ") + metaPath);
        return false;
    }
    file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    return true;
}

bool ExperimentManager::updateCentroRatio(const QString &folderPath, double ratio)
{
    const QString metaPath = folderPath + QStringLiteral("/metadata.json");
    QFile file(metaPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return false;
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    if (!doc.isObject()) return false;

    QJsonObject obj = doc.object();
    obj[QStringLiteral("centroRatio")] = ratio;

    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) return false;
    file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    return true;
}

bool ExperimentManager::saveSessionMetadata(const QString &experimentName,
                                             const QString &jsonData,
                                             const QString &nameHint)
{
    const QString folderPath = experimentPath(experimentName.trimmed());
    if (folderPath.isEmpty()) {
        emit errorOccurred(QStringLiteral("Experimento não encontrado: ") + experimentName);
        return false;
    }

    const QString sessionsDir = folderPath + QStringLiteral("/sessions");
    QDir().mkpath(sessionsDir);

    const QString timestamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd_HH-mm-ss"));
    const QString base      = nameHint.isEmpty()
                              ? QStringLiteral("session_") + timestamp
                              : QStringLiteral("session_") + nameHint + QLatin1Char('_') + timestamp;
    const QString filePath  = sessionsDir + QLatin1Char('/') + base + QStringLiteral(".json");

    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit errorOccurred(QStringLiteral("Não foi possível salvar metadados da sessão: ") + filePath);
        return false;
    }
    file.write(jsonData.toUtf8());
    return true;
}

void ExperimentManager::setExperimentReactivation(const QString &experimentName, bool hasReactivation)
{
    const QString folderPath = experimentPath(experimentName);
    const QString metaPath = folderPath + QStringLiteral("/metadata.json");
    QFile file(metaPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return;
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    
    QJsonObject obj = doc.object();
    obj[QStringLiteral("hasReactivation")] = hasReactivation;
    
    if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    }
}

void ExperimentManager::refreshModel()
{
    if (m_inSearchMode) {
        loadAllContexts(m_aparatoFilter);
    } else {
        scanAndUpdateModel();
    }
}

void ExperimentManager::removeFromRegistry(const QString &name, const QString &context)
{
    QString effectiveContext = context.isEmpty() ? m_activeContext : context;
    const QString regPath = basePath() + QStringLiteral("/registry.json");
    QFile regFile(regPath);
    if (!regFile.open(QIODevice::ReadOnly))
        return;
    QJsonArray arr = QJsonDocument::fromJson(regFile.readAll()).array();
    regFile.close();

    QJsonArray updated;
    for (int i = 0; i < arr.size(); ++i) {
        QJsonObject obj = arr[i].toObject();
        if (obj["name"].toString() == name && obj["context"].toString() == effectiveContext)
            continue; // remove esta entrada
        updated.append(obj);
    }

    if (arr.size() == updated.size())
        return; // nada removido — não reescreve

    if (regFile.open(QIODevice::WriteOnly))
        regFile.write(QJsonDocument(updated).toJson());
}

bool ExperimentManager::updateDayNames(const QString &folderPath, const QStringList &dayNames)
{
    const QString metaPath = folderPath + QStringLiteral("/metadata.json");
    QFile file(metaPath);
    if (!file.open(QIODevice::ReadOnly)) return false;
    QJsonObject meta = QJsonDocument::fromJson(file.readAll()).object();
    file.close();

    QJsonArray arr;
    for (const QString &n : dayNames) arr.append(n);
    meta[QStringLiteral("dayNames")] = arr;

    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) return false;
    file.write(QJsonDocument(meta).toJson(QJsonDocument::Indented));
    return true;
}

// ── Helpers de escrita ───────────────────────────────────────────────────────

void ExperimentManager::writeMetadata(const QString    &folderPath,
                                       const QString    &name,
                                       int               animalCount,
                                       const QStringList &columns,
                                       const QString     &pair1,
                                       const QString     &pair2,
                                       const QString     &pair3,
                                       bool               includeDrug,
                                       bool               hasReactivation,
                                       const QString     &aparato,
                                       int                numCampos,
                                       double             centroRatio,
                                       bool               hasObjectZones,
                                       int                sessionMinutes,
                                       int                sessionDays) const
{
    QJsonArray colArray;
    for (const QString &col : columns)
        colArray.append(col);

    QJsonObject meta;
    meta[QStringLiteral("name")]        = name;
    meta[QStringLiteral("context")]     = m_activeContext;
    meta[QStringLiteral("animalCount")] = animalCount;
    meta[QStringLiteral("columns")]     = colArray;
    meta[QStringLiteral("pair1")]       = pair1;
    meta[QStringLiteral("pair2")]       = pair2;
    meta[QStringLiteral("pair3")]       = pair3;
    meta[QStringLiteral("includeDrug")] = includeDrug;
    meta[QStringLiteral("hasReactivation")] = hasReactivation;
    meta[QStringLiteral("aparato")]     = aparato;
    meta[QStringLiteral("numCampos")]   = numCampos;
    meta[QStringLiteral("centroRatio")]    = centroRatio;
    meta[QStringLiteral("hasObjectZones")]  = hasObjectZones;
    meta[QStringLiteral("sessionMinutes")] = sessionMinutes;
    meta[QStringLiteral("sessionDays")]    = sessionDays;
    meta[QStringLiteral("createdAt")]   =
        QDateTime::currentDateTime().toString(Qt::ISODate);
    meta[QStringLiteral("version")]     = QStringLiteral("1.2");

    QFile file(folderPath + QStringLiteral("/metadata.json"));
    if (file.open(QIODevice::WriteOnly | QIODevice::Text))
        file.write(QJsonDocument(meta).toJson(QJsonDocument::Indented));
}

void ExperimentManager::writeCsv(const QString    &folderPath,
                                  const QStringList &columns,
                                  int               animalCount) const
{
    QFile file(folderPath + QStringLiteral("/tracking_data.csv"));
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return;

    // Adiciona assinatura BOM para o Excel não corromper acentuações ("í", "ó")
    file.write("\xEF\xBB\xBF");

    QTextStream out(&file);

    // Cabeçalhos
    out << columns.join(QLatin1Char(',')) << QLatin1Char('\n');

    // Uma linha vazia por animal
    const QString emptyRow = QString(columns.size() - 1, QLatin1Char(','));
    for (int i = 0; i < animalCount; ++i)
        out << emptyRow << QLatin1Char('\n');
}
