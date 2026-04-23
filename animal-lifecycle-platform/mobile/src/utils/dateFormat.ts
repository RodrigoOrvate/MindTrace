export type DateFormat = "DD/MM/YYYY" | "MM/DD/YYYY" | "YYYY-MM-DD";

function splitIsoDate(iso: string): { y: string; m: string; d: string } | null {
  const parts = String(iso || "").split("-");
  if (parts.length !== 3) return null;
  const [y, m, d] = parts;
  if (y.length !== 4 || m.length !== 2 || d.length < 2) return null;
  return { y, m, d: d.slice(0, 2) };
}

export function formatDateOnly(iso: string, format: DateFormat): string {
  const parts = splitIsoDate(iso);
  if (!parts) return iso;
  if (format === "YYYY-MM-DD") return `${parts.y}-${parts.m}-${parts.d}`;
  if (format === "MM/DD/YYYY") return `${parts.m}/${parts.d}/${parts.y}`;
  return `${parts.d}/${parts.m}/${parts.y}`;
}

export function formatDateTime(value: string, format: DateFormat): string {
  const raw = String(value || "").trim();
  if (!raw) return "";
  const normalized = /([zZ]|[+\-]\d{2}:\d{2})$/.test(raw) ? raw : `${raw}Z`;
  const dt = new Date(normalized);
  if (Number.isNaN(dt.getTime())) return value;
  const y = String(dt.getFullYear());
  const m = String(dt.getMonth() + 1).padStart(2, "0");
  const d = String(dt.getDate()).padStart(2, "0");
  const hh = String(dt.getHours()).padStart(2, "0");
  const mm = String(dt.getMinutes()).padStart(2, "0");
  const dateText = formatDateOnly(`${y}-${m}-${d}`, format);
  return `${dateText}, ${hh}:${mm}`;
}
