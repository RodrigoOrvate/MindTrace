import { Animal, AnimalEvent, AppSettings, AuthMe, Species, Strain, UserAccount } from "../types";

const API_BASE = (process.env.EXPO_PUBLIC_API_BASE_URL || "http://localhost:8000").replace(/\/+$/, "");

let authToken: string | null = null;

export function setAuthToken(token: string | null): void {
  authToken = token;
}

function authHeaders(): Record<string, string> {
  if (!authToken) return {};
  return { Authorization: `Bearer ${authToken}` };
}

function stringifyDetail(detail: unknown, fallback: string): string {
  if (typeof detail === "string") {
    const trimmed = detail.trim();
    return trimmed || fallback;
  }
  if (Array.isArray(detail)) {
    const joined = detail
      .map((entry) => {
        if (typeof entry === "string") return entry;
        if (entry && typeof entry === "object" && "msg" in entry) return String((entry as { msg?: unknown }).msg ?? "");
        return "";
      })
      .filter(Boolean)
      .join("; ");
    return joined || fallback;
  }
  if (detail && typeof detail === "object") {
    const maybeDetail = (detail as { detail?: unknown }).detail;
    if (maybeDetail !== undefined) return stringifyDetail(maybeDetail, fallback);
    const maybeMessage = (detail as { message?: unknown }).message;
    if (typeof maybeMessage === "string" && maybeMessage.trim()) return maybeMessage.trim();
  }
  return fallback;
}

async function readError(res: Response, fallback: string): Promise<never> {
  const body = await res.json().catch(() => ({}));
  const message = stringifyDetail(body?.detail, fallback);
  const err = new Error(message) as Error & { status?: number };
  err.status = res.status;
  throw err;
}

async function getJson<T>(url: string): Promise<T> {
  const res = await fetch(url, { headers: { ...authHeaders() } });
  if (!res.ok) return readError(res, "Falha na requisicao.");
  return res.json() as Promise<T>;
}

export async function login(username: string, password: string): Promise<{ access_token: string; username: string }> {
  const res = await fetch(`${API_BASE}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password }),
  });
  if (!res.ok) return readError(res, "Falha no login.");
  return res.json();
}

function asBool(value: unknown): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") return value.trim().toLowerCase() === "true";
  return false;
}

export async function me(): Promise<AuthMe> {
  const raw = await getJson<Record<string, unknown>>(`${API_BASE}/auth/me`);
  return {
    username: String(raw.username ?? ""),
    full_name: String(raw.full_name ?? ""),
    email: String(raw.email ?? ""),
    is_admin: asBool(raw.is_admin),
    authenticated: asBool(raw.authenticated),
    client: String(raw.client ?? ""),
    theme: String(raw.theme ?? "light") as "light" | "dark",
    language: String(raw.language ?? "pt") as "pt" | "en" | "es",
  };
}

export async function listAnimals(query?: string): Promise<Animal[]> {
  const url = query ? `${API_BASE}/animals?q=${encodeURIComponent(query)}` : `${API_BASE}/animals`;
  return getJson<Animal[]>(url);
}

export async function createAnimal(payload: {
  entry_date: string;
  species_id: number;
  strain_id: number;
  sex: "male" | "female" | "unknown";
  marking_date?: string;
  initial_weight_g?: number;
  id_cc: string;
  rr_override?: number;
}): Promise<Animal> {
  const res = await fetch(`${API_BASE}/animals`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify(payload),
  });
  if (!res.ok) return readError(res, "Falha ao cadastrar animal.");
  return res.json();
}

export async function deleteAnimal(animalId: number): Promise<void> {
  const res = await fetch(`${API_BASE}/animals/${animalId}`, { method: "DELETE", headers: { ...authHeaders() } });
  if (!res.ok) {
    await readError(res, `Falha ao excluir animal (HTTP ${res.status}).`);
  }
}

export async function deleteAnimalEvent(animalId: number, eventId: number): Promise<void> {
  const res = await fetch(`${API_BASE}/animals/${animalId}/events/${eventId}`, {
    method: "DELETE",
    headers: { ...authHeaders() },
  });
  if (!res.ok) {
    await readError(res, `Falha ao excluir evento (HTTP ${res.status}).`);
  }
}

export async function addAnimalEvent(
  animalId: number,
  payload: { event_type: string; title: string; description?: string; payload?: Record<string, unknown> }
): Promise<AnimalEvent> {
  const res = await fetch(`${API_BASE}/animals/${animalId}/events`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify({ ...payload, source: "app" }),
  });
  if (!res.ok) return readError(res, "Falha ao registrar evento.");
  return res.json();
}

export async function euthanizeAnimal(
  animalId: number,
  payload: { date: string; reason: string; method?: string; notes?: string }
): Promise<AnimalEvent> {
  const res = await fetch(`${API_BASE}/animals/${animalId}/euthanasia`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify(payload),
  });
  if (!res.ok) return readError(res, "Falha ao registrar eutanasia.");
  return res.json();
}

export async function bulkEuthanasia(payload: {
  entry_date: string;
  euthanasia_date: string;
  animal_ids: number[];
  reason: string;
  method?: string;
  notes?: string;
}): Promise<{ requested: number; euthanized: number; skipped: number; details: string[] }> {
  const res = await fetch(`${API_BASE}/animals/euthanasia/bulk`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify(payload),
  });
  if (!res.ok) return readError(res, "Falha na eutanasia em grupo.");
  return res.json();
}

export async function getAnimal(animalId: number): Promise<Animal> {
  return getJson<Animal>(`${API_BASE}/animals/${animalId}`);
}

export async function animalTimeline(animalId: number): Promise<AnimalEvent[]> {
  return getJson<AnimalEvent[]>(`${API_BASE}/animals/${animalId}/events`);
}

export async function fetchSpecies(): Promise<Species[]> {
  return getJson<Species[]>(`${API_BASE}/lookups/species`);
}

export async function fetchStrains(speciesId: number): Promise<Strain[]> {
  return getJson<Strain[]>(`${API_BASE}/lookups/strains?species_id=${speciesId}`);
}

export async function listUsers(): Promise<UserAccount[]> {
  return getJson<UserAccount[]>(`${API_BASE}/auth/users`);
}

export async function createUser(payload: {
  full_name: string;
  email?: string;
  username: string;
  password: string;
  is_admin: boolean;
}): Promise<UserAccount> {
  const res = await fetch(`${API_BASE}/auth/users`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify(payload),
  });
  if (!res.ok) return readError(res, "Falha ao criar usuario.");
  return res.json();
}

export async function getSettings(): Promise<AppSettings> {
  return getJson<AppSettings>(`${API_BASE}/auth/settings`);
}

export async function updateMyPreferences(payload: {
  theme?: "light" | "dark";
  language?: "pt" | "en" | "es";
}): Promise<AppSettings> {
  const res = await fetch(`${API_BASE}/auth/settings/preferences`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify(payload),
  });
  if (!res.ok) return readError(res, "Falha ao atualizar preferencias.");
  return res.json();
}

export async function updateGlobalDateFormat(dateFormat: AppSettings["date_format"]): Promise<AppSettings> {
  const res = await fetch(`${API_BASE}/auth/settings/date-format`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify({ date_format: dateFormat }),
  });
  if (!res.ok) return readError(res, "Falha ao atualizar formato global de data.");
  return res.json();
}
