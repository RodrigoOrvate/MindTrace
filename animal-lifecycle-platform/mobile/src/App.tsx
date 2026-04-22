import React from "react";
import { AppState, Platform, StyleSheet, Text, TouchableOpacity, View } from "react-native";
import { NavigationContainer } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { StatusBar } from "expo-status-bar";

import { login, me, setAuthToken } from "./api/client";
import { AuthMe } from "./types";
import AnimalTimelineScreen from "./screens/AnimalTimelineScreen";
import AnimalsListScreen from "./screens/AnimalsListScreen";
import LoginScreen from "./screens/LoginScreen";
import NewAnimalScreen from "./screens/NewAnimalScreen";
import UsersAdminScreen from "./screens/UsersAdminScreen";

const Stack = createNativeStackNavigator();
const INACTIVITY_MS = 30 * 60 * 1000;

export default function App() {
  const [token, setToken] = React.useState<string | null>(null);
  const [currentUser, setCurrentUser] = React.useState<AuthMe | null>(null);
  const [authError, setAuthError] = React.useState<string | null>(null);
  const timeoutRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);
  const backgroundAtRef = React.useRef<number | null>(null);

  React.useEffect(() => {
    setAuthToken(token);
  }, [token]);

  const handleLogout = React.useCallback(() => {
    setToken(null);
    setCurrentUser(null);
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

  async function handleLogin(username: string, password: string) {
    try {
      setAuthError(null);
      const result = await login(username, password);
      setToken(result.access_token);
      setAuthToken(result.access_token);
      const profile = await me();
      setCurrentUser(profile);
      resetInactivityTimer();
    } catch (err) {
      setToken(null);
      setCurrentUser(null);
      setAuthToken(null);
      setAuthError((err as Error).message || "Falha de autenticacao.");
      throw err;
    }
  }

  const loggedIn = !!token;
  const isAdmin = !!currentUser?.is_admin;

  const headerRight = () => (
    <TouchableOpacity style={styles.logoutBtn} onPress={handleLogout}>
      <Text style={styles.logoutText}>{"-> Sair"}</Text>
    </TouchableOpacity>
  );

  return (
    <View
      style={styles.root}
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
        <StatusBar style="dark" />
        <Stack.Navigator screenOptions={{ headerShown: loggedIn }}>
          {!loggedIn ? (
            <Stack.Screen name="Login" options={{ headerShown: false }}>
              {() => <LoginScreen onSubmit={handleLogin} error={authError} />}
            </Stack.Screen>
          ) : (
            <>
              <Stack.Screen
                name="Animals"
                options={{ title: "Animais", headerRight }}
              >
                {(props) => <AnimalsListScreen {...props} isAdmin={isAdmin} />}
              </Stack.Screen>
              <Stack.Screen
                name="NewAnimal"
                component={NewAnimalScreen}
                options={{ title: "Novo Animal", headerRight }}
              />
              <Stack.Screen
                name="Timeline"
                component={AnimalTimelineScreen}
                options={{ title: "Timeline", headerRight }}
              />
              {isAdmin ? (
                <Stack.Screen
                  name="UsersAdmin"
                  component={UsersAdminScreen}
                  options={{ title: "Usuarios", headerRight }}
                />
              ) : null}
            </>
          )}
        </Stack.Navigator>
      </NavigationContainer>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
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
