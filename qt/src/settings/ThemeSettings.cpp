#include "ThemeSettings.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

ThemeSettings::ThemeSettings(QObject *parent)
    : QObject(parent) {}

QString ThemeSettings::getSettingsPath() {
    const QString appDataPath = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QDir().mkpath(appDataPath);
    return appDataPath + "/mindtrace_settings.json";
}

QJsonObject ThemeSettings::loadSettingsFile() {
    QFile file(getSettingsPath());
    if (!file.open(QIODevice::ReadOnly))
        return QJsonObject();
    const QByteArray rawJson = file.readAll();
    return QJsonDocument::fromJson(rawJson).object();
}

void ThemeSettings::saveSettingsFile(const QJsonObject& settings) {
    QFile file(getSettingsPath());
    if (!file.open(QIODevice::WriteOnly))
        return;
    file.write(QJsonDocument(settings).toJson());
}

void ThemeSettings::saveSetting(const QString& key, bool value) {
    QJsonObject settings = loadSettingsFile();
    settings[key] = value;
    saveSettingsFile(settings);
}

QVariant ThemeSettings::loadSetting(const QString& key) {
    const QJsonObject settings = loadSettingsFile();
    if (settings.contains(key))
        return settings[key].toVariant();
    return QVariant();
}

void ThemeSettings::saveVariant(const QString& key, const QVariant& value) {
    QJsonObject settings = loadSettingsFile();
    if (!value.isValid() || value.isNull())
        settings.remove(key);
    else
        settings[key] = QJsonValue::fromVariant(value);
    saveSettingsFile(settings);
}

QVariant ThemeSettings::loadVariant(const QString& key, const QVariant& defaultValue) {
    const QJsonObject settings = loadSettingsFile();
    if (settings.contains(key))
        return settings[key].toVariant();
    return defaultValue;
}
