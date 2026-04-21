pragma Singleton
import QtQuick

QtObject {
    id: manager

    property string currentLanguage: "pt-BR"
    signal languageChanged(string languageCode)

    readonly property var supportedLanguages: [
        { code: "pt-BR", label: "Português (Brasil)" },
        { code: "en-US", label: "English (US)" },
        { code: "es-ES", label: "Español" }
    ]

    function languageLabel(code) {
        for (var i = 0; i < supportedLanguages.length; i++) {
            if (supportedLanguages[i].code === code) {
                return supportedLanguages[i].label
            }
        }
        return "Português (Brasil)"
    }

    function tr3(ptBr, enUs, esEs) {
        if (currentLanguage === "en-US") return enUs
        if (currentLanguage === "es-ES") return esEs
        return ptBr
    }

    function setLanguage(languageCode) {
        if (languageCode !== "pt-BR" && languageCode !== "en-US" && languageCode !== "es-ES") {
            languageCode = "pt-BR"
        }
        if (currentLanguage === languageCode) return
        currentLanguage = languageCode
        if (typeof LanguageSettings !== "undefined") {
            LanguageSettings.setCurrentLanguage(languageCode)
        }
        languageChanged(languageCode)
    }

    Component.onCompleted: {
        if (typeof LanguageSettings !== "undefined") {
            currentLanguage = LanguageSettings.currentLanguage()
        }
    }
}

