#include "ArenaModel.h"

#include <QDebug>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

// ── ArenaListModel ────────────────────────────────────────────────────────────

ArenaListModel::ArenaListModel(QObject *parent)
    : QAbstractListModel(parent)
{}

int ArenaListModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return m_arenas.size();
}

QVariant ArenaListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_arenas.size())
        return QVariant();

    const ArenaInfo &arenaItem = m_arenas.at(index.row());
    switch (role) {
    case IdRole:          return arenaItem.id;
    case NameRole:        return arenaItem.name;
    case DescriptionRole: return arenaItem.description;
    case IconRole:        return arenaItem.icon;
    default:              return QVariant();
    }
}

QHash<int, QByteArray> ArenaListModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[IdRole]          = "arenaId";
    roles[NameRole]        = "name";
    roles[DescriptionRole] = "description";
    roles[IconRole]        = "icon";
    return roles;
}

void ArenaListModel::setArenas(const QList<ArenaInfo> &arenas)
{
    beginResetModel();
    m_arenas = arenas;
    endResetModel();
    emit countChanged();
}

// ── PairListModel ─────────────────────────────────────────────────────────────

PairListModel::PairListModel(QObject *parent)
    : QAbstractListModel(parent)
{}

int PairListModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return m_pairs.size();
}

QVariant PairListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_pairs.size())
        return QVariant();

    const PairInfo &pairItem = m_pairs.at(index.row());
    switch (role) {
    case IdRole:          return pairItem.id;
    case NameRole:        return pairItem.name;
    case DescriptionRole: return pairItem.description;
    case PhaseRole:       return pairItem.phase;
    case ObjectsRole:     return pairItem.objects;
    default:              return QVariant();
    }
}

QHash<int, QByteArray> PairListModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[IdRole]          = "pairId";
    roles[NameRole]        = "name";
    roles[DescriptionRole] = "description";
    roles[PhaseRole]       = "phase";
    roles[ObjectsRole]     = "objects";
    return roles;
}

void PairListModel::setPairs(const QList<PairInfo> &pairs)
{
    beginResetModel();
    m_pairs = pairs;
    endResetModel();
    emit countChanged();
}

// ── ArenaModel ────────────────────────────────────────────────────────────────

ArenaModel::ArenaModel(QObject *parent)
    : QObject(parent)
    , m_arenas(new ArenaListModel(this))
    , m_pairs(new PairListModel(this))
{
    loadJson();
}

ArenaListModel *ArenaModel::arenas() const { return m_arenas; }
PairListModel  *ArenaModel::pairs()  const { return m_pairs; }

void ArenaModel::loadJson()
{
    QFile file(QStringLiteral(":/arenas.json"));
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "ArenaModel: não encontrou :/arenas.json";
        return;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    const QJsonObject   root = doc.object();

    const QJsonArray arenaArray = root.value(QStringLiteral("arenas")).toArray();
    m_allArenas.reserve(arenaArray.size());
    for (const QJsonValue &arenaValue : arenaArray) {
        const QJsonObject arenaObj = arenaValue.toObject();
        ArenaInfo arenaInfo;
        arenaInfo.id          = arenaObj.value(QStringLiteral("id")).toString();
        arenaInfo.name        = arenaObj.value(QStringLiteral("name")).toString();
        arenaInfo.description = arenaObj.value(QStringLiteral("description")).toString();
        arenaInfo.icon        = arenaObj.value(QStringLiteral("icon")).toString();
        for (const QJsonValue &contextValue : arenaObj.value(QStringLiteral("contexts")).toArray())
            arenaInfo.contexts << contextValue.toString();
        m_allArenas.append(arenaInfo);
    }

    const QJsonArray pairArray = root.value(QStringLiteral("objectPairs")).toArray();
    m_allPairs.reserve(pairArray.size());
    for (const QJsonValue &pairValue : pairArray) {
        const QJsonObject pairObj = pairValue.toObject();
        PairInfo pairInfo;
        pairInfo.id          = pairObj.value(QStringLiteral("id")).toString();
        pairInfo.name        = pairObj.value(QStringLiteral("name")).toString();
        pairInfo.description = pairObj.value(QStringLiteral("description")).toString();
        pairInfo.phase       = pairObj.value(QStringLiteral("phase")).toString();
        for (const QJsonValue &objectValue : pairObj.value(QStringLiteral("objects")).toArray())
            pairInfo.objects << objectValue.toString();
        m_allPairs.append(pairInfo);
    }

    m_pairs->setPairs(m_allPairs);
    m_arenas->setArenas(m_allArenas);
}

void ArenaModel::filterArenasByContext(const QString &context)
{
    if (context.isEmpty()) {
        m_arenas->setArenas(m_allArenas);
        return;
    }
    QList<ArenaInfo> filtered;
    for (const ArenaInfo &arenaInfo : m_allArenas) {
        if (arenaInfo.contexts.contains(context))
            filtered.append(arenaInfo);
    }
    m_arenas->setArenas(filtered);
}

QString ArenaModel::eventLabels(const QString &pairId) const
{
    for (const PairInfo &pairInfo : m_allPairs) {
        if (pairInfo.id == pairId)
            return pairInfo.objects.join(QStringLiteral("  •  "));
    }
    return QString();
}

QStringList ArenaModel::objectsForPair(const QString &pairId) const
{
    for (const PairInfo &pairInfo : m_allPairs) {
        if (pairInfo.id == pairId)
            return pairInfo.objects;
    }
    return QStringList();
}
