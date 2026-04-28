#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

/// Loads and saves per-experiment arena configuration (zones, floor polygon, image).
class ArenaConfigModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString  pairId     READ pairId     NOTIFY configChanged)
    Q_PROPERTY(QString  imageUrl   READ imageUrl   NOTIFY configChanged)
    Q_PROPERTY(bool     configured READ configured NOTIFY configChanged)
    Q_PROPERTY(QVariantList zones   READ zones     NOTIFY configChanged)

public:
    explicit ArenaConfigModel(QObject *parent = nullptr);

    QString      pairId()     const;
    QString      imageUrl()   const;
    bool         configured() const;
    QVariantList zones()      const;

    /// Load arena config (zones, points) by context name and experiment name.
    Q_INVOKABLE void loadConfig(const QString &context, const QString &expName);

    /// Load arena config from an absolute folder path.
    /// Falls back to arena_config_referencia.json (NOR/CA/CC default).
    Q_INVOKABLE void loadConfigFromPath(const QString &folderPath);
    /// Overload: specify a custom reference file (e.g. EI uses its own file).
    Q_INVOKABLE void loadConfigFromPath(const QString &folderPath, const QString &referenceFile);

    /// Save current config by context + experiment name.
    Q_INVOKABLE bool saveConfig(const QString &context, const QString &expName, const QString &pairId,
                                const QString &imageUrl, const QVariantList &zones,
                                const QString &arenaPointsJson, const QString &floorPointsJson);

    /// Save config to an absolute folder path.
    Q_INVOKABLE bool saveConfigToPath(const QString &folderPath, const QString &pairId,
                                      const QString &imageUrl, const QVariantList &zones,
                                      const QString &arenaPointsJson, const QString &floorPointsJson);

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