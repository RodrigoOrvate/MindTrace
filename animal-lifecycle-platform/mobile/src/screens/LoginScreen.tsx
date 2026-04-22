import React, { useState } from "react";
import { ActivityIndicator, SafeAreaView, StyleSheet, Text, TextInput, TouchableOpacity, View } from "react-native";

type Props = {
  onSubmit: (username: string, password: string) => Promise<void>;
  error: string | null;
};

export default function LoginScreen({ onSubmit, error }: Props) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleLogin() {
    if (!username.trim() || !password) return;
    setLoading(true);
    try {
      await onSubmit(username.trim(), password);
      setPassword("");
    } finally {
      setLoading(false);
    }
  }

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.card}>
        <Text style={styles.title}>Acesso Restrito</Text>
        <Text style={styles.subtitle}>
          Entre com seu usuário local para acessar os dados dos animais.
        </Text>

        <Text style={styles.label}>Usuário</Text>
        <TextInput
          style={styles.input}
          autoCapitalize="none"
          value={username}
          onChangeText={setUsername}
          placeholder="seu.usuario"
          placeholderTextColor="#94a3b8"
        />

        <Text style={styles.label}>Senha</Text>
        <TextInput
          style={styles.input}
          secureTextEntry
          value={password}
          onChangeText={setPassword}
          placeholder="********"
          placeholderTextColor="#94a3b8"
          onSubmitEditing={handleLogin}
        />

        {error ? <Text style={styles.error}>{error}</Text> : null}

        <TouchableOpacity
          style={[styles.btn, (!username.trim() || !password || loading) && styles.btnDisabled]}
          onPress={handleLogin}
          disabled={!username.trim() || !password || loading}
        >
          {loading ? <ActivityIndicator color="#fff" /> : <Text style={styles.btnText}>Entrar</Text>}
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#eef2f7",
    justifyContent: "center",
    padding: 16,
  },
  card: {
    backgroundColor: "#ffffff",
    borderRadius: 16,
    borderWidth: 1,
    borderColor: "#e2e8f0",
    padding: 20,
    gap: 8,
  },
  title: { fontSize: 24, fontWeight: "700", color: "#17375e" },
  subtitle: { fontSize: 14, color: "#64748b", marginBottom: 6 },
  label: { fontSize: 13, color: "#475569", fontWeight: "600", marginTop: 8 },
  input: {
    borderWidth: 1,
    borderColor: "#cbd5e1",
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 10,
    color: "#0f172a",
    backgroundColor: "#fff",
  },
  error: { color: "#b91c1c", marginTop: 4, fontSize: 13 },
  btn: {
    marginTop: 14,
    backgroundColor: "#1f4f7c",
    borderRadius: 10,
    alignItems: "center",
    justifyContent: "center",
    minHeight: 44,
  },
  btnDisabled: { opacity: 0.5 },
  btnText: { color: "#fff", fontWeight: "700", fontSize: 15 },
});
