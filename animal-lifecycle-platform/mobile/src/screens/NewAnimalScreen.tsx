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

type Props = { route: any; navigation: any };

const SEX_OPTIONS = [
  { label: "Macho", value: "male" },
  { label: "Femea", value: "female" },
  { label: "Nao def.", value: "unknown" },
] as const;

type SexValue = "male" | "female" | "unknown";

const PLACEHOLDER_COLOR = "#b8c4d0";

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

function idPreview(entryDate: string, cc: string, rr: string): string {
  const ccPad = (cc || "??").toUpperCase();
  const rrNum = rr ? String(Number(rr)).padStart(2, "0") : "01";
  const match = entryDate.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return `ID: DDMMAAAA-${ccPad}${rrNum}`;
  const [, yyyy, mm, dd] = match;
  return `ID gerado: ${dd}${mm}${yyyy}-${ccPad}${rrNum}`;
}

function ChipRow<T extends { id: number }>({
  items,
  selected,
  labelKey,
  onSelect,
}: {
  items: T[];
  selected: number | null;
  labelKey: keyof T;
  onSelect: (id: number) => void;
}) {
  return (
    <View style={styles.chipRow}>
      {items.map((item) => {
        const active = item.id === selected;
        return (
          <TouchableOpacity
            key={item.id}
            style={[styles.chip, active && styles.chipActive]}
            onPress={() => onSelect(item.id)}
          >
            <Text style={[styles.chipText, active && styles.chipTextActive]}>
              {String(item[labelKey])}
            </Text>
          </TouchableOpacity>
        );
      })}
    </View>
  );
}

export default function NewAnimalScreen({ route, navigation }: Props) {
  const [speciesList, setSpeciesList] = useState<Species[]>([]);
  const [strainList, setStrainList] = useState<Strain[]>([]);
  const [speciesId, setSpeciesId] = useState<number | null>(null);
  const [strainId, setStrainId] = useState<number | null>(null);
  const [sex, setSex] = useState<SexValue>("unknown");
  const [entryDate, setEntryDate] = useState(today());
  const [markingDate, setMarkingDate] = useState("");
  const [weight, setWeight] = useState("");
  const [cc, setCc] = useState("");
  const [rr, setRr] = useState("01");
  const [saving, setSaving] = useState(false);
  const [loadingSpecies, setLoadingSpecies] = useState(true);

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
    if (!entryDate.match(/^\d{4}-\d{2}-\d{2}$/)) {
      Alert.alert("Atencao", "Data de entrada invalida. Use o formato AAAA-MM-DD.");
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
        entry_date: entryDate,
        species_id: speciesId,
        strain_id: strainId,
        sex,
        marking_date: markingDate || undefined,
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
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#1f4f7c" />
        <Text style={styles.loadingText}>Carregando...</Text>
      </View>
    );
  }

  return (
    <ScrollView style={styles.scroll} contentContainerStyle={styles.container}>
      <Text style={styles.title}>Cadastro de Animal</Text>

      <Text style={styles.label}>Especie</Text>
      <ChipRow
        items={speciesList}
        selected={speciesId}
        labelKey="common_name"
        onSelect={(id) => handleSpeciesSelect(id)}
      />

      <Text style={styles.label}>Linhagem</Text>
      {strainList.length === 0 ? (
        <Text style={styles.hint}>Selecione uma especie acima</Text>
      ) : (
        <ChipRow items={strainList} selected={strainId} labelKey="name" onSelect={setStrainId} />
      )}

      <Text style={styles.label}>Sexo</Text>
      <View style={styles.chipRow}>
        {SEX_OPTIONS.map((opt) => {
          const active = sex === opt.value;
          return (
            <TouchableOpacity
              key={opt.value}
              style={[styles.chip, active && styles.chipActive]}
              onPress={() => setSex(opt.value)}
            >
              <Text style={[styles.chipText, active && styles.chipTextActive]}>{opt.label}</Text>
            </TouchableOpacity>
          );
        })}
      </View>

      <Text style={styles.label}>Data de Entrada</Text>
      <TextInput
        style={styles.input}
        placeholder="AAAA-MM-DD"
        placeholderTextColor={PLACEHOLDER_COLOR}
        value={entryDate}
        onChangeText={setEntryDate}
      />

      <Text style={styles.label}>
        Data de Marcamento <Text style={styles.optional}>(opcional)</Text>
      </Text>
      <TextInput
        style={styles.input}
        placeholder="AAAA-MM-DD"
        placeholderTextColor={PLACEHOLDER_COLOR}
        value={markingDate}
        onChangeText={setMarkingDate}
      />

      <Text style={styles.label}>
        Peso Inicial (g) <Text style={styles.optional}>(opcional)</Text>
      </Text>
      <TextInput
        style={styles.input}
        placeholder="Ex: 250"
        placeholderTextColor={PLACEHOLDER_COLOR}
        value={weight}
        onChangeText={setWeight}
        keyboardType="numeric"
      />

      {/* Caixa + Numero do animal lado a lado */}
      <View style={styles.row2}>
        <View style={styles.flex1}>
          <Text style={styles.label}>Caixa</Text>
          <TextInput
            style={styles.input}
            placeholder="Ex: A1, B3"
            placeholderTextColor={PLACEHOLDER_COLOR}
            value={cc}
            onChangeText={(t) => setCc(t.toUpperCase())}
            maxLength={2}
            autoCapitalize="characters"
          />
        </View>
        <View style={styles.flex1}>
          <Text style={styles.label}>No do Animal</Text>
          <TextInput
            style={styles.input}
            placeholder="01 - 99"
            placeholderTextColor={PLACEHOLDER_COLOR}
            value={rr}
            onChangeText={(t) => setRr(t.replace(/\D/g, "").slice(0, 2))}
            keyboardType="numeric"
            maxLength={2}
          />
        </View>
      </View>

      <Text style={styles.idPreview}>{idPreview(entryDate, cc, rr)}</Text>

      <TouchableOpacity
        style={[styles.saveBtn, saving && styles.saveBtnDisabled]}
        onPress={submit}
        disabled={saving}
      >
        <Text style={styles.saveBtnText}>{saving ? "Salvando..." : "Salvar Animal"}</Text>
      </TouchableOpacity>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  scroll: { flex: 1, backgroundColor: "#f8f9fb" },
  container: { padding: 20, gap: 6, paddingBottom: 40 },
  center: { flex: 1, alignItems: "center", justifyContent: "center", gap: 12 },
  title: { fontSize: 22, fontWeight: "700", color: "#17375e", marginBottom: 8 },
  label: { fontSize: 13, fontWeight: "600", color: "#475569", marginTop: 12 },
  optional: { fontSize: 12, fontWeight: "400", color: "#94a3b8" },
  hint: { fontSize: 12, color: "#94a3b8", marginTop: 2 },
  input: {
    borderWidth: 1,
    borderColor: "#ccd2da",
    borderRadius: 8,
    padding: 10,
    backgroundColor: "white",
    fontSize: 15,
    marginTop: 4,
    color: "#1e293b",
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
    color: "#64748b",
    backgroundColor: "#f1f5f9",
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
  loadingText: { color: "#64748b" },
});
