#include "ArenaConfigModel.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

QVariantMap ArenaConfigModel::defaultZone(int index) {
    QVariantMap zoneMap;
    zoneMap[QStringLiteral("xRatio")]      = (index % 2 == 0) ? 0.30 : 0.70;
    zoneMap[QStringLiteral("yRatio")]      = 0.50;
    zoneMap[QStringLiteral("radiusRatio")] = 0.12;
    zoneMap[QStringLiteral("objectId")]    = QString();
    return zoneMap;
}

ArenaConfigModel::ArenaConfigModel(QObject *parent) : QObject(parent) {
    for (int zoneIdx = 0; zoneIdx < 6; ++zoneIdx) m_zones.append(defaultZone(zoneIdx));
}

QString ArenaConfigModel::pairId() const { return m_pairId; }
QString ArenaConfigModel::imageUrl() const { return m_imageUrl; }
bool ArenaConfigModel::configured() const { return m_configured; }
QVariantList ArenaConfigModel::zones() const { return m_zones; }
QString ArenaConfigModel::getArenaPoints() const { return m_arenaPoints; }
QString ArenaConfigModel::getFloorPoints() const { return m_floorPoints; }

QVariantMap ArenaConfigModel::zone(int index) const {
    if (index >= 0 && index < m_zones.size()) return m_zones.at(index).toMap();
    return defaultZone(index);
}

int ArenaConfigModel::zoneCount() const { return m_zones.size(); }

/// Populates arenaPoints, floorPoints, and zones from a parsed JSON root object.
static void applyZonesFromJson(const QJsonObject &root, QString &arenaPoints, QString &floorPoints, QVariantList &zones) {
    const QString arenaPointsRaw = root.value("arenaPoints").toString();
    const QString floorPointsRaw = root.value("floorPoints").toString();
    if (!arenaPointsRaw.isEmpty()) arenaPoints = arenaPointsRaw;
    if (!floorPointsRaw.isEmpty()) floorPoints = floorPointsRaw;

    const QJsonArray zoneArray = root.value("zones").toArray();
    if (!zoneArray.isEmpty()) {
        zones.clear();
        for (const QJsonValue &zoneValue : zoneArray) {
            const QJsonObject zoneObj = zoneValue.toObject();
            QVariantMap zoneMap;
            zoneMap["xRatio"]      = zoneObj.value("xRatio").toDouble();
            zoneMap["yRatio"]      = zoneObj.value("yRatio").toDouble();
            zoneMap["radiusRatio"] = zoneObj.value("radiusRatio").toDouble();
            zoneMap["objectId"]    = zoneObj.value("objectId").toString();
            zones.append(zoneMap);
        }
    }
}

void ArenaConfigModel::loadConfig(const QString &context, const QString &expName) {
    const QString experimentDir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)
                                + "/MindTrace_Data/Experimentos/" + context + "/" + expName;
    loadConfigFromPath(experimentDir);
}

void ArenaConfigModel::loadConfigFromPath(const QString &folderPath) {
    loadConfigFromPath(folderPath, QStringLiteral(":/arena_config_referencia.json"));
}

void ArenaConfigModel::loadConfigFromPath(const QString &folderPath, const QString &referenceFile) {
    m_pairId = QString(); m_imageUrl = QString(); m_arenaPoints = QString(); m_floorPoints = QString();
    m_configured = false; m_zones.clear();
    for (int i = 0; i < 6; ++i) m_zones.append(defaultZone(i));

    const QString configPath = folderPath + "/arena_config.json";

    QFile file(configPath);
    if (!file.open(QIODevice::ReadOnly)) {
        // No saved config — load the provided reference file as a starting point
        QFile ref(referenceFile);
        if (ref.open(QIODevice::ReadOnly)) {
            QJsonObject refRoot = QJsonDocument::fromJson(ref.readAll()).object();
            applyZonesFromJson(refRoot, m_arenaPoints, m_floorPoints, m_zones);
        }
        emit configChanged();
        return;
    }

    QJsonObject root = QJsonDocument::fromJson(file.readAll()).object();
    m_pairId   = root.value("pairId").toString();
    m_imageUrl = root.value("imageUrl").toString();
    applyZonesFromJson(root, m_arenaPoints, m_floorPoints, m_zones);
    m_configured = !m_pairId.isEmpty();
    emit configChanged();
}

bool ArenaConfigModel::saveConfig(const QString &context, const QString &expName, const QString &pairId,
                                  const QString &imageUrl, const QVariantList &zones,
                                  const QString &arenaPointsJson, const QString &floorPointsJson) {
    QString folderPath = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)
                       + "/MindTrace_Data/Experimentos/" + context + "/" + expName;
    return saveConfigToPath(folderPath, pairId, imageUrl, zones, arenaPointsJson, floorPointsJson);
}

bool ArenaConfigModel::saveConfigToPath(const QString &folderPath, const QString &pairId,
                                      const QString &imageUrl, const QVariantList &zones,
                                      const QString &arenaPointsJson, const QString &floorPointsJson) {
    QDir().mkpath(folderPath);
    QJsonArray zoneArray;
    for (const QVariant &zoneVariant : zones) {
        const QVariantMap zoneMap = zoneVariant.toMap();
        QJsonObject zoneObj;
        zoneObj["xRatio"]      = zoneMap["xRatio"].toDouble();
        zoneObj["yRatio"]      = zoneMap["yRatio"].toDouble();
        zoneObj["radiusRatio"] = zoneMap["radiusRatio"].toDouble();
        zoneObj["objectId"]    = zoneMap["objectId"].toString();
        zoneArray.append(zoneObj);
    }

    QJsonObject configDoc;
    configDoc["pairId"] = pairId; configDoc["imageUrl"] = imageUrl; configDoc["zones"] = zoneArray;
    configDoc["arenaPoints"] = arenaPointsJson; configDoc["floorPoints"] = floorPointsJson;

    QFile file(folderPath + "/arena_config.json");
    if (!file.open(QIODevice::WriteOnly)) return false;
    file.write(QJsonDocument(configDoc).toJson());

    m_pairId = pairId; m_imageUrl = imageUrl; m_zones = zones;
    m_arenaPoints = arenaPointsJson; m_floorPoints = floorPointsJson;
    m_configured = !pairId.isEmpty();
    emit configChanged();
    return true;
}
