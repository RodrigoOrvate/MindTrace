export type Species = {
  id: number;
  common_name: string;
  scientific_name: string | null;
};

export type Strain = {
  id: number;
  species_id: number;
  name: string;
  source: string | null;
};

export type Animal = {
  id: number;
  internal_id: string;
  status: "active" | "euthanized" | "deceased" | "archived";
  species_id: number;
  strain_id: number;
  sex: "male" | "female" | "unknown";
  entry_date: string;
  marking_date: string | null;
  initial_weight_g: number | null;
  euthanasia_date: string | null;
  euthanasia_reason: string | null;
  notes: string | null;
};

export type AnimalEvent = {
  id: number;
  animal_id: number;
  event_type: string;
  event_at: string;
  title: string;
  description?: string | null;
  payload?: Record<string, unknown> | null;
  source: string;
};

export type AuthMe = {
  username: string;
  full_name: string;
  email: string;
  is_admin: boolean;
  authenticated: boolean;
  client: string;
};

export type UserAccount = {
  id: number;
  full_name: string;
  email: string | null;
  username: string;
  is_admin: boolean;
  is_active: boolean;
  created_at: string;
};
