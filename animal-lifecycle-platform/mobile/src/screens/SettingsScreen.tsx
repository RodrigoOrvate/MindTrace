import React, { useState } from "react";
import { Alert, SafeAreaView, StyleSheet, Text, TouchableOpacity, View } from "react-native";

import { AppSettings } from "../types";
import { DateFormat } from "../utils/dateFormat";
import { LanguageCode, t } from "../utils/i18n";

type Props = {
  navigation: any;
  settings: AppSettings;
  onUpdatePreferences: (payload: { theme?: "light" | "dark"; language?: LanguageCode }) => Promise<void>;
  onUpdateDateFormat: (value: DateFormat) => Promise<void>;
};

function OptionRow<T extends string>({
  value,
  selected,
  onPress,
  label,
}: {
  value: T;
  selected: T;
  onPress: (v: T) => void;
  label: string;
}) {
  const active = value === selected;
  return (
    <TouchableOpacity
      style={[styles.option, active && styles.optionActive]}
      onPress={() => onPress(value)}
    >
      <Text style={[styles.optionText, active && styles.optionTextActive]}>{label}</Text>
    </TouchableOpacity>
  );
}

export default function SettingsScreen({
  navigation,
  settings,
  onUpdatePreferences,
  onUpdateDateFormat,
}: Props) {
  const [theme, setTheme] = useState<"light" | "dark">(settings.theme);
  const [language, setLanguage] = useState<LanguageCode>(settings.language);
  const [dateFormat, setDateFormat] = useState<DateFormat>(settings.date_format);
  const [saving, setSaving] = useState(false);

  const isDark = theme === "dark";
  const colors = isDark
    ? { bg: "#0f172a", card: "#111827", border: "#334155", text: "#e2e8f0", textMuted: "#94a3b8" }
    : { bg: "#f8f9fb", card: "#ffffff", border: "#cbd5e1", text: "#0f172a", textMuted: "#64748b" };

  async function save() {
    setSaving(true);
    try {
      await onUpdatePreferences({ theme, language });
      if (settings.is_admin && dateFormat !== settings.date_format) {
        await onUpdateDateFormat(dateFormat);
      }
      Alert.alert("OK", "Configuracoes atualizadas.");
      navigation.goBack();
    } catch (err) {
      Alert.alert("Erro", (err as Error).message);
    } finally {
      setSaving(false);
    }
  }

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.bg }]}>
      <View style={[styles.card, { backgroundColor: colors.card, borderColor: colors.border }]}>
        <Text style={[styles.sectionTitle, { color: colors.text }]}>{t(language, "theme")}</Text>
        <View style={styles.row}>
          <OptionRow value="light" selected={theme} onPress={setTheme} label={t(language, "light")} />
          <OptionRow value="dark" selected={theme} onPress={setTheme} label={t(language, "dark")} />
        </View>

        <Text style={[styles.sectionTitle, { color: colors.text, marginTop: 18 }]}>{t(language, "language")}</Text>
        <View style={styles.row}>
          <OptionRow value="pt" selected={language} onPress={setLanguage} label={t(language, "portuguese")} />
          <OptionRow value="en" selected={language} onPress={setLanguage} label={t(language, "english")} />
          <OptionRow value="es" selected={language} onPress={setLanguage} label={t(language, "spanish")} />
        </View>

        {settings.is_admin ? (
          <>
            <Text style={[styles.sectionTitle, { color: colors.text, marginTop: 18 }]}>
              {t(language, "date_format")} (Global)
            </Text>
            <View style={styles.row}>
              <OptionRow value="DD/MM/YYYY" selected={dateFormat} onPress={setDateFormat} label="DD/MM/YYYY" />
              <OptionRow value="MM/DD/YYYY" selected={dateFormat} onPress={setDateFormat} label="MM/DD/YYYY" />
              <OptionRow value="YYYY-MM-DD" selected={dateFormat} onPress={setDateFormat} label="YYYY-MM-DD" />
            </View>
            <Text style={[styles.help, { color: colors.textMuted }]}>
              Apenas admin altera o formato de data para todos.
            </Text>
          </>
        ) : (
          <Text style={[styles.help, { color: colors.textMuted, marginTop: 18 }]}>
            Formato de data global definido pelo administrador.
          </Text>
        )}

        <View style={styles.buttons}>
          <TouchableOpacity style={styles.backBtn} onPress={() => navigation.goBack()}>
            <Text style={styles.backText}>{t(language, "close")}</Text>
          </TouchableOpacity>
          <TouchableOpacity style={[styles.saveBtn, saving && { opacity: 0.5 }]} onPress={save} disabled={saving}>
            <Text style={styles.saveText}>{saving ? "..." : t(language, "save")}</Text>
          </TouchableOpacity>
        </View>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 16 },
  card: {
    borderWidth: 1,
    borderRadius: 14,
    padding: 16,
  },
  sectionTitle: { fontSize: 16, fontWeight: "700", marginBottom: 8 },
  row: { flexDirection: "row", gap: 8, flexWrap: "wrap" },
  option: {
    borderWidth: 1,
    borderColor: "#cbd5e1",
    borderRadius: 10,
    paddingVertical: 8,
    paddingHorizontal: 12,
    backgroundColor: "#fff",
  },
  optionActive: { backgroundColor: "#1f4f7c", borderColor: "#1f4f7c" },
  optionText: { color: "#334155", fontWeight: "600" },
  optionTextActive: { color: "#fff" },
  help: { marginTop: 8, fontSize: 12 },
  buttons: { flexDirection: "row", gap: 8, marginTop: 20 },
  backBtn: {
    flex: 1,
    borderWidth: 1,
    borderColor: "#cbd5e1",
    borderRadius: 10,
    paddingVertical: 10,
    alignItems: "center",
  },
  backText: { color: "#334155", fontWeight: "700" },
  saveBtn: {
    flex: 1,
    backgroundColor: "#1f4f7c",
    borderRadius: 10,
    paddingVertical: 10,
    alignItems: "center",
  },
  saveText: { color: "#fff", fontWeight: "700" },
});
