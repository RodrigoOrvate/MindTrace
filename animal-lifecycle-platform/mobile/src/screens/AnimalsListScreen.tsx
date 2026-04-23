import React, { useCallback, useState } from "react";
import {
  ActivityIndicator,
  FlatList,
  Modal,
  Pressable,
  SafeAreaView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";
import { useFocusEffect } from "@react-navigation/native";

import { bulkEuthanasia, listAnimals } from "../api/client";
import { Animal } from "../types";
import { DateFormat, formatDateOnly } from "../utils/dateFormat";
import { LanguageCode, t } from "../utils/i18n";

type Props = { navigation: any; isAdmin?: boolean; isDark?: boolean; language?: LanguageCode; dateFormat?: DateFormat };

const STATUS_LABEL: Record<Animal["status"], string> = {
  active: "Ativo",
  euthanized: "Inativo",
  deceased: "Inativo",
  archived: "Inativo",
};

const STATUS_COLOR: Record<Animal["status"], string> = {
  active: "#16a34a",
  euthanized: "#dc2626",
  deceased: "#dc2626",
  archived: "#dc2626",
};

function toIdDateToken(entryDate: string): string {
  const match = entryDate.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return "";
  const [, yyyy, mm, dd] = match;
  return `${dd}${mm}${yyyy}`;
}

function todayLocal(): string {
  const now = new Date();
  const yyyy = String(now.getFullYear());
  const mm = String(now.getMonth() + 1).padStart(2, "0");
  const dd = String(now.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

function GroupEuthanasiaModal({
  visible,
  onCancel,
  onDone,
}: {
  visible: boolean;
  onCancel: () => void;
  onDone: () => Promise<void>;
}) {
  const [entryDate, setEntryDate] = useState(todayLocal());
  const [typedDate, setTypedDate] = useState("");
  const [reason, setReason] = useState("Eutanasia em grupo");
  const [allAnimals, setAllAnimals] = useState<Animal[]>([]);
  const [selected, setSelected] = useState<number[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      if (!visible) return;
      setLoading(true);
      setError(null);
      listAnimals("")
        .then((rows) => setAllAnimals(rows))
        .catch((err) => setError((err as Error).message))
        .finally(() => setLoading(false));
    }, [visible])
  );

  const token = toIdDateToken(entryDate);
  const candidates = allAnimals.filter(
    (animal) => animal.status === "active" && token.length === 8 && animal.internal_id.startsWith(token)
  );

  const canConfirm = selected.length > 0 && typedDate.trim() === entryDate && reason.trim().length > 0 && !saving;

  function toggle(id: number) {
    setSelected((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  }

  async function handleConfirm() {
    if (!canConfirm) return;
    setSaving(true);
    setError(null);
    try {
      await bulkEuthanasia({
        entry_date: entryDate,
        euthanasia_date: todayLocal(),
        animal_ids: selected,
        reason: reason.trim(),
      });
      setSelected([]);
      setTypedDate("");
      await onDone();
      onCancel();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onCancel}>
      <View style={modal.overlay}>
        <View style={modal.box}>
          <Text style={modal.title}>Eutanasia em Grupo</Text>
          <Text style={modal.label}>Data de entrada (AAAA-MM-DD)</Text>
          <TextInput
            style={modal.input}
            placeholder="AAAA-MM-DD"
            placeholderTextColor="#94a3b8"
            value={entryDate}
            onChangeText={setEntryDate}
          />
          <Text style={[modal.label, { marginTop: 2 }]}>Candidatos: {candidates.length} ativos para essa data</Text>

          {loading ? (
            <ActivityIndicator color="#1f4f7c" style={{ marginTop: 12 }} />
          ) : (
            <View style={{ maxHeight: 200, marginTop: 8 }}>
              <FlatList
                data={candidates}
                keyExtractor={(item) => String(item.id)}
                renderItem={({ item }) => {
                  const checked = selected.includes(item.id);
                  return (
                    <TouchableOpacity style={styles.groupRow} onPress={() => toggle(item.id)}>
                      <View style={[styles.checkbox, checked && styles.checkboxOn]} />
                      <Text style={styles.groupRowText}>{item.internal_id}</Text>
                    </TouchableOpacity>
                  );
                }}
                ListEmptyComponent={<Text style={styles.groupEmpty}>Nenhum ativo nessa data.</Text>}
              />
            </View>
          )}

          <Text style={modal.label}>Motivo</Text>
          <TextInput
            style={modal.input}
            placeholder="Ex: Fim do protocolo"
            placeholderTextColor="#94a3b8"
            value={reason}
            onChangeText={setReason}
          />

          <Text style={modal.label}>Confirmacao dupla: digite a data exata ({entryDate})</Text>
          <TextInput
            style={modal.input}
            placeholder={entryDate}
            placeholderTextColor="#94a3b8"
            value={typedDate}
            onChangeText={setTypedDate}
          />

          {error ? <Text style={styles.error}>{error}</Text> : null}

          <View style={modal.btnRow}>
            <TouchableOpacity style={modal.cancelBtn} onPress={onCancel}>
              <Text style={modal.cancelText}>Cancelar</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[modal.deleteBtn, !canConfirm && modal.btnDisabled]}
              onPress={handleConfirm}
              disabled={!canConfirm}
            >
              <Text style={modal.deleteBtnText}>{saving ? "Aplicando..." : "Confirmar Grupo"}</Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </Modal>
  );
}

export default function AnimalsListScreen({
  navigation,
  isAdmin = false,
  isDark = false,
  language = "pt",
  dateFormat = "DD/MM/YYYY",
}: Props) {
  const colors = isDark
    ? { bg: "#0f172a", card: "#1e293b", border: "#334155", text: "#e2e8f0", textMuted: "#94a3b8", inputBg: "#1e293b", inputText: "#f1f5f9", inputBorder: "#475569" }
    : { bg: "#f8f9fb", card: "#ffffff", border: "#e2e8f0", text: "#0f172a", textMuted: "#64748b", inputBg: "#ffffff", inputText: "#1e293b", inputBorder: "#ccd2da" };
  const [query, setQuery] = useState("");
  const [animals, setAnimals] = useState<Animal[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showGroupEuth, setShowGroupEuth] = useState(false);

  const load = useCallback(async (q: string) => {
    setLoading(true);
    setError(null);
    try {
      const data = await listAnimals(q);
      setAnimals(data);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setLoading(false);
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      load(query);
    }, [load, query])
  );

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.bg }]}>
      <View style={styles.header}>
        <Text style={styles.title}>{t(language, "app_title")}</Text>
        <View style={styles.headerActions}>
          {isAdmin ? (
            <TouchableOpacity style={styles.adminBtn} onPress={() => navigation.navigate("UsersAdmin")}>
              <Text style={styles.adminBtnText}>{t(language, "admin_users")}</Text>
            </TouchableOpacity>
          ) : null}
          <TouchableOpacity style={styles.newBtn} onPress={() => navigation.navigate("NewAnimal")}>
            <Text style={styles.newBtnText}>+ {t(language, "new_animal")}</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.groupEuthBtn} onPress={() => setShowGroupEuth(true)}>
            <Text style={styles.groupEuthBtnText}>{t(language, "group_euthanasia")}</Text>
          </TouchableOpacity>
        </View>
      </View>

      <View style={styles.searchRow}>
        <TextInput
          style={[styles.input, { backgroundColor: colors.inputBg, color: colors.inputText, borderColor: colors.inputBorder }]}
          placeholder={t(language, "search_placeholder")}
          placeholderTextColor="#b8c4d0"
          value={query}
          onChangeText={setQuery}
          onSubmitEditing={() => load(query)}
          returnKeyType="search"
        />
        <TouchableOpacity style={styles.searchBtn} onPress={() => load(query)}>
          <Text style={styles.searchBtnText}>{t(language, "search")}</Text>
        </TouchableOpacity>
      </View>

      {loading && (
        <View style={styles.center}>
          <ActivityIndicator color="#1f4f7c" />
        </View>
      )}
      {error && <Text style={styles.error}>{error}</Text>}

      <FlatList
        data={animals}
        keyExtractor={(item) => String(item.id)}
        contentContainerStyle={styles.list}
        ListEmptyComponent={!loading ? <Text style={styles.empty}>Nenhum animal encontrado.</Text> : null}
        renderItem={({ item }) => (
          <Pressable
            style={[styles.card, { backgroundColor: colors.card, borderColor: colors.border }]}
            onPress={() =>
              navigation.navigate("Timeline", {
                animalId: item.id,
                animalCode: item.internal_id,
              })
            }
          >
            <View style={styles.cardTop}>
              <Text style={styles.id}>{item.internal_id}</Text>
              <View style={[styles.badge, { backgroundColor: STATUS_COLOR[item.status] + "20" }]}>
                <Text style={[styles.badgeText, { color: STATUS_COLOR[item.status] }]}>{STATUS_LABEL[item.status]}</Text>
              </View>
            </View>
            <Text style={styles.meta}>
              Entrada: {formatDateOnly(item.entry_date, dateFormat)}
              {item.initial_weight_g ? `  -  ${item.initial_weight_g} g` : ""}
            </Text>
          </Pressable>
        )}
      />

      <GroupEuthanasiaModal
        visible={showGroupEuth}
        onCancel={() => setShowGroupEuth(false)}
        onDone={async () => {
          await load(query);
        }}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: "#f8f9fb" },
  header: {
    flexDirection: "column",
    alignItems: "flex-start",
    padding: 16,
    paddingBottom: 6,
    gap: 10,
  },
  title: { fontSize: 22, fontWeight: "700", color: "#17375e" },
  headerActions: { flexDirection: "row", alignItems: "center", gap: 8, flexWrap: "wrap" },
  adminBtn: {
    backgroundColor: "#fff7ed",
    borderWidth: 1,
    borderColor: "#fed7aa",
    paddingHorizontal: 10,
    paddingVertical: 8,
    borderRadius: 8,
  },
  adminBtnText: { color: "#9a3412", fontWeight: "700", fontSize: 13 },
  newBtn: {
    backgroundColor: "#1f4f7c",
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 8,
  },
  newBtnText: { color: "white", fontWeight: "600", fontSize: 14 },
  groupEuthBtn: {
    backgroundColor: "#fee2e2",
    borderWidth: 1,
    borderColor: "#fecaca",
    paddingHorizontal: 10,
    paddingVertical: 8,
    borderRadius: 8,
  },
  groupEuthBtnText: { color: "#b91c1c", fontWeight: "700", fontSize: 12 },
  searchRow: { flexDirection: "row", gap: 8, paddingHorizontal: 16, paddingBottom: 8 },
  input: {
    flex: 1,
    borderWidth: 1,
    borderColor: "#ccd2da",
    borderRadius: 8,
    padding: 10,
    backgroundColor: "white",
    fontSize: 14,
    color: "#1e293b",
  },
  searchBtn: {
    backgroundColor: "#e2e8f0",
    paddingHorizontal: 14,
    borderRadius: 8,
    justifyContent: "center",
  },
  searchBtnText: { color: "#334155", fontWeight: "600" },
  list: { paddingHorizontal: 16, paddingBottom: 20 },
  card: {
    backgroundColor: "white",
    borderRadius: 10,
    padding: 14,
    marginVertical: 5,
    borderWidth: 1,
    borderColor: "#e2e8f0",
    gap: 4,
  },
  cardTop: { flexDirection: "row", alignItems: "center", justifyContent: "space-between" },
  id: { fontWeight: "700", fontSize: 17, color: "#1f4f7c", fontFamily: "monospace" },
  badge: { paddingHorizontal: 8, paddingVertical: 3, borderRadius: 12 },
  badgeText: { fontSize: 12, fontWeight: "600" },
  meta: { fontSize: 13, color: "#64748b" },
  center: { padding: 20, alignItems: "center" },
  empty: { textAlign: "center", color: "#94a3b8", marginTop: 40 },
  error: { color: "#b91c1c", paddingHorizontal: 16, marginBottom: 8 },
  groupRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    borderWidth: 1,
    borderColor: "#e2e8f0",
    borderRadius: 8,
    padding: 8,
    marginBottom: 6,
    backgroundColor: "#fff",
  },
  groupRowText: { color: "#1f4f7c", fontFamily: "monospace", fontWeight: "700" },
  checkbox: {
    width: 16,
    height: 16,
    borderRadius: 4,
    borderWidth: 1.5,
    borderColor: "#94a3b8",
    backgroundColor: "white",
  },
  checkboxOn: {
    backgroundColor: "#dc2626",
    borderColor: "#dc2626",
  },
  groupEmpty: { color: "#94a3b8", textAlign: "center", marginTop: 8 },
});

const modal = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: "rgba(0,0,0,0.5)",
    justifyContent: "center",
    alignItems: "center",
    padding: 20,
  },
  box: {
    backgroundColor: "white",
    borderRadius: 14,
    padding: 20,
    width: "100%",
    maxWidth: 460,
    gap: 8,
  },
  title: { fontSize: 18, fontWeight: "700", color: "#1e293b" },
  label: { fontSize: 13, fontWeight: "600", color: "#475569", marginTop: 6 },
  input: {
    borderWidth: 1.5,
    borderColor: "#cbd5e1",
    borderRadius: 8,
    padding: 10,
    fontSize: 15,
    color: "#1e293b",
    marginTop: 4,
  },
  btnRow: { flexDirection: "row", gap: 10, marginTop: 12 },
  cancelBtn: {
    flex: 1,
    padding: 12,
    borderRadius: 8,
    borderWidth: 1.5,
    borderColor: "#cbd5e1",
    alignItems: "center",
  },
  cancelText: { color: "#334155", fontWeight: "600" },
  deleteBtn: { flex: 1, padding: 12, borderRadius: 8, backgroundColor: "#dc2626", alignItems: "center" },
  deleteBtnText: { color: "white", fontWeight: "700" },
  btnDisabled: { opacity: 0.4 },
});
