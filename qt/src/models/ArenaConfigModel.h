#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QString>

class ArenaConfigModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString  pairId     READ pairId     NOTIFY configChanged)
    Q_PROPERTY(QString  imageUrl   READ imageUrl   NOTIFY configChanged)
    Q_PROPERTY(bool     configured READ configured NOTIFY configChanged)

public:
    explicit ArenaConfigModel(QObject *parent = nullptr);

    QString pairId()     const;
    QString imageUrl()   const;
    bool    configured() const;

    // ── API invocável pelo QML ──────────────────────────────────────────
    // Adicionado 'context' aqui para bater com o C++
    Q_INVOKABLE void loadConfig(const QString &context, const QString &expName);

    Q_INVOKABLE bool saveConfig(const QString &context,
                                const QString &expName,
                                const QString &pairId,
                                const QString &imageUrl,
                                const QVariantList &zones,
                                const QString &arenaPointsJson = "",
                                const QString &floorPointsJson = "");

    Q_INVOKABLE QString     getArenaPoints() const;
    Q_INVOKABLE QString     getFloorPoints() const;

    Q_INVOKABLE QVariantMap zone(int index) const;
    Q_INVOKABLE int         zoneCount() const;

signals:
    void configChanged();

private:
    QString      m_pairId;
    QString      m_imageUrl;
    QString      m_arenaPoints; 
    QString      m_floorPoints;
    bool         m_configured = false;
    QVariantList m_zones;

    static QVariantMap defaultZone(int index);
};