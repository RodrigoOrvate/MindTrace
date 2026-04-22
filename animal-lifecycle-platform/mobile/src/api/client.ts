import { Animal, AnimalEvent, AuthMe, Species, Strain, UserAccount } from "../types";

const API_BASE = (process.env.EXPO_PUBLIC_API_BASE_URL || "http://localhost:8000").replace(/\/+$/, "");

let authToken: string | null = null;

export function setAuthToken(token: string | null): void {
  authToken = token;
}

function authHeaders(): Record<string, string> {
  if (!authToken) return {};
  return { Authorization: `Bearer ${authToken}` };
}

async function readError(res: Response, fallback: string): Promise<never> {
  const body = await res.json().catch(() => ({}));
  const detail = body?.detail || fallback;
  const err = new Error(detail) as Error & { status?: number };
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
