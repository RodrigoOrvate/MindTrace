#include "ExperimentTableModel.h"

#include <QFile>
#include <QTextStream>

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Parser CSV mínimo (sem suporte a aspas com vírgulas — suficiente para
// dados de experimentos). Substitua por um parser completo se necessário.
static QStringList parseCsvLine(const QString &line)
{
    return line.split(QLatin1Char(','));
}

// ===========================================================================
// ExperimentTableModel
// ===========================================================================

ExperimentTableModel::ExperimentTableModel(QObject *parent)
    : QAbstractTableModel(parent)
{}

// ── QAbstractTableModel interface ──────────────────────────────────────────

int ExperimentTableModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return m_loadedRows.size();
}

int ExperimentTableModel::columnCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return m_headers.size();
}

QVariant ExperimentTableModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid()
        || index.row()    >= m_loadedRows.size()
        || index.column() >= m_headers.size())
        return {};

    if (role == Qt::DisplayRole || role == Qt::EditRole)
        return m_loadedRows.at(index.row()).value(index.column());

    return {};
}

QVariant ExperimentTableModel::headerData(int section,
                                          Qt::Orientation orientation,
                                          int role) const
{
    if (role != Qt::DisplayRole) return {};
    if (orientation == Qt::Horizontal)
        return m_headers.value(section);
    return section + 1;  // número da linha (1-based)
}

Qt::ItemFlags ExperimentTableModel::flags(const QModelIndex &index) const
{
    if (!index.isValid()) return Qt::NoItemFlags;
    return Qt::ItemIsEnabled | Qt::ItemIsSelectable | Qt::ItemIsEditable;
}

bool ExperimentTableModel::setData(const QModelIndex &index,
                                   const QVariant   &value,
                                   int               role)
{
    if (role != Qt::EditRole || !index.isValid()) return false;
    if (index.row() >= m_loadedRows.size()) return false;

    // Garante que a linha tenha colunas suficientes
    while (m_loadedRows[index.row()].size() <= index.column())
        m_loadedRows[index.row()].append(QString());

    m_loadedRows[index.row()][index.column()] = value.toString();
    emit dataChanged(index, index, {Qt::DisplayRole, Qt::EditRole});
    return true;
}

// ── Lazy loading ────────────────────────────────────────────────────────────

bool ExperimentTableModel::canFetchMore(const QModelIndex &parent) const
{
    if (parent.isValid()) return false;
    return !m_pendingRows.isEmpty();
}

void ExperimentTableModel::fetchMore(const QModelIndex &parent)
{
    if (parent.isValid() || m_pendingRows.isEmpty()) return;

    const int batch = qMin(BATCH_SIZE, m_pendingRows.size());
    const int first = m_loadedRows.size();

    beginInsertRows({}, first, first + batch - 1);
    for (int i = 0; i < batch; ++i)
        m_loadedRows.append(m_pendingRows.takeFirst());
    endInsertRows();

    emit fetchingMoreChanged();
}

// ── API QML ────────────────────────────────────────────────────────────────

QString ExperimentTableModel::sourcePath() const { return m_sourcePath; }

void ExperimentTableModel::loadCsv(const QString &csvPath)
{
    beginResetModel();
    m_headers.clear();
    m_loadedRows.clear();
    m_pendingRows.clear();
    m_sourcePath = csvPath;
    endResetModel();
    emit sourcePathChanged();

    parseCsvIntoBuffers(csvPath);

    // Carrega o primeiro batch imediatamente
    fetchMore({});
    emit fetchingMoreChanged();
}

void ExperimentTableModel::addRow()
{
    const int row = m_loadedRows.size();
    beginInsertRows({}, row, row);

    QStringList emptyRow;
    for (int i = 0; i < m_headers.size(); ++i) {
        emptyRow.append(QString());
    }
    
    m_loadedRows.append(emptyRow);
    endInsertRows();
}

void ExperimentTableModel::removeRow(int row)
{
    if (row < 0 || row >= m_loadedRows.size()) return;
    beginRemoveRows({}, row, row);
    m_loadedRows.removeAt(row);
    endRemoveRows();
}

bool ExperimentTableModel::saveCsv() const
{
    if (m_sourcePath.isEmpty()) return false;

    QFile file(m_sourcePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;

    QTextStream out(&file);
    out << m_headers.join(QLatin1Char(',')) << '\n';
    for (const QStringList &row : m_loadedRows)
        out << row.join(QLatin1Char(',')) << '\n';

    return true;
}

bool ExperimentTableModel::exportCsv(const QString &destPath) const
{
    if (m_headers.isEmpty()) return false;

    QFile file(destPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;

    // BOM para abrir direto no Excel sem problemas de codificação
    file.write("\xEF\xBB\xBF");

    QTextStream out(&file);
    out << m_headers.join(QLatin1Char(',')) << '\n';
    for (const QStringList &row : m_loadedRows)
        out << row.join(QLatin1Char(',')) << '\n';
    // Também exporta as linhas pendentes (não carregadas pela UI ainda)
    for (const QStringList &row : m_pendingRows)
        out << row.join(QLatin1Char(',')) << '\n';

    return true;
}

// ── Privado ─────────────────────────────────────────────────────────────────

void ExperimentTableModel::parseCsvIntoBuffers(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;

    QTextStream in(&file);

    // Primeira linha = cabeçalhos
    if (!in.atEnd()) {
        beginResetModel();
        m_headers = parseCsvLine(in.readLine().trimmed());
        endResetModel();
    }

    // Restante vai para m_pendingRows — serão buscados sob demanda
    while (!in.atEnd()) {
        const QString line = in.readLine().trimmed();
        if (!line.isEmpty())
            m_pendingRows.append(parseCsvLine(line));
    }
}
