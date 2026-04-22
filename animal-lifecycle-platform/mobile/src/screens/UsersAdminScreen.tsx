import React, { useCallback, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  FlatList,
  SafeAreaView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";
import { useFocusEffect } from "@react-navigation/native";

import { createUser, listUsers } from "../api/client";
import { UserAccount } from "../types";

const PLACEHOLDER_COLOR = "#b8c4d0";

type Props = { navigation: any };

export default function UsersAdminScreen({ navigation }: Props) {
  const [users, setUsers] = useState<UserAccount[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [saving, setSaving] = useState(false);

  const loadUsers = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await listUsers();
      setUsers(data);
    } catch (err) {
      const msg = (err as Error).message || "Falha ao carregar usuarios.";
      setError(msg);
    } finally {
      setLoading(false);
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      loadUsers();
    }, [loadUsers])
  );

  async function handleCreateUser() {
    if (!fullName.trim() || !username.trim() || !password) {
      Alert.alert("Atencao", "Nome, usuario e senha sao obrigatorios.");
      return;
    }
    if (password.length < 8) {
      Alert.alert("Atencao", "Senha deve ter no minimo 8 caracteres.");
      return;
    }

    setSaving(true);
    try {
      await createUser({
        full_name: fullName.trim(),
        email: email.trim() || undefined,
        username: username.trim(),
        password,
        is_admin: false,
      });

      setFullName("");
      setEmail("");
      setUsername("");
      setPassword("");

      await loadUsers();
      Alert.alert("Sucesso", "Usuario criado com sucesso.");
    } catch (err) {
      Alert.alert("Erro", (err as Error).message || "Falha ao criar usuario.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <SafeAreaView style={styles.container}>
      <FlatList
        data={users}
        keyExtractor={(item) => String(item.id)}
        contentContainerStyle={styles.list}
        ListHeaderComponent={
          <View style={styles.formCard}>
            <Text style={styles.formTitle}>Novo Usuario</Text>

            <Text style={styles.label}>Nome completo</Text>
            <TextInput
              style={styles.input}
              value={fullName}
              onChangeText={setFullName}
              placeholder="Ex: Maria Souza"
              placeholderTextColor={PLACEHOLDER_COLOR}
            />

            <Text style={styles.label}>Email (opcional)</Text>
            <TextInput
              style={styles.input}
              value={email}
              onChangeText={setEmail}
              placeholder="maria@lab.local"
              placeholderTextColor={PLACEHOLDER_COLOR}
              autoCapitalize="none"
              keyboardType="email-address"
            />

            <Text style={styles.label}>Usuario</Text>
            <TextInput
              style={styles.input}
              value={username}
              onChangeText={setUsername}
              placeholder="maria.souza"
              placeholderTextColor={PLACEHOLDER_COLOR}
              autoCapitalize="none"
            />

            <Text style={styles.label}>Senha</Text>
            <TextInput
              style={styles.input}
              value={password}
              onChangeText={setPassword}
              placeholder="Minimo 8 caracteres"
              placeholderTextColor={PLACEHOLDER_COLOR}
              secureTextEntry
            />

            <TouchableOpacity
              style={[styles.saveBtn, saving && styles.btnDisabled]}
              onPress={handleCreateUser}
              disabled={saving}
            >
              <Text style={styles.saveBtnText}>{saving ? "Salvando..." : "Criar Usuario"}</Text>
            </TouchableOpacity>

            <TouchableOpacity style={styles.backBtn} onPress={() => navigation.goBack()}>
              <Text style={styles.backBtnText}>Voltar</Text>
            </TouchableOpacity>
          </View>
        }
        ListEmptyComponent={
          loading ? (
            <View style={styles.center}>
              <ActivityIndicator color="#1f4f7c" />
            </View>
          ) : (
            <Text style={styles.empty}>Nenhum usuario encontrado.</Text>
          )
        }
        renderItem={({ item }) => (
          <View style={styles.userCard}>
            <View style={styles.userTopRow}>
              <Text style={styles.userName}>{item.full_name}</Text>
              <View style={[styles.roleBadge, item.is_admin ? styles.adminBadge : styles.userBadge]}>
                <Text style={styles.roleBadgeText}>{item.is_admin ? "ADMIN" : "USER"}</Text>
              </View>
            </View>
            <Text style={styles.userMeta}>@{item.username}</Text>
            {item.email ? <Text style={styles.userMeta}>{item.email}</Text> : null}
            <Text style={styles.userMetaSmall}>Criado em: {new Date(item.created_at).toLocaleString("pt-BR")}</Text>
          </View>
        )}
      />

      {error ? (
        <View style={styles.errorBanner}>
          <Text style={styles.errorText}>{error}</Text>
        </View>
      ) : null}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: "#f8f9fb" },
  list: { padding: 16, paddingBottom: 24, gap: 10 },
  formCard: {
    backgroundColor: "white",
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "#e2e8f0",
    padding: 14,
    marginBottom: 12,
  },
  formTitle: { fontSize: 18, fontWeight: "700", color: "#17375e", marginBottom: 8 },
  label: { fontSize: 13, color: "#475569", fontWeight: "600", marginTop: 8 },
  input: {
    borderWidth: 1,
    borderColor: "#cbd5e1",
    borderRadius: 8,
    padding: 10,
    backgroundColor: "white",
    marginTop: 4,
    color: "#0f172a",
  },
  saveBtn: {
    marginTop: 12,
    backgroundColor: "#1f4f7c",
    borderRadius: 8,
    paddingVertical: 11,
    alignItems: "center",
  },
  saveBtnText: { color: "white", fontWeight: "700" },
  backBtn: {
    marginTop: 8,
    borderWidth: 1,
    borderColor: "#cbd5e1",
    borderRadius: 8,
    paddingVertical: 11,
    alignItems: "center",
  },
  backBtnText: { color: "#334155", fontWeight: "700" },
  btnDisabled: { opacity: 0.6 },
  userCard: {
    backgroundColor: "white",
    borderRadius: 10,
    borderWidth: 1,
    borderColor: "#e2e8f0",
    padding: 12,
    gap: 2,
  },
  userTopRow: { flexDirection: "row", justifyContent: "space-between", alignItems: "center" },
  userName: { fontSize: 15, fontWeight: "700", color: "#1e293b" },
  roleBadge: { borderRadius: 10, paddingHorizontal: 8, paddingVertical: 3 },
  adminBadge: { backgroundColor: "#fee2e2" },
  userBadge: { backgroundColor: "#e2e8f0" },
  roleBadgeText: { fontWeight: "700", fontSize: 11, color: "#334155" },
  userMeta: { fontSize: 13, color: "#64748b" },
  userMetaSmall: { fontSize: 12, color: "#94a3b8", marginTop: 2 },
  center: { padding: 20, alignItems: "center" },
  empty: { textAlign: "center", color: "#94a3b8", marginTop: 20 },
  errorBanner: {
    position: "absolute",
    bottom: 14,
    left: 14,
    right: 14,
    backgroundColor: "#fee2e2",
    borderRadius: 8,
    padding: 10,
  },
  errorText: { color: "#b91c1c", fontSize: 13 },
});
