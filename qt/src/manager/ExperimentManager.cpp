#include "ExperimentManager.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <QTextStream>
#include <QUrl>

namespace {

QJsonArray loadRegistryArray(const QString& regPath)
{
    QFile regFile(regPath);
    if (!regFile.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(regFile.readAll()).array();
}

void saveRegistryArray(const QString& regPath, const QJsonArray& arr)
{
    QFile regFile(regPath);
    if (regFile.open(QIODevice::WriteOnly))
        regFile.write(QJsonDocument(arr).toJson());
}

void upsertRegistryEntry(const QString& regPath,
                         const QString& context,
                         const QString& name,
                         const QString& path)
{
    QJsonArray arr = loadRegistryArray(regPath);
    bool found = false;
    for (int entryIdx = 0; entryIdx < arr.size(); ++entryIdx) {
        QJsonObject registryEntry = arr[entryIdx].toObject();
        if (registryEntry["context"].toString() == context && registryEntry["name"].toString() == name) {
            registryEntry["path"] = path;
            arr[entryIdx] = registryEntry;
            found = true;
            break;
        }
    }
    if (!found) {
        QJsonObject registryEntry;
        registryEntry["name"] = name;
        registryEntry["context"] = context;
        registryEntry["path"] = path;
        arr.append(registryEntry);
    }
    saveRegistryArray(regPath, arr);
}

QString resolveCaseAwareFolderPath(const QString& rootDir,
                                   const QString& requestedName,
                                   bool* usedAliasPath = nullptr)
{
    QDir root(rootDir);
    root.mkpath(".");

    bool hasCaseInsensitiveMatch = false;
    bool hasExactMatch = false;
    const QStringList entries = root.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString& entry : entries) {
        if (QString::compare(entry, requestedName, Qt::CaseInsensitive) == 0) {
            hasCaseInsensitiveMatch = true;
            if (entry == requestedName)
                hasExactMatch = true;
            break;
        }
    }

    if (!hasCaseInsensitiveMatch || hasExactMatch) {
        if (usedAliasPath) *usedAliasPath = false;
        return root.filePath(requestedName);
    }

    if (usedAliasPath) *usedAliasPath = true;
    int suffix = 2;
    QString candidate;
    do {
        candidate = QStringLiteral("%1__%2").arg(requestedName).arg(suffix++);
    } while (root.exists(candidate));
    return root.filePath(candidate);
}

} // namespace

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
    case ResponsibleRole: return m_responsibles.at(index.row());
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
    roles[ResponsibleRole] = "responsible";
    return roles;
}

void ExperimentListModel::setSourceData(const QStringList &names,
                                        const QStringList &paths,
                                        const QStringList &contexts,
                                        const QStringList &aparatos,
                                        const QStringList &responsibles)
{
    beginResetModel();
    m_allNames    = names;
    m_allPaths    = paths;
    m_allContexts = contexts;
    m_allAparatos = aparatos;
    m_allResponsibles = responsibles;
    m_names       = names;
    m_paths       = paths;
    m_contexts    = contexts;
    m_aparatos    = aparatos;
    m_responsibles = responsibles;
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
    m_responsibles.clear();

    for (int i = 0; i < m_allNames.size(); ++i) {
        if (m_allNames.at(i).contains(query, Qt::CaseInsensitive)) {
            m_names.append(m_allNames.at(i));
            m_paths.append(m_allPaths.at(i));
            m_contexts.append(m_allContexts.at(i));
            m_aparatos.append(m_allAparatos.at(i));
            m_responsibles.append(m_allResponsibles.at(i));
        }
    }
    endResetModel();
    emit countChanged();
}

// ===========================================================================
// ExperimentManager
// ===========================================================================

ExperimentManager::ExperimentManager(QObject *parent)
    : QObject(parent), m_model(new ExperimentListModel(this)), m_inSearchMode(false), m_syncNetwork(new QNetworkAccessManager(this))
{
    refreshResearchers();
}

ExperimentListModel *ExperimentManager::model()        const { return m_model; }
QString              ExperimentManager::activeContext() const { return m_activeContext; }
QStringList          ExperimentManager::researcherUsers() const { return m_researcherUsers; }

QString ExperimentManager::basePath() const
{
    const QString docsPath = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    return docsPath + QStringLiteral("/MindTrace_Data/Experimentos");
}

// Scans the active context directory; always executes regardless of aparato filter.
void ExperimentManager::scanAndUpdateModel(const QString &aparatoFilter)
{
    QStringList names, paths, contexts, aparatos, responsibles;
    QHash<QString, QString> registryNameByPath;
    {
        QFile regFile(basePath() + QStringLiteral("/registry.json"));
        if (regFile.open(QIODevice::ReadOnly)) {
            const QJsonArray arr = QJsonDocument::fromJson(regFile.readAll()).array();
            for (const auto& registryValue : arr) {
                const QJsonObject registryObject = registryValue.toObject();
                if (registryObject["context"].toString() == m_activeContext) {
                    const QString regPath = registryObject["path"].toString().trimmed();
                    const QString regName = registryObject["name"].toString().trimmed();
                    if (!regPath.isEmpty() && !regName.isEmpty())
                        registryNameByPath.insert(regPath, regName);
                }
            }
        }
    }

    auto checkAndAdd = [&](const QString &name, const QString &path, const QString &ctx) {
        if (paths.contains(path, Qt::CaseInsensitive)) return;

        QVariantMap meta = readMetadataFromPath(path);
        QString apa = meta["aparato"].toString();
        QString displayName = registryNameByPath.value(path).trimmed();
        if (displayName.isEmpty())
            displayName = meta["name"].toString().trimmed();
        if (displayName.isEmpty())
            displayName = name;
        
        if (aparatoFilter.isEmpty() || apa == aparatoFilter) {
            names << displayName;
            paths << path;
            contexts << ctx;
            aparatos << apa;
            responsibles << meta["responsible_username"].toString();
        }
    };

    // 1. Standard-path subfolders.
    const QString contextPath = basePath() + QLatin1Char('/') + m_activeContext;
    QDir dir(contextPath);
    if (dir.exists()) {
        const QFileInfoList entries = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QFileInfo &info : entries) {
            checkAndAdd(info.fileName(), info.absoluteFilePath(), m_activeContext);
        }
    }

    // 2. External-path experiments from registry.
    for (auto it = registryNameByPath.cbegin(); it != registryNameByPath.cend(); ++it)
        checkAndAdd(it.value(), it.key(), m_activeContext);

    m_model->setSourceData(names, paths, contexts, aparatos, responsibles);
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
    const QStringList defaultCols = {
        QStringLiteral("Animal ID"),
        QStringLiteral("Grupo"),
        QStringLiteral("Sessão"),
        QStringLiteral("Video"),
    };
    return createExperimentWithConfig(name, 1, defaultCols);
}

bool ExperimentManager::createExperimentWithConfig(const QString    &name,
                                                    int               animalCount,
                                                    const QStringList &columns)
{
    if (m_activeContext.isEmpty() || name.trimmed().isEmpty()) {
        emit errorOccurred(QStringLiteral("Contexto ou nome invalido."));
        return false;
    }
    if (columns.isEmpty()) {
        emit errorOccurred(QStringLiteral("Defina ao menos uma coluna."));
        return false;
    }

    const QString trimmedName = name.trimmed();
    const QString contextRoot = basePath() + QLatin1Char('/') + m_activeContext;
    QString folderPath;
    if (experimentExists(m_activeContext, trimmedName)) {
        folderPath = experimentPath(trimmedName, m_activeContext);
    } else {
        bool usedAliasPath = false;
        folderPath = resolveCaseAwareFolderPath(contextRoot, trimmedName, &usedAliasPath);
        if (usedAliasPath) {
            upsertRegistryEntry(basePath() + QStringLiteral("/registry.json"),
                                m_activeContext, trimmedName, folderPath);
        }
    }

    QDir dir;
    if (!dir.mkpath(folderPath)) {
        emit errorOccurred(QStringLiteral("Nao foi possivel criar a pasta: ") + folderPath);
        return false;
    }

    writeMetadata(folderPath, trimmedName, animalCount, columns);
    writeCsv(folderPath, columns, animalCount);

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
        for (int entryIdx = 0; entryIdx < arr.size(); ++entryIdx) {
            const QJsonObject registryEntry = arr[entryIdx].toObject();
            if (registryEntry["context"].toString() == effectiveContext && registryEntry["name"].toString() == name) {
                return registryEntry["path"].toString();
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
        emit errorOccurred(QStringLiteral("Nome invalido."));
        return false;
    }

    const QString folderPath = experimentPath(trimmed, effectiveContext);
    if (folderPath.isEmpty()) {
        emit errorOccurred(QStringLiteral("Experimento nao encontrado: ") + trimmed);
        return false;
    }

    QDir dir(folderPath);
    if (!dir.exists()) {
        triggerAnimalLifecycleDeletionAudit(trimmed, folderPath, effectiveContext);
        removeFromRegistry(trimmed, effectiveContext);
        refreshModel();
        emit experimentDeleted(trimmed);
        return true;
    }

    triggerAnimalLifecycleDeletionAudit(trimmed, folderPath, effectiveContext);
    if (!dir.removeRecursively()) {
        emit errorOccurred(QStringLiteral("Nao foi possivel excluir (pode estar em uso): ") + trimmed);
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

    {   // RAII scope: ~QTextStream flushes to QFile buffer; ~QFile closes and flushes to OS.
        // Only after both destructors run does loadCsv() see the new rows on disk.
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
    }   // RAII: ~QTextStream flushes to QFile buffer; ~QFile closes and flushes to OS.

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
            file.write("\xEF\xBB\xBF"); // UTF-8 BOM for Excel
            QTextStream header(&file);
            header << "Video,Animal,Campo,Comportamento,Tempo (s),Sessão (%)\n";
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
                                               const QString     &responsibleUsername,
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
        emit errorOccurred(QStringLiteral("Contexto ou nome invalido."));
        return false;
    }
    if (columns.isEmpty()) {
        emit errorOccurred(QStringLiteral("Defina ao menos uma coluna."));
        return false;
    }

    const QString trimmedName = name.trimmed();
    QString folderPath;

    if (savePath.isEmpty()) {
        const QString contextRoot = basePath() + QLatin1Char('/') + m_activeContext;
        if (experimentExists(m_activeContext, trimmedName)) {
            folderPath = experimentPath(trimmedName, m_activeContext);
        } else {
            bool usedAliasPath = false;
            folderPath = resolveCaseAwareFolderPath(contextRoot, trimmedName, &usedAliasPath);
            if (usedAliasPath) {
                upsertRegistryEntry(basePath() + QStringLiteral("/registry.json"),
                                    m_activeContext, trimmedName, folderPath);
            }
        }
    } else {
        const QString root = savePath.startsWith("file:///") ? savePath.mid(8) : savePath;
        bool usedAliasPath = false;
        folderPath = resolveCaseAwareFolderPath(root, trimmedName, &usedAliasPath);
        Q_UNUSED(usedAliasPath)
        QDir().mkpath(basePath());
        upsertRegistryEntry(basePath() + QStringLiteral("/registry.json"),
                            m_activeContext, trimmedName, folderPath);
    }

    QDir dir;
    if (!dir.mkpath(folderPath)) {
        emit errorOccurred(QStringLiteral("Nao foi possivel criar a pasta: ") + folderPath);
        return false;
    }

    writeMetadata(folderPath, trimmedName, 0, columns, pair1, pair2, pair3, includeDrug, responsibleUsername.trimmed(), hasReactivation, aparato, numCampos, centroRatio, hasObjectZones, sessionMinutes, sessionDays);
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
    QStringList names, paths, contexts, aparatos, responsibles;
    QHash<QString, QString> registryNameByPath;
    QHash<QString, QString> registryContextByPath;
    {
        QFile regFile(basePath() + QStringLiteral("/registry.json"));
        if (regFile.open(QIODevice::ReadOnly)) {
            const QJsonArray arr = QJsonDocument::fromJson(regFile.readAll()).array();
            for (const auto& registryValue : arr) {
                const QJsonObject registryObject = registryValue.toObject();
                const QString regPath = registryObject["path"].toString().trimmed();
                const QString regName = registryObject["name"].toString().trimmed();
                const QString regCtx  = registryObject["context"].toString().trimmed();
                if (!regPath.isEmpty()) {
                    if (!regName.isEmpty()) registryNameByPath.insert(regPath, regName);
                    if (!regCtx.isEmpty())  registryContextByPath.insert(regPath, regCtx);
                }
            }
        }
    }

    auto checkAndAdd = [&](const QString &name, const QString &path, const QString &ctx) {
        if (paths.contains(path, Qt::CaseInsensitive)) return;

        QVariantMap meta = readMetadataFromPath(path);
        QString apa = meta["aparato"].toString();
        QString displayName = registryNameByPath.value(path).trimmed();
        if (displayName.isEmpty())
            displayName = meta["name"].toString().trimmed();
        if (displayName.isEmpty())
            displayName = name;
        
        if (aparatoFilter.isEmpty() || apa == aparatoFilter) {
            names << displayName;
            paths << path;
            contexts << ctx;
            aparatos << apa;
            responsibles << meta["responsible_username"].toString();
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
    for (auto it = registryNameByPath.cbegin(); it != registryNameByPath.cend(); ++it) {
        const QString regPath = it.key();
        const QString regName = it.value();
        const QString regCtx  = registryContextByPath.value(regPath);
        checkAndAdd(regName, regPath, regCtx);
    }

    m_inSearchMode = true;
    m_aparatoFilter = aparatoFilter;
    m_model->setSourceData(names, paths, contexts, aparatos, responsibles);
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
        
        // Outside search mode: refresh sidebar to this context only.
        // In search mode: keep the global search results as-is.
        if (!m_inSearchMode && !m_activeContext.isEmpty()) {
            scanAndUpdateModel();
        }
    }
}

bool ExperimentManager::experimentExists(const QString &context, const QString &name) const
{
    const QString trimmedName = name.trimmed();
    if (context.isEmpty() || trimmedName.isEmpty()) return false;

    QFile regFile(basePath() + QStringLiteral("/registry.json"));
    if (regFile.open(QIODevice::ReadOnly)) {
        const QJsonArray arr = QJsonDocument::fromJson(regFile.readAll()).array();
        for (const auto& registryValue : arr) {
            const QJsonObject registryObject = registryValue.toObject();
            if (registryObject["context"].toString() == context
                && registryObject["name"].toString() == trimmedName) {
                return true;
            }
        }
    }

    const QString contextPath = basePath() + QLatin1Char('/') + context;
    QDir dir(contextPath);
    if (!dir.exists()) return false;

    const QFileInfoList entries = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QFileInfo& info : entries) {
        const QVariantMap meta = readMetadataFromPath(info.absoluteFilePath());
        QString logicalName = meta.value("name").toString().trimmed();
        if (logicalName.isEmpty())
            logicalName = info.fileName();
        if (logicalName == trimmedName)
            return true;
    }
    return false;
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
    result[QStringLiteral("responsible_username")] = QString();
    result[QStringLiteral("numCampos")]       = 3;
    result[QStringLiteral("centroRatio")]     = 0.5;
    result[QStringLiteral("contextPatterns")] = QVariantList();

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
    result[QStringLiteral("responsible_username")] = obj[QStringLiteral("responsible_username")].toString();
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
    if (obj.contains(QStringLiteral("contextPatterns"))) {
        QVariantList patterns;
        const QJsonArray arr = obj[QStringLiteral("contextPatterns")].toArray();
        for (const QJsonValue &jsonValue : arr) patterns.append(jsonValue.toString());
        result[QStringLiteral("contextPatterns")] = patterns;
    }
    if (obj.contains(QStringLiteral("dayNames"))) {
        const QJsonArray arr = obj[QStringLiteral("dayNames")].toArray();
        QStringList dayNameList;
        for (const QJsonValue &jsonValue : arr) dayNameList.append(jsonValue.toString());
        result[QStringLiteral("dayNames")] = dayNameList;
    }
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
    result[QStringLiteral("responsible_username")] = QString();
    result[QStringLiteral("numCampos")]       = 3;
    result[QStringLiteral("centroRatio")]     = 0.5;
    result[QStringLiteral("contextPatterns")] = QVariantList();

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
    result[QStringLiteral("responsible_username")] = obj[QStringLiteral("responsible_username")].toString();
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
    if (obj.contains(QStringLiteral("contextPatterns"))) {
        QVariantList patterns;
        const QJsonArray arr = obj[QStringLiteral("contextPatterns")].toArray();
        for (const QJsonValue &jsonValue : arr) patterns.append(jsonValue.toString());
        result[QStringLiteral("contextPatterns")] = patterns;
    }
    if (obj.contains(QStringLiteral("dayNames"))) {
        const QJsonArray arr = obj[QStringLiteral("dayNames")].toArray();
        QStringList dayNameList;
        for (const QJsonValue &jsonValue : arr) dayNameList.append(jsonValue.toString());
        result[QStringLiteral("dayNames")] = dayNameList;
    }
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
        emit errorOccurred(QStringLiteral("Nao foi possivel abrir metadata.json: ") + metaPath);
        return false;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    if (!doc.isObject()) {
        emit errorOccurred(QStringLiteral("metadata.json invalido: ") + metaPath);
        return false;
    }

    QJsonObject obj = doc.object();
    obj[QStringLiteral("pair1")] = pair1;
    obj[QStringLiteral("pair2")] = pair2;
    obj[QStringLiteral("pair3")] = pair3;

    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit errorOccurred(QStringLiteral("Nao foi possivel salvar metadata.json: ") + metaPath);
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
        emit errorOccurred(QStringLiteral("Experimento nao encontrado: ") + experimentName);
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
        emit errorOccurred(QStringLiteral("Nao foi possivel salvar metadados da sessao: ") + filePath);
        return false;
    }
    file.write(jsonData.toUtf8());
    triggerAnimalLifecycleSync(experimentName.trimmed(), folderPath);
    return true;
}

QString ExperimentManager::readDotEnvValue(const QString &key) const
{
    QStringList candidates;

    const QString explicitEnvPath = qEnvironmentVariable("MINDTRACE_BACKEND_ENV_PATH").trimmed();
    if (!explicitEnvPath.isEmpty()) {
        candidates.append(explicitEnvPath);
    }

    auto appendCandidates = [&](const QString &startPath) {
        QString probe = startPath;
        for (int depth = 0; depth < 6; ++depth) {
            candidates.append(QDir(probe).filePath("animal-lifecycle-platform/backend/.env"));
            QDir upDir(probe);
            if (!upDir.cdUp()) break;
            probe = upDir.absolutePath();
        }
    };

    appendCandidates(QDir::currentPath());
    appendCandidates(QCoreApplication::applicationDirPath());
    candidates.removeDuplicates();

    for (const QString &candidate : candidates) {
        QFile file(candidate);
        if (!file.exists()) continue;
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) continue;

        while (!file.atEnd()) {
            QString line = QString::fromUtf8(file.readLine()).trimmed();
            if (line.isEmpty() || line.startsWith('#')) continue;
            if (line.startsWith("export ")) line = line.mid(7).trimmed();
            const int eq = line.indexOf('=');
            if (eq <= 0) continue;
            const QString parsedKey = line.left(eq).trimmed();
            if (parsedKey != key) continue;
            QString value = line.mid(eq + 1).trimmed();
            if ((value.startsWith('"') && value.endsWith('"'))
                || (value.startsWith('\'') && value.endsWith('\''))) {
                value = value.mid(1, value.size() - 2);
            }
            return value.trimmed();
        }
    }
    return QString();
}

QString ExperimentManager::resolveSyncSecret() const
{
    QString secret = qEnvironmentVariable("MINDTRACE_SYNC_SECRET").trimmed();
    if (!secret.isEmpty()) return secret;

    secret = qEnvironmentVariable("SYNC_SECRET").trimmed();
    if (!secret.isEmpty()) return secret;

    secret = readDotEnvValue(QStringLiteral("MINDTRACE_SYNC_SECRET"));
    if (!secret.isEmpty()) return secret;

    return readDotEnvValue(QStringLiteral("SYNC_SECRET"));
}

void ExperimentManager::refreshResearchers()
{
    const QString syncUrl = qEnvironmentVariable("MINDTRACE_SYNC_URL", "http://127.0.0.1:8000").trimmed();
    const QUrl base(syncUrl);
    if (!isSafeLocalSyncUrl(base)) {
        qWarning() << "[SYNC] URL blocked (loopback-only policy):" << syncUrl;
        return;
    }

    const QString syncSecret = resolveSyncSecret();
    if (syncSecret.isEmpty()) {
        qWarning() << "[SYNC] Sync secret missing (MINDTRACE_SYNC_SECRET/SYNC_SECRET/.env). Researcher query aborted.";
        return;
    }

    const QByteArray body;
    const QByteArray ts = QByteArray::number(QDateTime::currentSecsSinceEpoch());
    const QByteArray signature = computeHmacSha256(syncSecret.toUtf8(), ts + '\n' + body).toHex();

    QUrl endpoint(base);
    QString endpointPath = endpoint.path();
    if (endpointPath.endsWith('/')) endpointPath.chop(1);
    endpoint.setPath(endpointPath + QStringLiteral("/sync/mindtrace/researchers"));

    QNetworkRequest req(endpoint);
    req.setRawHeader("X-MindTrace-Timestamp", ts);
    req.setRawHeader("X-MindTrace-Signature", signature);
    req.setRawHeader("X-MindTrace-Client", QByteArray("mindtrace-qt"));

    QNetworkReply *reply = m_syncNetwork->get(req);
    QObject::connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray response = reply->readAll();
        if (reply->error() != QNetworkReply::NoError || httpStatus < 200 || httpStatus >= 300) {
            qWarning() << "[SYNC] Falha ao buscar pesquisadores:"
                       << "status=" << httpStatus
                       << "erro=" << reply->errorString()
                       << "resp=" << QString::fromUtf8(response.left(300));
            reply->deleteLater();
            return;
        }

        QStringList fetchedUsers;
        QHash<QString, QString> fetchedFullNames;
        const QJsonDocument doc = QJsonDocument::fromJson(response);
        if (doc.isArray()) {
            const QJsonArray arr = doc.array();
            for (const QJsonValue &researcherValue : arr) {
                const QJsonObject researcherObj = researcherValue.toObject();
                const QString username = researcherObj.value(QStringLiteral("username")).toString().trimmed();
                const QString fullName = researcherObj.value(QStringLiteral("full_name")).toString().trimmed();
                if (!username.isEmpty()) {
                    fetchedUsers.append(username);
                    fetchedFullNames.insert(username, fullName.isEmpty() ? username : fullName);
                }
            }
        }
        fetchedUsers.removeDuplicates();
        fetchedUsers.sort(Qt::CaseInsensitive);

        if (fetchedUsers != m_researcherUsers || fetchedFullNames != m_researcherFullNames) {
            m_researcherUsers = fetchedUsers;
            m_researcherFullNames = fetchedFullNames;
            emit researcherUsersChanged();
        }
        reply->deleteLater();
    });
}

QString ExperimentManager::syncTimestamp() const
{
    return QString::number(QDateTime::currentSecsSinceEpoch());
}

QString ExperimentManager::researcherFullName(const QString &username) const
{
    const QString key = username.trimmed();
    if (key.isEmpty()) return QString();
    const QString fullName = m_researcherFullNames.value(key).trimmed();
    const QString source = fullName.isEmpty() ? key : fullName;
    const QStringList parts = source.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
    if (parts.size() <= 1) return source;
    QString second = parts.last();
    if (parts.size() >= 3) {
        const QString penultimate = parts.at(parts.size() - 2).toLower();
        static const QSet<QString> particles = {
            QStringLiteral("da"), QStringLiteral("de"), QStringLiteral("do"),
            QStringLiteral("das"), QStringLiteral("dos"), QStringLiteral("del"),
            QStringLiteral("della"), QStringLiteral("van"), QStringLiteral("von")
        };
        if (particles.contains(penultimate)) {
            second = parts.at(parts.size() - 2) + QStringLiteral(" ") + parts.last();
        }
    }
    return parts.first() + QStringLiteral(" ") + second;
}

QString ExperimentManager::syncSignature(const QString &timestamp, const QString &body) const
{
    const QString syncSecret = resolveSyncSecret();
    if (syncSecret.isEmpty() || timestamp.trimmed().isEmpty()) return QString();
    const QByteArray ts = timestamp.trimmed().toUtf8();
    const QByteArray payload = body.toUtf8();
    return QString::fromUtf8(computeHmacSha256(syncSecret.toUtf8(), ts + '\n' + payload).toHex());
}

bool ExperimentManager::isSafeLocalSyncUrl(const QUrl &url) const
{
    if (!url.isValid()) return false;
    if (url.scheme().toLower() != QStringLiteral("http")) return false;
    if (!url.userName().isEmpty() || !url.password().isEmpty()) return false;

    const QString host = url.host().toLower();
    return host == QStringLiteral("127.0.0.1")
        || host == QStringLiteral("localhost")
        || host == QStringLiteral("::1");
}

QByteArray ExperimentManager::computeHmacSha256(const QByteArray &key, const QByteArray &data) const
{
    constexpr int blockSize = 64;
    QByteArray normalizedKey = key;
    if (normalizedKey.size() > blockSize) {
        normalizedKey = QCryptographicHash::hash(normalizedKey, QCryptographicHash::Sha256);
    }
    normalizedKey = normalizedKey.leftJustified(blockSize, char(0x00), true);

    QByteArray oKeyPad(blockSize, char(0x5c));
    QByteArray iKeyPad(blockSize, char(0x36));
    for (int byteIdx = 0; byteIdx < blockSize; ++byteIdx) {
        oKeyPad[byteIdx] = oKeyPad[byteIdx] ^ normalizedKey[byteIdx];
        iKeyPad[byteIdx] = iKeyPad[byteIdx] ^ normalizedKey[byteIdx];
    }

    const QByteArray inner = QCryptographicHash::hash(iKeyPad + data, QCryptographicHash::Sha256);
    return QCryptographicHash::hash(oKeyPad + inner, QCryptographicHash::Sha256);
}

void ExperimentManager::triggerAnimalLifecycleSync(const QString &experimentName, const QString &folderPath)
{
    const QString enabled = qEnvironmentVariable("MINDTRACE_SYNC_ENABLED", "0").trimmed().toLower();
    if (enabled != QStringLiteral("1") && enabled != QStringLiteral("true") && enabled != QStringLiteral("yes")) {
        return;
    }

    const QString syncUrl = qEnvironmentVariable("MINDTRACE_SYNC_URL", "http://127.0.0.1:8000").trimmed();
    const QUrl base(syncUrl);
    if (!isSafeLocalSyncUrl(base)) {
        qWarning() << "[SYNC] URL blocked (loopback-only policy):" << syncUrl;
        return;
    }

    const QString syncSecret = resolveSyncSecret();
    if (syncSecret.isEmpty()) {
        qWarning() << "[SYNC] MINDTRACE_SYNC_SECRET missing. Sync aborted.";
        return;
    }

    const QFileInfo expFolder(folderPath);
    if (!expFolder.exists() || !expFolder.isDir()) {
        qWarning() << "[SYNC] Experiment folder invalid:" << folderPath;
        return;
    }

    QJsonObject payload;
    payload["experiment_path"] = QDir::toNativeSeparators(expFolder.absoluteFilePath());
    payload["context"] = m_activeContext;
    payload["create_missing_animals"] = false;
    payload["id_cc_default"] = qEnvironmentVariable("MINDTRACE_SYNC_ID_CC_DEFAULT", "CC").trimmed();
    payload["dry_run"] = false;
    const QByteArray body = QJsonDocument(payload).toJson(QJsonDocument::Compact);

    const QByteArray ts = QByteArray::number(QDateTime::currentSecsSinceEpoch());
    const QByteArray signature = computeHmacSha256(syncSecret.toUtf8(), ts + '\n' + body).toHex();

    QUrl endpoint(base);
    QString endpointPath = endpoint.path();
    if (endpointPath.endsWith('/')) endpointPath.chop(1);
    endpoint.setPath(endpointPath + QStringLiteral("/sync/mindtrace/import-folder"));

    QNetworkRequest req(endpoint);
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setRawHeader("X-MindTrace-Timestamp", ts);
    req.setRawHeader("X-MindTrace-Signature", signature);
    req.setRawHeader("X-MindTrace-Client", QByteArray("mindtrace-qt"));

    QNetworkReply *reply = m_syncNetwork->post(req, body);
    QObject::connect(reply, &QNetworkReply::finished, this, [reply, experimentName]() {
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray response = reply->readAll();
        if (reply->error() != QNetworkReply::NoError || httpStatus < 200 || httpStatus >= 300) {
            qWarning() << "[SYNC] Sync failed for experiment" << experimentName
                       << "status=" << httpStatus
                       << "error=" << reply->errorString()
                       << "resp=" << QString::fromUtf8(response.left(300));
        } else {
            qDebug() << "[SYNC] Sync completed for experiment" << experimentName;
        }
        reply->deleteLater();
    });
}

void ExperimentManager::triggerAnimalLifecycleDeletionAudit(const QString &experimentName,
                                                            const QString &folderPath,
                                                            const QString &context)
{
    const QString enabled = qEnvironmentVariable("MINDTRACE_SYNC_ENABLED", "0").trimmed().toLower();
    if (enabled != QStringLiteral("1") && enabled != QStringLiteral("true") && enabled != QStringLiteral("yes")) {
        return;
    }

    const QString syncUrl = qEnvironmentVariable("MINDTRACE_SYNC_URL", "http://127.0.0.1:8000").trimmed();
    const QUrl base(syncUrl);
    if (!isSafeLocalSyncUrl(base)) {
        qWarning() << "[SYNC] URL blocked (loopback-only policy):" << syncUrl;
        return;
    }

    const QString syncSecret = resolveSyncSecret();
    if (syncSecret.isEmpty()) {
        qWarning() << "[SYNC] MINDTRACE_SYNC_SECRET missing. Deletion audit aborted.";
        return;
    }

    QJsonObject payload;
    payload["experiment_name"] = experimentName.trimmed();
    payload["context"] = context.trimmed();
    payload["source_path"] = QDir::toNativeSeparators(folderPath);
    const QByteArray body = QJsonDocument(payload).toJson(QJsonDocument::Compact);

    const QByteArray ts = QByteArray::number(QDateTime::currentSecsSinceEpoch());
    const QByteArray signature = computeHmacSha256(syncSecret.toUtf8(), ts + '\n' + body).toHex();

    QUrl endpoint(base);
    QString endpointPath = endpoint.path();
    if (endpointPath.endsWith('/')) endpointPath.chop(1);
    endpoint.setPath(endpointPath + QStringLiteral("/sync/mindtrace/experiment-deleted"));

    QNetworkRequest req(endpoint);
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setRawHeader("X-MindTrace-Timestamp", ts);
    req.setRawHeader("X-MindTrace-Signature", signature);
    req.setRawHeader("X-MindTrace-Client", QByteArray("mindtrace-qt"));

    QNetworkReply *reply = m_syncNetwork->post(req, body);
    QObject::connect(reply, &QNetworkReply::finished, this, [reply, experimentName]() {
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray response = reply->readAll();
        if (reply->error() != QNetworkReply::NoError || httpStatus < 200 || httpStatus >= 300) {
            qWarning() << "[SYNC] Deletion audit failed for experiment" << experimentName
                       << "status=" << httpStatus
                       << "error=" << reply->errorString()
                       << "resp=" << QString::fromUtf8(response.left(300));
        } else {
            qDebug() << "[SYNC] Deletion audit registered for experiment" << experimentName;
        }
        reply->deleteLater();
    });
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

    QJsonArray filteredArray;
    for (int entryIdx = 0; entryIdx < arr.size(); ++entryIdx) {
        const QJsonObject registryEntry = arr[entryIdx].toObject();
        if (registryEntry["name"].toString() == name && registryEntry["context"].toString() == effectiveContext)
            continue;
        filteredArray.append(registryEntry);
    }

    if (arr.size() == filteredArray.size())
        return; // nothing removed — skip rewrite

    if (regFile.open(QIODevice::WriteOnly))
        regFile.write(QJsonDocument(filteredArray).toJson());
}

bool ExperimentManager::updateDayNames(const QString &folderPath, const QStringList &dayNames)
{
    const QString metaPath = folderPath + QStringLiteral("/metadata.json");
    QFile file(metaPath);
    if (!file.open(QIODevice::ReadOnly)) return false;
    QJsonObject meta = QJsonDocument::fromJson(file.readAll()).object();
    file.close();

    QJsonArray arr;
    for (const QString &dayName : dayNames) arr.append(dayName);
    meta[QStringLiteral("dayNames")] = arr;

    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) return false;
    file.write(QJsonDocument(meta).toJson(QJsonDocument::Indented));
    return true;
}

bool ExperimentManager::updateContextPatterns(const QString &folderPath, const QVariantList &patterns)
{
    const QString metaPath = folderPath + QStringLiteral("/metadata.json");
    QFile file(metaPath);
    if (!file.open(QIODevice::ReadOnly)) return false;
    QJsonObject meta = QJsonDocument::fromJson(file.readAll()).object();
    file.close();

    QJsonArray arr;
    for (const QVariant &patternVariant : patterns) arr.append(patternVariant.toString());
    meta[QStringLiteral("contextPatterns")] = arr;

    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) return false;
    file.write(QJsonDocument(meta).toJson(QJsonDocument::Indented));
    return true;
}

// -- Write helpers ------------------------------------------------------------

void ExperimentManager::writeMetadata(const QString    &folderPath,
                                       const QString    &name,
                                       int               animalCount,
                                       const QStringList &columns,
                                       const QString     &pair1,
                                       const QString     &pair2,
                                       const QString     &pair3,
                                       bool               includeDrug,
                                       const QString     &responsibleUsername,
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
    meta[QStringLiteral("responsible_username")] = responsibleUsername;
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

    file.write("\xEF\xBB\xBF"); // UTF-8 BOM so Excel reads accented characters correctly

    QTextStream out(&file);
    out << columns.join(QLatin1Char(',')) << QLatin1Char('\n');

    const QString emptyRow = QString(columns.size() - 1, QLatin1Char(','));
    for (int animalIdx = 0; animalIdx < animalCount; ++animalIdx)
        out << emptyRow << QLatin1Char('\n');
}
