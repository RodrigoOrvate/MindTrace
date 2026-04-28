#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QUrl>

/// High-performance QAbstractListModel for the sidebar ListView.
/// Filtering is done in-process on a QStringList — O(n) with no extra
/// allocations or proxy models, efficient for lists of hundreds of items.
class ExperimentListModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        PathRole,
        ContextRole,
        AparatoRole,
        ResponsibleRole,
    };

    explicit ExperimentListModel(QObject *parent = nullptr);

    int      rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setSourceData(const QStringList &names,
                       const QStringList &paths,
                       const QStringList &contexts,
                       const QStringList &aparatos,
                       const QStringList &responsibles);
    void applyFilter(const QString &query);

signals:
    void countChanged();

private:
    QStringList m_allNames;
    QStringList m_allPaths;
    QStringList m_allContexts;
    QStringList m_allAparatos;
    QStringList m_allResponsibles;
    QStringList m_names;   // lista filtrada — exposta ao QML
    QStringList m_paths;
    QStringList m_contexts;
    QStringList m_aparatos;
    QStringList m_responsibles;
};

/// Singleton QML object. Manages experiment creation and persistence on disk.
class ExperimentManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(ExperimentListModel* model        READ model        CONSTANT)
    Q_PROPERTY(QString activeContext             READ activeContext NOTIFY activeContextChanged)
    Q_PROPERTY(QStringList researcherUsers READ researcherUsers NOTIFY researcherUsersChanged)

public:
    explicit ExperimentManager(QObject *parent = nullptr);

    ExperimentListModel *model() const;
    QString              activeContext() const;
    QStringList          researcherUsers() const;

    // ── QML-invokable API ──────────────────────────────────────────────────
    Q_INVOKABLE void    loadContext(const QString &context, const QString &aparatoFilter = QString());

    // Simple creation (no column config — kept for backwards compatibility)
    Q_INVOKABLE bool    createExperiment(const QString &name);

    // Full creation: name + animal count (rows) + column names
    Q_INVOKABLE bool    createExperimentWithConfig(const QString    &name,
                                                   int               animalCount,
                                                   const QStringList &columns);

    Q_INVOKABLE void    setFilter(const QString &query);
    Q_INVOKABLE QString experimentPath(const QString &name, const QString &context = QString()) const;
    Q_INVOKABLE bool    deleteExperiment(const QString &name, const QString &context = QString());

    // Called at the end of the 300-s timer: inserts N rows at once into the CSV.
    // rows: list of QStringList, one per field, values in CSV column order.
    // E.g.: [["video.mp4","A1","1","1","AA","Saline"],
    //         ["video.mp4","A1","2","1","AB","Saline"],
    //         ["video.mp4","A1","3","1","AC","Saline"]]
    Q_INVOKABLE bool    insertSessionResult(const QString &experimentName,
                                            const QVariantList &rows);

    Q_INVOKABLE bool    insertBehaviorResult(const QString &experimentName,
                                             const QVariantList &rows);

    Q_INVOKABLE bool    createExperimentFull(const QString &name,
                                              const QStringList &columns,
                                              const QString &pair1,
                                              const QString &pair2,
                                              const QString &pair3,
                                              bool includeDrug,
                                              const QString &responsibleUsername,
                                              bool hasReactivation,
                                              const QString &savePath,
                                              const QString &aparato = QStringLiteral("nor"),
                                              int numCampos = 3,
                                              double centroRatio = 0.5,
                                              bool hasObjectZones = true,
                                              int sessionMinutes = 5,
                                              int sessionDays = 5);

    Q_INVOKABLE bool    updateCentroRatio(const QString &folderPath, double ratio);

    // Reads metadata.json and returns pair1/pair2/pair3/includeDrug/hasReactivation for the dashboard.
    Q_INVOKABLE QVariantMap readMetadata(const QString &name) const;

    // Persists only the pairs into the existing metadata.json (called after Arena tab edit).
    Q_INVOKABLE bool updatePairs(const QString &folderPath,
                                 const QString &pair1,
                                 const QString &pair2,
                                 const QString &pair3);

    // Updates the reactivation flag after the experiment has been created.
    Q_INVOKABLE void setExperimentReactivation(const QString &experimentName, bool hasReactivation);

    // Reads metadata.json from the full experiment folder path.
    Q_INVOKABLE QVariantMap readMetadataFromPath(const QString &folderPath) const;

    // Saves rich session metadata (bouts, distance, velocity) as JSON
    // in the "sessions/" subdirectory inside the experiment folder.
    // nameHint: descriptive prefix for the filename (e.g. "TR_A1-A2-A3")
    Q_INVOKABLE bool saveSessionMetadata(const QString &experimentName,
                                         const QString &jsonData,
                                         const QString &nameHint = QString());

    Q_INVOKABLE void    loadAllContexts(const QString &aparatoFilter = QString());

    // Clears the apparatus filter and re-syncs the model.
    Q_INVOKABLE void    clearFilter();

    // Sets m_activeContext without triggering a disk scan — used when a dashboard
    // in search mode selects an experiment from a specific context.
    Q_INVOKABLE void setActiveContext(const QString &context);

    // Returns true if the experiment folder already exists in the given context.
    Q_INVOKABLE bool experimentExists(const QString &context, const QString &name) const;

    // Re-scans the disk and updates the model (useful after external folder deletion).
    Q_INVOKABLE void refreshModel();

    // Persists dayNames into the existing experiment metadata.json.
    Q_INVOKABLE bool updateDayNames(const QString &folderPath, const QStringList &dayNames);
    // Persists visual context patterns per field (e.g. horizontal, vertical, dots...).
    Q_INVOKABLE bool updateContextPatterns(const QString &folderPath, const QVariantList &patterns);
    Q_INVOKABLE void refreshResearchers();
    Q_INVOKABLE QString researcherFullName(const QString &username) const;
    Q_INVOKABLE QString syncTimestamp() const;
    Q_INVOKABLE QString syncSignature(const QString &timestamp, const QString &body = QString()) const;

signals:
    void activeContextChanged();
    void researcherUsersChanged();
    void experimentCreated(const QString &name, const QString &path);
    void experimentDeleted(const QString &name);
    void errorOccurred(const QString &message);
    // Emitted after a successful insertSessionResult — dashboard reloads the model.
    void sessionDataInserted(const QString &experimentName);

private:
    bool    isSafeLocalSyncUrl(const QUrl &url) const;
    QByteArray computeHmacSha256(const QByteArray &key, const QByteArray &data) const;
    QString resolveSyncSecret() const;
    QString readDotEnvValue(const QString &key) const;
    void    triggerAnimalLifecycleSync(const QString &experimentName, const QString &folderPath);
    void    triggerAnimalLifecycleDeletionAudit(const QString &experimentName,
                                                const QString &folderPath,
                                                const QString &context);

    QString basePath() const;
    void    scanAndUpdateModel(const QString &aparatoFilter); 
    void    scanAndUpdateModel();
    void    removeFromRegistry(const QString &name, const QString &context = QString()); // remove entrada do registry.json
    void    writeMetadata(const QString &folderPath,
                          const QString &name,
                          int            animalCount,
                          const QStringList &columns,
                          const QString &pair1 = QString(),
                          const QString &pair2 = QString(),
                          const QString &pair3 = QString(),
                          bool           includeDrug = true,
                          const QString &responsibleUsername = QString(),
                          bool           hasReactivation = false,
                          const QString &aparato = QStringLiteral("nor"),
                          int            numCampos = 3,
                          double         centroRatio = 0.5,
                          bool           hasObjectZones = true,
                          int            sessionMinutes = 5,
                          int            sessionDays = 5) const;
    void    writeCsv(const QString &folderPath,
                     const QStringList &columns,
                     int animalCount) const;

    ExperimentListModel *m_model;
    QString              m_activeContext;
    QString              m_aparatoFilter;
    bool                 m_inSearchMode    = false;
    QStringList          m_researcherUsers;
    QHash<QString, QString> m_researcherFullNames;
    QNetworkAccessManager *m_syncNetwork;
};
