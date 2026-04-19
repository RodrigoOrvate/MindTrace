#include "ExperimentTableModel.h"

#include <QFile>
#include <QFileInfo>
#include <QTextStream>
#include <QDateTime>
#include <QtGlobal>
#include <QProcess>
#include <QCoreApplication>
#include <QDir>

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Minimal CSV parser (no quoted comma support).
static QStringList parseCsvLine(const QString &line)
{
    return line.split(QLatin1Char(','));
}

struct ExportTheme
{
    QString aparatoLabel;
    QString accent;
    QString headerBg;
    QString headerText;
};

static ExportTheme detectTheme(const QStringList &headers)
{
    if (headers.contains(QStringLiteral("Par de Objetos"))) {
        return {QStringLiteral("Reconhecimento de Objetos (NOR)"),
                QStringLiteral("#ab3d4c"), QStringLiteral("#fcecef"), QStringLiteral("#611824")};
    }
    if (headers.contains(QStringLiteral("Latência (s)")) || headers.contains(QStringLiteral("Tempo Plataforma (s)"))) {
        return {QStringLiteral("Esquiva Inibitória (EI)"),
                QStringLiteral("#2f7a4b"), QStringLiteral("#eaf7ef"), QStringLiteral("#0f4d27")};
    }
    if (headers.contains(QStringLiteral("Duração (min)"))) {
        return {QStringLiteral("Comportamento Complexo (CC)"),
                QStringLiteral("#7a3dab"), QStringLiteral("#f2eafc"), QStringLiteral("#3f1d61")};
    }
    if (headers.contains(QStringLiteral("Distância Total (m)"))) {
        return {QStringLiteral("Campo Aberto (CA)"),
                QStringLiteral("#3d7aab"), QStringLiteral("#eaf3fb"), QStringLiteral("#153e5c")};
    }

    return {QStringLiteral("Dados de Experimento"),
            QStringLiteral("#4b5563"), QStringLiteral("#f3f4f6"), QStringLiteral("#111827")};
}

static bool isNumericColumn(const QString &header)
{
    const QString h = header.toLower();
    return h.contains(QStringLiteral("(m)"))
        || h.contains(QStringLiteral("(m/s)"))
        || h.contains(QStringLiteral("(s)"))
        || h.contains(QStringLiteral("(min)"))
        || h.contains(QStringLiteral("distância"))
        || h.contains(QStringLiteral("velocidade"))
        || h.contains(QStringLiteral("latência"))
        || h.contains(QStringLiteral("bouts"))
        || h == QStringLiteral("di")
        || h == QStringLiteral("campo");
}

static bool isIntegerColumn(const QString &header)
{
    const QString h = header.toLower();
    return h == QStringLiteral("campo") || h.contains(QStringLiteral("bouts"));
}

// Formata número usando vírgula como separador decimal (compatível com Excel pt-BR)
static QString formatNumericValue(const QString &value, bool integerFormat)
{
    bool ok = false;
    const double num = value.trimmed().toDouble(&ok);
    if (!ok) return value;

    if (integerFormat)
        return QString::number(static_cast<int>(qRound64(num)));
    // Usa vírgula como separador decimal para Excel pt-BR
    QString formatted = QString::number(num, 'f', 3);
    formatted.replace(QLatin1Char('.'), QLatin1Char(','));
    return formatted;
}

// ===========================================================================
// ExperimentTableModel
// ===========================================================================

ExperimentTableModel::ExperimentTableModel(QObject *parent)
    : QAbstractTableModel(parent)
{}

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
        || index.row() >= m_loadedRows.size()
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
    return section + 1;
}

Qt::ItemFlags ExperimentTableModel::flags(const QModelIndex &index) const
{
    if (!index.isValid()) return Qt::NoItemFlags;
    return Qt::ItemIsEnabled | Qt::ItemIsSelectable | Qt::ItemIsEditable;
}

bool ExperimentTableModel::setData(const QModelIndex &index,
                                   const QVariant &value,
                                   int role)
{
    if (role != Qt::EditRole || !index.isValid()) return false;
    if (index.row() >= m_loadedRows.size()) return false;

    while (m_loadedRows[index.row()].size() <= index.column())
        m_loadedRows[index.row()].append(QString());

    m_loadedRows[index.row()][index.column()] = value.toString();
    emit dataChanged(index, index, {Qt::DisplayRole, Qt::EditRole});
    return true;
}

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

QString ExperimentTableModel::sourcePath() const
{
    return m_sourcePath;
}

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

    fetchMore({});
    emit fetchingMoreChanged();
}

void ExperimentTableModel::addRow()
{
    const int row = m_loadedRows.size();
    beginInsertRows({}, row, row);

    QStringList emptyRow;
    for (int i = 0; i < m_headers.size(); ++i)
        emptyRow.append(QString());

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
    if (m_headers.isEmpty() || destPath.isEmpty()) return false;

    QFile file(destPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;

    file.write("\xEF\xBB\xBF");
    QTextStream out(&file);

    // Escreve cabeçalhos puros
    out << m_headers.join(QLatin1Char(',')) << '\n';

    // Escreve linhas puras
    QList<QStringList> allRows = m_loadedRows + m_pendingRows;
    for (const QStringList &row : allRows) {
        out << row.join(QLatin1Char(',')) << '\n';
    }

    file.close();

#if defined(Q_OS_WIN)
    QString scriptPath = QDir::cleanPath(QCoreApplication::applicationDirPath() + "/../../formatar_mindtrace.py");
#else
    QString scriptPath = QDir::cleanPath(QCoreApplication::applicationDirPath() + "/../formatar_mindtrace.py");
#endif
    
    // Chama o Python que transformará este CSV puro no arquivo final .xlsx com abas
    QProcess::startDetached(QStringLiteral("python"), QStringList() << scriptPath << destPath);

    return true;
}

void ExperimentTableModel::parseCsvIntoBuffers(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;

    QTextStream in(&file);

    if (!in.atEnd()) {
        beginResetModel();
        m_headers = parseCsvLine(in.readLine().trimmed());
        endResetModel();
    }

    while (!in.atEnd()) {
        const QString line = in.readLine().trimmed();
        if (!line.isEmpty())
            m_pendingRows.append(parseCsvLine(line));
    }
}
