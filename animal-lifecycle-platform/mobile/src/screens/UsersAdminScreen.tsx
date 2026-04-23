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
import { LanguageCode, t } from "../utils/i18n";

const PLACEHOLDER_COLOR = "#b8c4d0";

type Props = { navigation: any; isDark?: boolean; language?: LanguageCode };

export default function UsersAdminScreen({ navigation, isDark = false, language = "pt" }: Props) {
  const colors = isDark
    ? { bg: "#0f172a", card: "#1e293b", border: "#334155", text: "#e2e8f0", textMuted: "#94a3b8", label: "#94a3b8", inputBg: "#1e293b", inputText: "#f1f5f9", inputBorder: "#475569" }
    : { bg: "#f8f9fb", card: "#ffffff", border: "#e2e8f0", text: "#0f172a", textMuted: "#64748b", label: "#475569", inputBg: "#ffffff", inputText: "#0f172a", inputBorder: "#cbd5e1" };
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
    <SafeAreaView style={[styles.container, { backgroundColor: colors.bg }]}>
      <FlatList
        data={users}
        keyExtractor={(item) => String(item.id)}
        contentContainerStyle={styles.list}
        ListHeaderComponent={
          <View style={[styles.formCard, { backgroundColor: colors.card, borderColor: colors.border }]}>
            <Text style={[styles.formTitle, { color: colors.text }]}>{t(language, "new_user")}</Text>

            <Text style={[styles.label, { color: colors.label }]}>{t(language, "full_name")}</Text>
            <TextInput
              style={[styles.input, { backgroundColor: colors.inputBg, color: colors.inputText, borderColor: colors.inputBorder }]}
              value={fullName}
              onChangeText={setFullName}
              placeholder="Ex: Maria Souza"
              placeholderTextColor={PLACEHOLDER_COLOR}
            />

            <Text style={[styles.label, { color: colors.label }]}>{t(language, "email_optional")}</Text>
            <TextInput
              style={[styles.input, { backgroundColor: colors.inputBg, color: colors.inputText, borderColor: colors.inputBorder }]}
              value={email}
              onChangeText={setEmail}
              placeholder="maria@lab.local"
              placeholderTextColor={PLACEHOLDER_COLOR}
              autoCapitalize="none"
              keyboardType="email-address"
            />

            <Text style={[styles.label, { color: colors.label }]}>{t(language, "username_label")}</Text>
            <TextInput
              style={[styles.input, { backgroundColor: colors.inputBg, color: colors.inputText, borderColor: colors.inputBorder }]}
              value={username}
              onChangeText={setUsername}
              placeholder="maria.souza"
              placeholderTextColor={PLACEHOLDER_COLOR}
              autoCapitalize="none"
            />

            <Text style={[styles.label, { color: colors.label }]}>{t(language, "password_label")}</Text>
            <TextInput
              style={[styles.input, { backgroundColor: colors.inputBg, color: colors.inputText, borderColor: colors.inputBorder }]}
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
              <Text style={styles.saveBtnText}>{saving ? t(language, "saving") : t(language, "create_user")}</Text>
            </TouchableOpacity>

            <TouchableOpacity style={styles.backBtn} onPress={() => navigation.goBack()}>
              <Text style={[styles.backBtnText, { color: isDark ? "#94a3b8" : "#334155" }]}>{t(language, "back")}</Text>
            </TouchableOpacity>
          </View>
        }
        ListEmptyComponent={
          loading ? (
            <View style={styles.center}>
              <ActivityIndicator color="#1f4f7c" />
            </View>
          ) : (
            <Text style={[styles.empty, { color: colors.textMuted }]}>{t(language, "no_users")}</Text>
          )
        }
        renderItem={({ item }) => (
          <View style={[styles.userCard, { backgroundColor: colors.card, borderColor: colors.border }]}>
            <View style={styles.userTopRow}>
              <Text style={[styles.userName, { color: colors.text }]}>{item.full_name}</Text>
              <View style={[styles.roleBadge, item.is_admin ? styles.adminBadge : styles.userBadge]}>
                <Text style={styles.roleBadgeText}>{item.is_admin ? "ADMIN" : "USER"}</Text>
              </View>
            </View>
            <Text style={[styles.userMeta, { color: colors.textMuted }]}>@{item.username}</Text>
            {item.email ? <Text style={[styles.userMeta, { color: colors.textMuted }]}>{item.email}</Text> : null}
            <Text style={[styles.userMetaSmall, { color: colors.textMuted }]}>Criado em: {new Date(item.created_at).toLocaleString("pt-BR")}</Text>
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
