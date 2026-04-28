#pragma once

#include <QAbstractListModel>
#include <QObject>
#include <QStringList>

/// Static arena descriptor loaded from arenas.json.
struct ArenaInfo {
    QString     id;
    QString     name;
    QString     description;
    QString     icon;
    QStringList contexts;   // e.g. {"Padrão"} ou {"Contextual"}
};

/// Object-pair descriptor used for NOR experiment configuration.
struct PairInfo {
    QString     id;
    QString     name;
    QString     description;
    QString     phase;      // "Treino" ou "Teste"
    QStringList objects;    // IDs dos eventos, e.g. {"OBJA","OBJB"}
};

/// List of arenas filtered by the active context.
class ArenaListModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles { IdRole = Qt::UserRole + 1, NameRole, DescriptionRole, IconRole };

    explicit ArenaListModel(QObject *parent = nullptr);

    int      rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setArenas(const QList<ArenaInfo> &arenas);

signals:
    void countChanged();

private:
    QList<ArenaInfo> m_arenas;
};

/// Complete list of object pairs — no filtering, all pairs available.
class PairListModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        DescriptionRole,
        PhaseRole,
        ObjectsRole     // QStringList com os IDs dos eventos
    };

    explicit PairListModel(QObject *parent = nullptr);

    int      rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setPairs(const QList<PairInfo> &pairs);

signals:
    void countChanged();

private:
    QList<PairInfo> m_pairs;
};

/// Singleton QML object. Loads arenas.json (embedded in .qrc) and exposes the list models.
class ArenaModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(ArenaListModel* arenas READ arenas CONSTANT)
    Q_PROPERTY(PairListModel*  pairs  READ pairs  CONSTANT)

public:
    explicit ArenaModel(QObject *parent = nullptr);

    ArenaListModel *arenas() const;
    PairListModel  *pairs()  const;

    // Aplica filtro de contexto na ArenaListModel (chame ao entrar na tela).
    Q_INVOKABLE void filterArenasByContext(const QString &context);

    // Retorna string formatada dos eventos para exibição, ex.: "OBJA  •  OBJB"
    Q_INVOKABLE QString     eventLabels(const QString &pairId) const;

    // Retorna lista de IDs dos objetos para um par, ex.: ["OBJA","OBJB"]
    Q_INVOKABLE QStringList objectsForPair(const QString &pairId) const;

private:
    ArenaListModel   *m_arenas;
    PairListModel    *m_pairs;
    QList<ArenaInfo>  m_allArenas;
    QList<PairInfo>   m_allPairs;

    void loadJson();
};
