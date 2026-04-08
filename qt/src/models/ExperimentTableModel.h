#pragma once

#include <QAbstractTableModel>
#include <QList>
#include <QString>
#include <QStringList>

// ---------------------------------------------------------------------------
// ExperimentTableModel
//   Modelo de tabela com Lazy Loading via canFetchMore / fetchMore.
//   Lê um CSV de linhas; carrega BATCH_SIZE linhas por vez conforme o
//   TableView rola — mantém consumo de RAM mínimo para arquivos grandes.
// ---------------------------------------------------------------------------
class ExperimentTableModel : public QAbstractTableModel
{
    Q_OBJECT

    // Caminho do CSV carregado atualmente
    Q_PROPERTY(QString sourcePath READ sourcePath NOTIFY sourcePathChanged)

    // Indica ao QML se ainda há dados a carregar
    Q_PROPERTY(bool fetchingMore READ canFetchMore NOTIFY fetchingMoreChanged)

public:
    static constexpr int BATCH_SIZE = 50;  // linhas por fetch

    explicit ExperimentTableModel(QObject *parent = nullptr);

    // QAbstractTableModel interface
    int      rowCount(const QModelIndex &parent = {}) const override;
    int      columnCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QVariant headerData(int section, Qt::Orientation orientation,
                        int role = Qt::DisplayRole) const override;
    Qt::ItemFlags flags(const QModelIndex &index) const override;
    bool setData(const QModelIndex &index, const QVariant &value,
                 int role = Qt::EditRole) override;

    // Lazy loading
    bool canFetchMore(const QModelIndex &parent = {}) const override;
    void fetchMore(const QModelIndex &parent = {}) override;

    QString sourcePath() const;

    // ── API invocável pelo QML ──────────────────────────────────────────
    Q_INVOKABLE void loadCsv(const QString &csvPath);
    Q_INVOKABLE void addRow();
    Q_INVOKABLE void removeRow(int row);
    Q_INVOKABLE bool saveCsv() const;

signals:
    void sourcePathChanged();
    void fetchingMoreChanged();

private:
    QStringList              m_headers;
    QList<QStringList>       m_loadedRows;   // linhas já no modelo
    QList<QStringList>       m_pendingRows;  // linhas aguardando fetchMore
    QString                  m_sourcePath;

    void parseCsvIntoBuffers(const QString &path);
};
