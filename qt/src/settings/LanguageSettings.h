#pragma once

#include <QObject>
#include <QString>

class LanguageSettings : public QObject {
    Q_OBJECT

public:
    explicit LanguageSettings(QObject* parent = nullptr);

    Q_INVOKABLE QString currentLanguage() const;
    Q_INVOKABLE void setCurrentLanguage(const QString& languageCode);

private:
    static QString sanitizeLanguageCode(const QString& languageCode);
};

