#pragma once
#include <QString>
#include <QJsonObject>
#include <QObject>

class ThemeSettings : public QObject {
    Q_OBJECT

public:
    ThemeSettings(QObject *parent = nullptr);
    
    Q_INVOKABLE void saveSetting(const QString& key, bool value);
    Q_INVOKABLE QVariant loadSetting(const QString& key);
    
    static QString getSettingsPath();

private:
    static QJsonObject loadSettingsFile();
    static void saveSettingsFile(const QJsonObject& settings);
};
