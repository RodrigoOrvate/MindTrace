import React, { useCallback, useState } from "react";
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  SafeAreaView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";
import { useFocusEffect } from "@react-navigation/native";

import { listAnimals } from "../api/client";
import { Animal } from "../types";

type Props = { navigation: any; isAdmin?: boolean };

const STATUS_LABEL: Record<Animal["status"], string> = {
  active: "Ativo",
  euthanized: "Eutanasiado",
  deceased: "Falecido",
  archived: "Arquivado",
};

const STATUS_COLOR: Record<Animal["status"], string> = {
  active: "#16a34a",
  euthanized: "#dc2626",
  deceased: "#6b7280",
  archived: "#9ca3af",
};

export default function AnimalsListScreen({ navigation, isAdmin = false }: Props) {
  const [query, setQuery] = useState("");
  const [animals, setAnimals] = useState<Animal[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

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

  // Reload every time this screen comes into focus (e.g. after delete or create)
  useFocusEffect(
    useCallback(() => {
      load(query);
    }, [load])
  );

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Animal Lifecycle</Text>
        <View style={styles.headerActions}>
          {isAdmin ? (
            <TouchableOpacity
              style={styles.adminBtn}
              onPress={() => navigation.navigate("UsersAdmin")}
            >
              <Text style={styles.adminBtnText}>Usuarios</Text>
            </TouchableOpacity>
          ) : null}
          <TouchableOpacity
            style={styles.newBtn}
            onPress={() => navigation.navigate("NewAnimal")}
          >
            <Text style={styles.newBtnText}>+ Novo Animal</Text>
          </TouchableOpacity>
        </View>
      </View>

      <View style={styles.searchRow}>
        <TextInput
          style={styles.input}
          placeholder="Buscar por ID (ex: 21042026-A501)"
          placeholderTextColor="#b8c4d0"
          value={query}
          onChangeText={setQuery}
          onSubmitEditing={() => load(query)}
          returnKeyType="search"
        />
        <TouchableOpacity style={styles.searchBtn} onPress={() => load(query)}>
          <Text style={styles.searchBtnText}>Buscar</Text>
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
        ListEmptyComponent={
          !loading ? <Text style={styles.empty}>Nenhum animal encontrado.</Text> : null
        }
        renderItem={({ item }) => (
          <Pressable
            style={styles.card}
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
                <Text style={[styles.badgeText, { color: STATUS_COLOR[item.status] }]}>
                  {STATUS_LABEL[item.status]}
                </Text>
              </View>
            </View>
            <Text style={styles.meta}>
              Entrada: {item.entry_date}
              {item.initial_weight_g ? `  ·  ${item.initial_weight_g} g` : ""}
            </Text>
          </Pressable>
        )}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: "#f8f9fb" },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    padding: 16,
    paddingBottom: 8,
  },
  title: { fontSize: 22, fontWeight: "700", color: "#17375e" },
  headerActions: { flexDirection: "row", alignItems: "center", gap: 8 },
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
});
