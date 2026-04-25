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
    Q_INVOKABLE void saveVariant(const QString& key, const QVariant& value);
    Q_INVOKABLE QVariant loadVariant(const QString& key, const QVariant& defaultValue = QVariant());
    
    static QString getSettingsPath();
    static QJsonObject loadSettingsFile();
    static void saveSettingsFile(const QJsonObject& settings);

private:
};
