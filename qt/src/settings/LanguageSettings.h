#pragma once

#include <QObject>
#include <QString>

/// Persists the UI language code (pt-BR, en-US, es-ES) in mindtrace_settings.json.
class LanguageSettings : public QObject {
    Q_OBJECT

public:
    explicit LanguageSettings(QObject* parent = nullptr);

    Q_INVOKABLE QString currentLanguage() const;
    Q_INVOKABLE void setCurrentLanguage(const QString& languageCode);

private:
    static QString sanitizeLanguageCode(const QString& languageCode);
};

