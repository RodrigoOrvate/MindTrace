#pragma once

#include <QAbstractListModel>
#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QStringList>

// ---------------------------------------------------------------------------
// ExperimentListModel
//   QAbstractListModel de alta performance para o ListView da sidebar.
//   A filtragem é feita in-process sobre um QStringList — O(n) sem alocações
//   extras nem proxies adicionais para listas de centenas de itens.
// ---------------------------------------------------------------------------
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
    };

    explicit ExperimentListModel(QObject *parent = nullptr);

    int      rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setSourceData(const QStringList &names, const QStringList &paths, const QStringList &contexts, const QStringList &aparatos);
    void applyFilter(const QString &query);

signals:
    void countChanged();

private:
    QStringList m_allNames;
    QStringList m_allPaths;
    QStringList m_allContexts;
    QStringList m_allAparatos;
    QStringList m_names;   // lista filtrada — exposta ao QML
    QStringList m_paths;
    QStringList m_contexts;
    QStringList m_aparatos;
};

// ---------------------------------------------------------------------------
// ExperimentManager
//   Singleton QML. Gerencia criação/leitura de experimentos em disco.
// ---------------------------------------------------------------------------
class ExperimentManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(ExperimentListModel* model        READ model        CONSTANT)
    Q_PROPERTY(QString activeContext             READ activeContext NOTIFY activeContextChanged)

public:
    explicit ExperimentManager(QObject *parent = nullptr);

    ExperimentListModel *model() const;
    QString              activeContext() const;

    // ── API invocável pelo QML ──────────────────────────────────────────────
    Q_INVOKABLE void    loadContext(const QString &context, const QString &aparatoFilter = QString());

    // Criação simples (sem configuração de colunas — mantido por compatibilidade)
    Q_INVOKABLE bool    createExperiment(const QString &name);

    // Criação completa: nome + quantidade de animais (linhas) + nomes das colunas
    Q_INVOKABLE bool    createExperimentWithConfig(const QString    &name,
                                                   int               animalCount,
                                                   const QStringList &columns);

    Q_INVOKABLE void    setFilter(const QString &query);
    Q_INVOKABLE QString experimentPath(const QString &name, const QString &context = QString()) const;
    Q_INVOKABLE bool    deleteExperiment(const QString &name, const QString &context = QString());

    // Chamado ao fim do timer de 300 s: insere N linhas de uma vez no CSV.
    // rows: lista de QStringList, uma por campo, valores na ordem das colunas do CSV.
    // Ex.: [["video.mp4","A1","1","1","AA","Salina"],
    //        ["video.mp4","A1","2","1","AB","Salina"],
    //        ["video.mp4","A1","3","1","AC","Salina"]]
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
                                              bool hasReactivation,
                                              const QString &savePath,
                                              const QString &aparato = QStringLiteral("nor"),
                                              int numCampos = 3,
                                              double centroRatio = 0.5,
                                              bool hasObjectZones = true);

    Q_INVOKABLE bool    updateCentroRatio(const QString &folderPath, double ratio);

    // Lê metadata.json e retorna pair1/pair2/pair3/includeDrug/hasReactivation para o dashboard.
    Q_INVOKABLE QVariantMap readMetadata(const QString &name) const;

    // Persiste apenas os pares no metadata.json existente (chamado após edição na tab Arena).
    Q_INVOKABLE bool updatePairs(const QString &folderPath,
                                 const QString &pair1,
                                 const QString &pair2,
                                 const QString &pair3);

    // Altera a flag de reativação após o experimento ter sido criado
    Q_INVOKABLE void setExperimentReactivation(const QString &experimentName, bool hasReactivation);

    // Lê metadata.json a partir do path completo da pasta do experimento.
    Q_INVOKABLE QVariantMap readMetadataFromPath(const QString &folderPath) const;

    // Salva metadados ricos da sessão (bouts, distância, velocidade) como JSON
    // no subdiretório "sessions/" dentro da pasta do experimento.
    // nameHint: prefixo descritivo para o nome do arquivo (ex: "TR_A1-A2-A3")
    Q_INVOKABLE bool saveSessionMetadata(const QString &experimentName,
                                         const QString &jsonData,
                                         const QString &nameHint = QString());

    Q_INVOKABLE void    loadAllContexts(const QString &aparatoFilter = QString());

    // Limpa o filtro de aparato e re-sincroniza o modelo.
    Q_INVOKABLE void    clearFilter();

    // Define m_activeContext sem disparar scan — usado quando o dashboard
    // em search mode seleciona um experimento de um contexto específico.
    Q_INVOKABLE void setActiveContext(const QString &context);

    // Retorna true se a pasta do experimento já existe no contexto dado.
    Q_INVOKABLE bool experimentExists(const QString &context, const QString &name) const;

    // Re-varre o disco e atualiza o modelo (útil após exclusão externa de pasta).
    Q_INVOKABLE void refreshModel();

signals:
    void activeContextChanged();
    void experimentCreated(const QString &name, const QString &path);
    void experimentDeleted(const QString &name);
    void errorOccurred(const QString &message);
    // Emitido após insertSessionResult bem-sucedido — dashboard recarrega o modelo.
    void sessionDataInserted(const QString &experimentName);

private:
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
                          bool           hasReactivation = false,
                          const QString &aparato = QStringLiteral("nor"),
                          int            numCampos = 3,
                          double         centroRatio = 0.5,
                          bool           hasObjectZones = true) const;
    void    writeCsv(const QString &folderPath,
                     const QStringList &columns,
                     int animalCount) const;

    ExperimentListModel *m_model;
    QString              m_activeContext;
    QString              m_aparatoFilter;
    bool                 m_inSearchMode;
};
