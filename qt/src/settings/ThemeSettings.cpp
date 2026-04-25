#include "ThemeSettings.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QFile>
#include <QStandardPaths>
#include <QDir>

ThemeSettings::ThemeSettings(QObject *parent)
    : QObject(parent) {}

QString ThemeSettings::getSettingsPath() {
    QString appDataPath = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QString settingsFile = appDataPath + "/mindtrace_settings.json";
    QDir().mkpath(appDataPath);
    return settingsFile;
}

QJsonObject ThemeSettings::loadSettingsFile() {
    QString filePath = getSettingsPath();
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        return QJsonObject(); // Return empty if file doesn't exist
    }
    QByteArray data = file.readAll();
    file.close();
    return QJsonDocument::fromJson(data).object();
}

void ThemeSettings::saveSettingsFile(const QJsonObject& settings) {
    QString filePath = getSettingsPath();
    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        return;
    }
    file.write(QJsonDocument(settings).toJson());
    file.close();
}

void ThemeSettings::saveSetting(const QString& key, bool value) {
    QJsonObject obj = loadSettingsFile();
    obj[key] = value;
    saveSettingsFile(obj);
}

QVariant ThemeSettings::loadSetting(const QString& key) {
    QJsonObject obj = loadSettingsFile();
    if (obj.contains(key)) {
        return obj[key].toVariant();
    }
    return QVariant(); // Return null if not found
}

void ThemeSettings::saveVariant(const QString& key, const QVariant& value) {
    QJsonObject obj = loadSettingsFile();
    if (!value.isValid() || value.isNull()) {
        obj.remove(key);
    } else {
        obj[key] = QJsonValue::fromVariant(value);
    }
    saveSettingsFile(obj);
}

QVariant ThemeSettings::loadVariant(const QString& key, const QVariant& defaultValue) {
    QJsonObject obj = loadSettingsFile();
    if (obj.contains(key)) {
        return obj[key].toVariant();
    }
    return defaultValue;
}
