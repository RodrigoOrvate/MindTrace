import React from "react";
import { AppState, Platform, StyleSheet, Text, TouchableOpacity, View } from "react-native";
import { NavigationContainer } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { StatusBar } from "expo-status-bar";

import { getSettings, login, me, setAuthToken, updateGlobalDateFormat, updateMyPreferences } from "./api/client";
import { AppSettings, AuthMe } from "./types";
import AnimalsListScreen from "./screens/AnimalsListScreen";
import AnimalTimelineScreen from "./screens/AnimalTimelineScreen";
import LoginScreen from "./screens/LoginScreen";
import NewAnimalScreen from "./screens/NewAnimalScreen";
import SettingsScreen from "./screens/SettingsScreen";
import UsersAdminScreen from "./screens/UsersAdminScreen";
import { DateFormat } from "./utils/dateFormat";
import { LanguageCode, t } from "./utils/i18n";

const Stack = createNativeStackNavigator();
const INACTIVITY_MS = 30 * 60 * 1000;

const DEFAULT_SETTINGS: AppSettings = {
  theme: "light",
  language: "pt",
  date_format: "DD/MM/YYYY",
  is_admin: false,
};

export default function App() {
  const [token, setToken] = React.useState<string | null>(null);
  const [currentUser, setCurrentUser] = React.useState<AuthMe | null>(null);
  const [settings, setSettings] = React.useState<AppSettings>(DEFAULT_SETTINGS);
  const [authError, setAuthError] = React.useState<string | null>(null);
  const timeoutRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);
  const backgroundAtRef = React.useRef<number | null>(null);

  React.useEffect(() => {
    setAuthToken(token);
  }, [token]);

  const handleLogout = React.useCallback(() => {
    setToken(null);
    setCurrentUser(null);
    setSettings(DEFAULT_SETTINGS);
    setAuthToken(null);
  }, []);

  const resetInactivityTimer = React.useCallback(() => {
    if (!token) return;
    if (timeoutRef.current) clearTimeout(timeoutRef.current);
    timeoutRef.current = setTimeout(() => {
      handleLogout();
    }, INACTIVITY_MS);
  }, [handleLogout, token]);

  React.useEffect(() => {
    if (!token) {
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
      timeoutRef.current = null;
      return;
    }

    resetInactivityTimer();

    const appStateSub = AppState.addEventListener("change", (nextState) => {
      if (nextState === "background" || nextState === "inactive") {
        backgroundAtRef.current = Date.now();
      } else if (nextState === "active") {
        const bgAt = backgroundAtRef.current;
        if (bgAt && Date.now() - bgAt >= INACTIVITY_MS) {
          handleLogout();
          return;
        }
        resetInactivityTimer();
      }
    });

    let removeWebListeners: (() => void) | undefined;
    if (Platform.OS === "web" && typeof document !== "undefined") {
      const bump = () => resetInactivityTimer();
      const events: Array<keyof DocumentEventMap> = ["click", "keydown", "mousemove", "touchstart", "scroll"];
      events.forEach((eventName) => document.addEventListener(eventName, bump, { passive: true }));
      removeWebListeners = () => {
        events.forEach((eventName) => document.removeEventListener(eventName, bump));
      };
    }

    return () => {
      appStateSub.remove();
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
      timeoutRef.current = null;
      if (removeWebListeners) removeWebListeners();
    };
  }, [handleLogout, resetInactivityTimer, token]);

  async function refreshSettings() {
    const loaded = await getSettings();
    setSettings(loaded);
  }

  async function handleLogin(username: string, password: string) {
    try {
      setAuthError(null);
      const result = await login(username, password);
      setToken(result.access_token);
      setAuthToken(result.access_token);
      const profile = await me();
      setCurrentUser(profile);
      await refreshSettings();
      resetInactivityTimer();
    } catch (err) {
      setToken(null);
      setCurrentUser(null);
      setSettings(DEFAULT_SETTINGS);
      setAuthToken(null);
      setAuthError((err as Error).message || "Falha de autenticacao.");
      throw err;
    }
  }

  async function savePreferences(payload: { theme?: "light" | "dark"; language?: LanguageCode }) {
    const updated = await updateMyPreferences(payload);
    setSettings(updated);
  }

  async function saveGlobalDateFormat(value: DateFormat) {
    const updated = await updateGlobalDateFormat(value);
    setSettings(updated);
  }

  const loggedIn = !!token;
  const isAdmin = !!currentUser?.is_admin;
  const language = settings.language || "pt";
  const isDark = settings.theme === "dark";

  const headerActions = (navigation: any) => (
    <View style={styles.headerRightWrap}>
      <TouchableOpacity style={styles.headerIconBtn} onPress={() => navigation.navigate("Settings")}>
        <Text style={styles.headerIcon}>⚙</Text>
      </TouchableOpacity>
      <TouchableOpacity style={styles.logoutBtn} onPress={handleLogout}>
        <Text style={styles.logoutText}>{t(language, "logout")}</Text>
      </TouchableOpacity>
    </View>
  );

  return (
    <View
      style={[styles.root, { backgroundColor: isDark ? "#0f172a" : "#f8f9fb" }]}
      onStartShouldSetResponderCapture={() => {
        resetInactivityTimer();
        return false;
      }}
      onMoveShouldSetResponderCapture={() => {
        resetInactivityTimer();
        return false;
      }}
    >
      <NavigationContainer
        onStateChange={() => {
          resetInactivityTimer();
        }}
      >
        <StatusBar style={isDark ? "light" : "dark"} />
        <Stack.Navigator screenOptions={{ headerShown: loggedIn }}>
          {!loggedIn ? (
            <Stack.Screen name="Login" options={{ headerShown: false }}>
              {() => <LoginScreen onSubmit={handleLogin} error={authError} />}
            </Stack.Screen>
          ) : (
            <>
              <Stack.Screen
                name="Animals"
                options={({ navigation }) => ({
                  title: t(language, "animals"),
                  headerRight: () => headerActions(navigation),
                })}
              >
                {(props) => (
                  <AnimalsListScreen
                    {...props}
                    isAdmin={isAdmin}
                    isDark={isDark}
                    language={language}
                    dateFormat={settings.date_format}
                  />
                )}
              </Stack.Screen>
              <Stack.Screen
                name="NewAnimal"
                options={({ navigation }) => ({
                  title: t(language, "new_animal"),
                  headerRight: () => headerActions(navigation),
                })}
              >
                {(props) => (
                  <NewAnimalScreen
                    {...props}
                    isDark={isDark}
                    language={language}
                    dateFormat={settings.date_format}
                  />
                )}
              </Stack.Screen>
              <Stack.Screen
                name="Timeline"
                options={({ navigation }) => ({
                  title: t(language, "timeline"),
                  headerRight: () => headerActions(navigation),
                })}
              >
                {(props) => <AnimalTimelineScreen {...props} isDark={isDark} dateFormat={settings.date_format} />}
              </Stack.Screen>
              {isAdmin ? (
                <Stack.Screen
                  name="UsersAdmin"
                  options={({ navigation }) => ({
                    title: t(language, "users"),
                    headerRight: () => headerActions(navigation),
                  })}
                >
                  {(props) => (
                    <UsersAdminScreen {...props} isDark={isDark} language={language} />
                  )}
                </Stack.Screen>
              ) : null}
              <Stack.Screen
                name="Settings"
                options={({ navigation }) => ({
                  title: t(language, "settings"),
                  headerRight: () => (
                    <TouchableOpacity style={styles.logoutBtn} onPress={handleLogout}>
                      <Text style={styles.logoutText}>{t(language, "logout")}</Text>
                    </TouchableOpacity>
                  ),
                })}
              >
                {(props) => (
                  <SettingsScreen
                    {...props}
                    settings={{ ...settings, is_admin: isAdmin }}
                    onUpdatePreferences={savePreferences}
                    onUpdateDateFormat={saveGlobalDateFormat}
                  />
                )}
              </Stack.Screen>
            </>
          )}
        </Stack.Navigator>
      </NavigationContainer>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  headerRightWrap: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
  },
  headerIconBtn: {
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  headerIcon: {
    fontSize: 18,
    color: "#334155",
  },
  logoutBtn: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  logoutText: {
    color: "#b91c1c",
    fontWeight: "700",
    fontSize: 13,
  },
});
