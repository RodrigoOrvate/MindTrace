import React, { useEffect, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";

import { createAnimal, fetchSpecies, fetchStrains } from "../api/client";
import { Species, Strain } from "../types";
import { DateFormat, formatDateOnly } from "../utils/dateFormat";
import { LanguageCode, t } from "../utils/i18n";

type Props = {
  route: any;
  navigation: any;
  isDark?: boolean;
  language?: LanguageCode;
  dateFormat?: DateFormat;
};

type SexValue = "male" | "female" | "unknown";

const PLACEHOLDER_COLOR = "#b8c4d0";

function parseDisplayToIso(displayDate: string, format: DateFormat): string {
  if (format === "YYYY-MM-DD") return displayDate;
  const match = displayDate.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (!match) return "";
  if (format === "DD/MM/YYYY") return `${match[3]}-${match[2]}-${match[1]}`;
  return `${match[3]}-${match[1]}-${match[2]}`; // MM/DD/YYYY
}

function todayForFormat(format: DateFormat): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return formatDateOnly(`${year}-${month}-${day}`, format);
}

function idPreview(displayDate: string, format: DateFormat, cc: string, rr: string): string {
  const ccPad = (cc || "??").toUpperCase();
  const rrNum = rr ? String(Number(rr)).padStart(2, "0") : "01";
  const iso = parseDisplayToIso(displayDate, format);
  const match = iso.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return `ID: DDMMAAAA-${ccPad}${rrNum}`;
  const [, yyyy, mm, dd] = match;
  return `ID gerado: ${dd}${mm}${yyyy}-${ccPad}${rrNum}`;
}

function ChipRow<T extends { id: number }>({
  items,
  selected,
  labelKey,
  onSelect,
  isDark,
}: {
  items: T[];
  selected: number | null;
  labelKey: keyof T;
  onSelect: (id: number) => void;
  isDark: boolean;
}) {
  return (
    <View style={styles.chipRow}>
      {items.map((item) => {
        const active = item.id === selected;
        return (
          <TouchableOpacity
            key={item.id}
            style={[styles.chip, active && styles.chipActive, !active && { backgroundColor: isDark ? "#1e293b" : "#fff", borderColor: isDark ? "#475569" : "#cbd5e1" }]}
            onPress={() => onSelect(item.id)}
          >
            <Text style={[styles.chipText, active && styles.chipTextActive, !active && { color: isDark ? "#e2e8f0" : "#334155" }]}>
              {String(item[labelKey])}
            </Text>
          </TouchableOpacity>
        );
      })}
    </View>
  );
}

export default function NewAnimalScreen({ route, navigation, isDark = false, language = "pt", dateFormat = "DD/MM/YYYY" }: Props) {
  const colors = isDark
    ? { bg: "#0f172a", card: "#1e293b", border: "#334155", text: "#e2e8f0", textMuted: "#94a3b8", label: "#94a3b8", inputBg: "#1e293b", inputText: "#f1f5f9", inputBorder: "#475569", titleColor: "#93c5fd" }
    : { bg: "#f8f9fb", card: "#ffffff", border: "#ccd2da", text: "#1e293b", textMuted: "#94a3b8", label: "#475569", inputBg: "#ffffff", inputText: "#1e293b", inputBorder: "#ccd2da", titleColor: "#17375e" };

  const [speciesList, setSpeciesList] = useState<Species[]>([]);
  const [strainList, setStrainList] = useState<Strain[]>([]);
  const [speciesId, setSpeciesId] = useState<number | null>(null);
  const [strainId, setStrainId] = useState<number | null>(null);
  const [sex, setSex] = useState<SexValue>("unknown");
  const [entryDate, setEntryDate] = useState(() => todayForFormat(dateFormat));
  const [markingDate, setMarkingDate] = useState("");
  const [weight, setWeight] = useState("");
  const [cc, setCc] = useState("");
  const [rr, setRr] = useState("01");
  const [saving, setSaving] = useState(false);
  const [loadingSpecies, setLoadingSpecies] = useState(true);

  const sexOptions: Array<{ label: string; value: SexValue }> = [
    { label: t(language, "male"), value: "male" },
    { label: t(language, "female"), value: "female" },
    { label: t(language, "sex_unknown"), value: "unknown" },
  ];

  useEffect(() => {
    fetchSpecies()
      .then((list) => {
        setSpeciesList(list);
        if (list.length > 0) handleSpeciesSelect(list[0].id, list);
      })
      .catch(() => Alert.alert("Erro", "Nao foi possivel carregar as especies."))
      .finally(() => setLoadingSpecies(false));
  }, []);

  function handleSpeciesSelect(id: number, list = speciesList) {
    setSpeciesId(id);
    setStrainId(null);
    setStrainList([]);
    fetchStrains(id)
      .then((strains) => {
        setStrainList(strains);
        if (strains.length > 0) setStrainId(strains[0].id);
      })
      .catch(() => {});
  }

  async function submit() {
    if (!speciesId || !strainId) {
      Alert.alert("Atencao", "Selecione especie e linhagem.");
      return;
    }
    const isoEntry = parseDisplayToIso(entryDate, dateFormat);
    if (!isoEntry.match(/^\d{4}-\d{2}-\d{2}$/)) {
      Alert.alert("Atencao", `Data de entrada invalida. Use o formato ${dateFormat}.`);
      return;
    }
    const isoMarking = markingDate ? parseDisplayToIso(markingDate, dateFormat) : "";
    if (markingDate && !isoMarking.match(/^\d{4}-\d{2}-\d{2}$/)) {
      Alert.alert("Atencao", `Data de marcamento invalida. Use o formato ${dateFormat}.`);
      return;
    }
    const ccNorm = cc.trim().toUpperCase();
    if (ccNorm.length !== 2) {
      Alert.alert("Atencao", "Caixa deve ter exatamente 2 caracteres (ex: A1, B3).");
      return;
    }
    const rrNum = parseInt(rr, 10);
    if (!rr || isNaN(rrNum) || rrNum < 1 || rrNum > 99) {
      Alert.alert("Atencao", "Numero do animal deve ser entre 1 e 99.");
      return;
    }
    setSaving(true);
    try {
      await createAnimal({
        entry_date: isoEntry,
        species_id: speciesId,
        strain_id: strainId,
        sex,
        marking_date: isoMarking || undefined,
        initial_weight_g: weight ? Number(weight) : undefined,
        id_cc: ccNorm,
        rr_override: rrNum,
      });
      Alert.alert("Sucesso", "Animal cadastrado com sucesso.");
      route.params?.onCreated?.();
      navigation.goBack();
    } catch (err) {
      Alert.alert("Erro", (err as Error).message);
    } finally {
      setSaving(false);
    }
  }

  if (loadingSpecies) {
    return (
      <View style={[styles.center, { backgroundColor: colors.bg }]}>
        <ActivityIndicator size="large" color="#1f4f7c" />
        <Text style={[styles.loadingText, { color: colors.textMuted }]}>{t(language, "loading")}</Text>
      </View>
    );
  }

  return (
    <ScrollView style={[styles.scroll, { backgroundColor: colors.bg }]} contentContainerStyle={styles.container}>
      <Text style={[styles.title, { color: colors.titleColor }]}>{t(language, "registration_title")}</Text>

      <Text style={[styles.label, { color: colors.label }]}>{t(language, "species")}</Text>
      <ChipRow items={speciesList} selected={speciesId} labelKey="common_name" onSelect={(id) => handleSpeciesSelect(id)} isDark={isDark} />

      <Text style={[styles.label, { color: colors.label }]}>{t(language, "strain")}</Text>
      {strainList.length === 0 ? (
        <Text style={[styles.hint, { color: colors.textMuted }]}>{t(language, "select_species_hint")}</Text>
      ) : (
        <ChipRow items={strainList} selected={strainId} labelKey="name" onSelect={setStrainId} isDark={isDark} />
      )}

      <Text style={[styles.label, { color: colors.label }]}>{t(language, "sex")}</Text>
      <View style={styles.chipRow}>
        {sexOptions.map((opt) => {
          const active = sex === opt.value;
          return (
            <TouchableOpacity
              key={opt.value}
              style={[styles.chip, active && styles.chipActive, !active && { backgroundColor: isDark ? "#1e293b" : "#fff", borderColor: isDark ? "#475569" : "#cbd5e1" }]}
              onPress={() => setSex(opt.value)}
            >
              <Text style={[styles.chipText, active && styles.chipTextActive, !active && { color: isDark ? "#e2e8f0" : "#334155" }]}>{opt.label}</Text>
            </TouchableOpacity>
          );
        })}
      </View>

      <Text style={[styles.label, { color: colors.label }]}>{t(language, "entry_date")}</Text>
      <TextInput
        style={[styles.input, { backgroundColor: colors.inputBg, color: colors.inputText, borderColor: colors.inputBorder }]}
        placeholder={dateFormat}
        placeholderTextColor={PLACEHOLDER_COLOR}
        value={entryDate}
        onChangeText={setEntryDate}
      />

      <Text style={[styles.label, { color: colors.label }]}>
        {t(language, "marking_date")} <Text style={[styles.optional, { color: colors.textMuted }]}>({t(language, "optional")})</Text>
      </Text>
      <TextInput
        style={[styles.input, { backgroundColor: colors.inputBg, color: colors.inputText, borderColor: colors.inputBorder }]}
        placeholder={dateFormat}
        placeholderTextColor={PLACEHOLDER_COLOR}
        value={markingDate}
        onChangeText={setMarkingDate}
      />

      <Text style={[styles.label, { color: colors.label }]}>
        {t(language, "initial_weight_g")} <Text style={[styles.optional, { color: colors.textMuted }]}>({t(language, "optional")})</Text>
      </Text>
      <TextInput
        style={[styles.input, { backgroundColor: colors.inputBg, color: colors.inputText, borderColor: colors.inputBorder }]}
        placeholder="Ex: 250"
        placeholderTextColor={PLACEHOLDER_COLOR}
        value={weight}
        onChangeText={setWeight}
        keyboardType="numeric"
      />

      <View style={styles.row2}>
        <View style={styles.flex1}>
          <Text style={[styles.label, { color: colors.label }]}>{t(language, "cage")}</Text>
          <TextInput
            style={[styles.input, { backgroundColor: colors.inputBg, color: colors.inputText, borderColor: colors.inputBorder }]}
            placeholder="Ex: A1, B3"
            placeholderTextColor={PLACEHOLDER_COLOR}
            value={cc}
            onChangeText={(v) => setCc(v.toUpperCase())}
            maxLength={2}
            autoCapitalize="characters"
          />
        </View>
        <View style={styles.flex1}>
          <Text style={[styles.label, { color: colors.label }]}>{t(language, "animal_number")}</Text>
          <TextInput
            style={[styles.input, { backgroundColor: colors.inputBg, color: colors.inputText, borderColor: colors.inputBorder }]}
            placeholder="01 - 99"
            placeholderTextColor={PLACEHOLDER_COLOR}
            value={rr}
            onChangeText={(v) => setRr(v.replace(/\D/g, "").slice(0, 2))}
            keyboardType="numeric"
            maxLength={2}
          />
        </View>
      </View>

      <Text style={[styles.idPreview, { backgroundColor: isDark ? "#1e293b" : "#f1f5f9", color: isDark ? "#94a3b8" : "#64748b" }]}>
        {idPreview(entryDate, dateFormat, cc, rr)}
      </Text>

      <TouchableOpacity
        style={[styles.saveBtn, saving && styles.saveBtnDisabled]}
        onPress={submit}
        disabled={saving}
      >
        <Text style={styles.saveBtnText}>{saving ? t(language, "saving") : t(language, "save_animal")}</Text>
      </TouchableOpacity>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  scroll: { flex: 1 },
  container: { padding: 20, gap: 6, paddingBottom: 40 },
  center: { flex: 1, alignItems: "center", justifyContent: "center", gap: 12 },
  title: { fontSize: 22, fontWeight: "700", marginBottom: 8 },
  label: { fontSize: 13, fontWeight: "600", marginTop: 12 },
  optional: { fontSize: 12, fontWeight: "400" },
  hint: { fontSize: 12, marginTop: 2 },
  input: {
    borderWidth: 1,
    borderRadius: 8,
    padding: 10,
    fontSize: 15,
    marginTop: 4,
  },
  chipRow: { flexDirection: "row", flexWrap: "wrap", gap: 8, marginTop: 6 },
  chip: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
    borderWidth: 1.5,
    borderColor: "#cbd5e1",
    backgroundColor: "white",
  },
  chipActive: { backgroundColor: "#1f4f7c", borderColor: "#1f4f7c" },
  chipText: { fontSize: 14, color: "#334155" },
  chipTextActive: { color: "white", fontWeight: "600" },
  row2: { flexDirection: "row", gap: 12 },
  flex1: { flex: 1 },
  idPreview: {
    fontSize: 12,
    borderRadius: 6,
    padding: 8,
    marginTop: 6,
    fontFamily: "monospace",
  },
  saveBtn: {
    marginTop: 24,
    backgroundColor: "#1f4f7c",
    borderRadius: 10,
    padding: 14,
    alignItems: "center",
  },
  saveBtnDisabled: { opacity: 0.5 },
  saveBtnText: { color: "white", fontWeight: "700", fontSize: 16 },
  loadingText: {},
});
