#include "LanguageSettings.h"

#include "ThemeSettings.h"
#include <QJsonObject>

namespace {
constexpr const char* kLanguageKey = "language";
constexpr const char* kDefaultLanguage = "pt-BR";
}

LanguageSettings::LanguageSettings(QObject* parent)
    : QObject(parent) {}

QString LanguageSettings::currentLanguage() const
{
    const QJsonObject settings = ThemeSettings::loadSettingsFile();
    const QString rawLanguage = settings.value(kLanguageKey).toString(QString::fromLatin1(kDefaultLanguage));
    return sanitizeLanguageCode(rawLanguage);
}

void LanguageSettings::setCurrentLanguage(const QString& languageCode)
{
    QJsonObject settings = ThemeSettings::loadSettingsFile();
    settings[QString::fromLatin1(kLanguageKey)] = sanitizeLanguageCode(languageCode);
    ThemeSettings::saveSettingsFile(settings);
}

QString LanguageSettings::sanitizeLanguageCode(const QString& languageCode)
{
    const QString normalized = languageCode.trimmed();
    if (normalized == "en-US" || normalized == "es-ES") return normalized;
    return QString::fromLatin1(kDefaultLanguage);
}

