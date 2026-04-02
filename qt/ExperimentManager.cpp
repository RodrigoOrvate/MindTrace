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
    case NameRole: return m_names.at(index.row());
    case PathRole: return m_paths.at(index.row());
    default:       return QVariant();
    }
}

QHash<int, QByteArray> ExperimentListModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[NameRole] = "name";
    roles[PathRole] = "path";
    return roles;
}

void ExperimentListModel::setSourceData(const QStringList &names,
                                        const QStringList &paths)
{
    beginResetModel();
    m_allNames = names;
    m_allPaths = paths;
    m_names    = names;
    m_paths    = paths;
    endResetModel();
    emit countChanged();
}

void ExperimentListModel::applyFilter(const QString &query)
{
    beginResetModel();
    if (query.isEmpty()) {
        m_names = m_allNames;
        m_paths = m_allPaths;
    } else {
        m_names.clear();
        m_paths.clear();
        const QString lower = query.toLower();
        for (int i = 0; i < m_allNames.size(); ++i) {
            if (m_allNames.at(i).toLower().contains(lower)) {
                m_names.append(m_allNames.at(i));
                m_paths.append(m_allPaths.at(i));
            }
        }
    }
    endResetModel();
    emit countChanged();
}

// ===========================================================================
// ExperimentManager
// ===========================================================================

ExperimentManager::ExperimentManager(QObject *parent)
    : QObject(parent)
    , m_model(new ExperimentListModel(this))
{}

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
void ExperimentManager::scanAndUpdateModel()
{
    const QString contextPath = basePath() + QLatin1Char('/') + m_activeContext;
    QDir dir(contextPath);
    dir.mkpath(contextPath);

    const QStringList entries = dir.entryList(
        QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);

    QStringList names, paths;
    names.reserve(entries.size());
    paths.reserve(entries.size());
    for (const QString &entry : entries) {
        names.append(entry);
        paths.append(contextPath + QLatin1Char('/') + entry);
    }
    m_model->setSourceData(names, paths);
}

void ExperimentManager::loadContext(const QString &context)
{
    const bool changed = (m_activeContext != context);
    m_activeContext = context;
    if (changed)
        emit activeContextChanged();
    scanAndUpdateModel();
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

    writeMetadata(folderPath, trimmedName, animalCount, columns);
    // pair1/pair2/pair3/includeDrug usam defaults — criação simples pela sidebar
    writeCsv(folderPath, columns, animalCount);

    scanAndUpdateModel();
    emit experimentCreated(trimmedName, folderPath);
    return true;
}

void ExperimentManager::setFilter(const QString &query)
{
    m_model->applyFilter(query);
}

QString ExperimentManager::experimentPath(const QString &name) const
{
    if (m_activeContext.isEmpty()) return QString();
    return basePath() + QLatin1Char('/') + m_activeContext + QLatin1Char('/') + name;
}

bool ExperimentManager::deleteExperiment(const QString &name)
{
    const QString trimmed = name.trimmed();
    if (m_activeContext.isEmpty() || trimmed.isEmpty()) {
        emit errorOccurred(QStringLiteral("Nome inválido."));
        return false;
    }
    const QString folderPath = basePath() + QLatin1Char('/') + m_activeContext + QLatin1Char('/') + trimmed;
    QDir dir(folderPath);
    if (!dir.exists()) {
        emit errorOccurred(QStringLiteral("Experimento não encontrado: ") + trimmed);
        return false;
    }
    if (!dir.removeRecursively()) {
        emit errorOccurred(QStringLiteral("Não foi possível excluir: ") + trimmed);
        return false;
    }
    scanAndUpdateModel();
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

    emit sessionDataInserted(trimmed);
    return true;
}

bool ExperimentManager::createExperimentFull(const QString    &name,
                                              const QStringList &columns,
                                              const QString     &pair1,
                                              const QString     &pair2,
                                              const QString     &pair3,
                                              bool               includeDrug)
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

    writeMetadata(folderPath, trimmedName, 0, columns, pair1, pair2, pair3, includeDrug);
    writeCsv(folderPath, columns, 0);

    scanAndUpdateModel();
    emit experimentCreated(trimmedName, folderPath);
    return true;
}

void ExperimentManager::loadAllContexts()
{
    QDir base(basePath());
    base.mkpath(base.path());

    const QStringList contexts = base.entryList(
        QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);

    QStringList names, paths;
    for (const QString &ctx : contexts) {
        const QString ctxPath = basePath() + QLatin1Char('/') + ctx;
        QDir ctxDir(ctxPath);
        const QStringList entries = ctxDir.entryList(
            QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QString &entry : entries) {
            names.append(entry);
            paths.append(ctxPath + QLatin1Char('/') + entry);
        }
    }
    m_model->setSourceData(names, paths);
}

void ExperimentManager::setActiveContext(const QString &context)
{
    if (m_activeContext != context) {
        m_activeContext = context;
        emit activeContextChanged();
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
    result[QStringLiteral("pair1")]       = QString();
    result[QStringLiteral("pair2")]       = QString();
    result[QStringLiteral("pair3")]       = QString();
    result[QStringLiteral("includeDrug")] = true;
    result[QStringLiteral("context")]     = QString();

    QFile file(folderPath + QStringLiteral("/metadata.json"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return result;

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject())
        return result;

    const QJsonObject obj = doc.object();
    result[QStringLiteral("pair1")]       = obj[QStringLiteral("pair1")].toString();
    result[QStringLiteral("pair2")]       = obj[QStringLiteral("pair2")].toString();
    result[QStringLiteral("pair3")]       = obj[QStringLiteral("pair3")].toString();
    result[QStringLiteral("includeDrug")] = obj[QStringLiteral("includeDrug")].toBool(true);
    result[QStringLiteral("context")]     = obj[QStringLiteral("context")].toString();
    return result;
}

QVariantMap ExperimentManager::readMetadata(const QString &name) const
{
    // Valores padrão caso o arquivo não exista ou não tenha os campos
    QVariantMap result;
    result[QStringLiteral("pair1")]       = QString();
    result[QStringLiteral("pair2")]       = QString();
    result[QStringLiteral("pair3")]       = QString();
    result[QStringLiteral("includeDrug")] = true;
    result[QStringLiteral("context")]     = QString();

    const QString path = experimentPath(name.trimmed())
                         + QStringLiteral("/metadata.json");
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return result;

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject())
        return result;

    const QJsonObject obj = doc.object();
    result[QStringLiteral("pair1")]       = obj[QStringLiteral("pair1")].toString();
    result[QStringLiteral("pair2")]       = obj[QStringLiteral("pair2")].toString();
    result[QStringLiteral("pair3")]       = obj[QStringLiteral("pair3")].toString();
    result[QStringLiteral("includeDrug")] = obj[QStringLiteral("includeDrug")].toBool(true);
    result[QStringLiteral("context")]     = obj[QStringLiteral("context")].toString();
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

// ── Helpers de escrita ───────────────────────────────────────────────────────

void ExperimentManager::writeMetadata(const QString    &folderPath,
                                       const QString    &name,
                                       int               animalCount,
                                       const QStringList &columns,
                                       const QString     &pair1,
                                       const QString     &pair2,
                                       const QString     &pair3,
                                       bool               includeDrug) const
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
    meta[QStringLiteral("createdAt")]   =
        QDateTime::currentDateTime().toString(Qt::ISODate);
    meta[QStringLiteral("version")]     = QStringLiteral("1.1");

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

    QTextStream out(&file);

    // Cabeçalhos
    out << columns.join(QLatin1Char(',')) << QLatin1Char('\n');

    // Uma linha vazia por animal
    const QString emptyRow = QString(columns.size() - 1, QLatin1Char(','));
    for (int i = 0; i < animalCount; ++i)
        out << emptyRow << QLatin1Char('\n');
}
