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

    const ArenaInfo &a = m_arenas.at(index.row());
    switch (role) {
    case IdRole:          return a.id;
    case NameRole:        return a.name;
    case DescriptionRole: return a.description;
    case IconRole:        return a.icon;
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

    const PairInfo &p = m_pairs.at(index.row());
    switch (role) {
    case IdRole:          return p.id;
    case NameRole:        return p.name;
    case DescriptionRole: return p.description;
    case PhaseRole:       return p.phase;
    case ObjectsRole:     return p.objects;
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

    // Arenas
    const QJsonArray arenaArray = root.value(QStringLiteral("arenas")).toArray();
    m_allArenas.reserve(arenaArray.size());
    for (const QJsonValue &v : arenaArray) {
        const QJsonObject obj = v.toObject();
        ArenaInfo a;
        a.id          = obj.value(QStringLiteral("id")).toString();
        a.name        = obj.value(QStringLiteral("name")).toString();
        a.description = obj.value(QStringLiteral("description")).toString();
        a.icon        = obj.value(QStringLiteral("icon")).toString();
        for (const QJsonValue &c : obj.value(QStringLiteral("contexts")).toArray())
            a.contexts << c.toString();
        m_allArenas.append(a);
    }

    // Pares de objetos
    const QJsonArray pairArray = root.value(QStringLiteral("objectPairs")).toArray();
    m_allPairs.reserve(pairArray.size());
    for (const QJsonValue &v : pairArray) {
        const QJsonObject obj = v.toObject();
        PairInfo p;
        p.id          = obj.value(QStringLiteral("id")).toString();
        p.name        = obj.value(QStringLiteral("name")).toString();
        p.description = obj.value(QStringLiteral("description")).toString();
        p.phase       = obj.value(QStringLiteral("phase")).toString();
        for (const QJsonValue &o : obj.value(QStringLiteral("objects")).toArray())
            p.objects << o.toString();
        m_allPairs.append(p);
    }

    // Expõe todos os pares (sem filtro)
    m_pairs->setPairs(m_allPairs);

    // Arenas: começa sem filtro (será filtrado na abertura da tela)
    m_arenas->setArenas(m_allArenas);
}

void ArenaModel::filterArenasByContext(const QString &context)
{
    if (context.isEmpty()) {
        m_arenas->setArenas(m_allArenas);
        return;
    }
    QList<ArenaInfo> filtered;
    for (const ArenaInfo &a : m_allArenas) {
        if (a.contexts.contains(context))
            filtered.append(a);
    }
    m_arenas->setArenas(filtered);
}

QString ArenaModel::eventLabels(const QString &pairId) const
{
    for (const PairInfo &p : m_allPairs) {
        if (p.id == pairId)
            return p.objects.join(QStringLiteral("  •  "));
    }
    return QString();
}

QStringList ArenaModel::objectsForPair(const QString &pairId) const
{
    for (const PairInfo &p : m_allPairs) {
        if (p.id == pairId)
            return p.objects;
    }
    return QStringList();
}
