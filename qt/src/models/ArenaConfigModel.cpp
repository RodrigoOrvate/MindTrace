#include "ArenaConfigModel.h"
#include <QDebug>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QDir>

QVariantMap ArenaConfigModel::defaultZone(int index) {
    QVariantMap z;
    z[QStringLiteral("xRatio")] = (index % 2 == 0) ? 0.30 : 0.70;
    z[QStringLiteral("yRatio")] = 0.50;
    z[QStringLiteral("radiusRatio")] = 0.12;
    z[QStringLiteral("objectId")] = QString();
    return z;
}

ArenaConfigModel::ArenaConfigModel(QObject *parent) : QObject(parent) {
    for (int i = 0; i < 6; ++i) m_zones.append(defaultZone(i));
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

// Carrega zonas/paredes/chão de um QJsonObject (helper compartilhado)
static void applyZonesFromJson(const QJsonObject &root, QString &arenaPoints, QString &floorPoints, QVariantList &zones) {
    QString a = root.value("arenaPoints").toString();
    QString f = root.value("floorPoints").toString();
    if (!a.isEmpty()) arenaPoints = a;
    if (!f.isEmpty()) floorPoints = f;

    QJsonArray zArr = root.value("zones").toArray();
    if (!zArr.isEmpty()) {
        zones.clear();
        for (const auto& v : zArr) {
            QJsonObject z = v.toObject();
            QVariantMap zm;
            zm["xRatio"]      = z.value("xRatio").toDouble();
            zm["yRatio"]      = z.value("yRatio").toDouble();
            zm["radiusRatio"] = z.value("radiusRatio").toDouble();
            zm["objectId"]    = z.value("objectId").toString();
            zones.append(zm);
        }
    }
}

void ArenaConfigModel::loadConfig(const QString &context, const QString &expName) {
    QString path = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)
                 + "/MindTrace_Data/Experimentos/" + context + "/" + expName;
    loadConfigFromPath(path);
}

void ArenaConfigModel::loadConfigFromPath(const QString &folderPath) {
    loadConfigFromPath(folderPath, QStringLiteral(":/arena_config_referencia.json"));
}

void ArenaConfigModel::loadConfigFromPath(const QString &folderPath, const QString &referenceFile) {
    m_pairId = QString(); m_imageUrl = QString(); m_arenaPoints = QString(); m_floorPoints = QString();
    m_configured = false; m_zones.clear();
    for (int i = 0; i < 6; ++i) m_zones.append(defaultZone(i));

    QString path = folderPath + "/arena_config.json";

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        // Sem config salva — carrega o arquivo de referência fornecido como ponto de partida
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
    QString rootPath = folderPath;

    QDir().mkpath(rootPath);
    QJsonArray zArr;
    for (const QVariant &v : zones) {
        QVariantMap zm = v.toMap();
        QJsonObject z;
        z["xRatio"]      = zm["xRatio"].toDouble();
        z["yRatio"]      = zm["yRatio"].toDouble();
        z["radiusRatio"] = zm["radiusRatio"].toDouble();
        z["objectId"]    = zm["objectId"].toString();
        zArr.append(z);
    }

    QJsonObject root;
    root["pairId"] = pairId; root["imageUrl"] = imageUrl; root["zones"] = zArr;
    root["arenaPoints"] = arenaPointsJson; root["floorPoints"] = floorPointsJson;

    QFile file(rootPath + "/arena_config.json");
    if (!file.open(QIODevice::WriteOnly)) return false;
    file.write(QJsonDocument(root).toJson());

    m_pairId = pairId; m_imageUrl = imageUrl; m_zones = zones;
    m_arenaPoints = arenaPointsJson; m_floorPoints = floorPointsJson;
    m_configured = !pairId.isEmpty();
    emit configChanged();
    return true;
}
