import React, { useEffect, useState } from "react";
import {
  ActivityIndicator,
  FlatList,
  Modal,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from "react-native";

import {
  addAnimalEvent,
  animalTimeline,
  deleteAnimal,
  deleteAnimalEvent,
  fetchSpecies,
  fetchStrains,
  getAnimal,
} from "../api/client";
import { Animal, AnimalEvent, Species, Strain } from "../types";

type Props = { route: any; navigation: any };
type Tab = "history" | "profile";

const PLACEHOLDER_COLOR = "#b8c4d0";

const EVENT_CONFIG: Record<string, { icon: string; color: string; label: string }> = {
  entry:                 { icon: "->", color: "#16a34a", label: "Entrada" },
  weight:                { icon: "W", color: "#2563eb", label: "Pesagem" },
  health:                { icon: "+", color: "#d97706", label: "Saude" },
  experiment_session:    { icon: "EXP", color: "#7c3aed", label: "Experimento" },
  experiment_enrollment: { icon: "ENR", color: "#0891b2", label: "Matricula" },
  euthanasia:            { icon: "X", color: "#dc2626", label: "Eutanasia" },
  note:                  { icon: "N", color: "#64748b", label: "Nota" },
  transfer:              { icon: "<>", color: "#ea580c", label: "Transferencia" },
};

const APPARATUS_OPTIONS = [
  { value: "nor",                   label: "NOR" },
  { value: "campo_aberto",          label: "CA" },
  { value: "comportamento_complexo",label: "CC" },
  { value: "esquiva_inibitoria",    label: "EI" },
] as const;
type ApparatusValue = typeof APPARATUS_OPTIONS[number]["value"];

const ADD_EVENT_TYPES = [
  { value: "note",        label: "Nota" },
  { value: "weight",      label: "Pesagem" },
  { value: "health",      label: "Saude" },
  { value: "experiment",  label: "Experimento" },
] as const;
type AddEventType = typeof ADD_EVENT_TYPES[number]["value"];

const SEX_LABEL: Record<Animal["sex"], string> = {
  male: "Macho",
  female: "Femea",
  unknown: "Nao def.",
};

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

function isAudit(event: AnimalEvent): boolean {
  return !!(event.payload?.audit);
}

function apparatusLabel(payload?: Record<string, unknown> | null): string {
  if (!payload) return "";
  const ap = payload.apparatus ?? payload.context ?? "";
  const map: Record<string, string> = {
    nor: "NOR", campo_aberto: "CA", comportamento_complexo: "CC", esquiva_inibitoria: "EI",
  };
  return map[String(ap)] ?? "";
}

function asNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function asText(value: unknown): string {
  if (value == null) return "";
  return String(value).trim();
}

function metricRowsForExperiment(payload: Record<string, unknown> | null | undefined, apLabel: string): string[][] {
  if (!payload || !apLabel) return [];

  const rows: string[][] = [];
  const day = asText(payload.day);
  const field = asNumber(payload.field);
  const treatment = asText(payload.treatment);
  const distanceM = asNumber(payload.distance_m);
  const speed = asNumber(payload.avg_speed_ms ?? payload.velocity_ms);

  if (apLabel === "NOR") {
    const pair = asText(payload.pair);
    const a = asNumber(payload.exploration_a_s);
    const b = asNumber(payload.exploration_b_s);
    const di = asNumber(payload.di);
    rows.push([
      field != null ? `Campo C${field}` : "",
      pair ? `Par ${pair}` : "",
      day ? `Dia ${day}` : "",
    ].filter(Boolean));
    rows.push([
      a != null ? `Obj A: ${a.toFixed(2)}s` : "",
      b != null ? `Obj B: ${b.toFixed(2)}s` : "",
      di != null ? `DI: ${di.toFixed(3)}` : "",
    ].filter(Boolean));
    rows.push([
      distanceM != null ? `Dist: ${distanceM.toFixed(3)}m` : "",
      speed != null ? `Vel: ${speed.toFixed(3)}m/s` : "",
      treatment ? `Trat: ${treatment}` : "",
    ].filter(Boolean));
    return rows.filter((r) => r.length > 0);
  }

  if (apLabel === "CA") {
    const center = asNumber(payload.tempo_centro_s);
    const border = asNumber(payload.tempo_borda_s);
    const visits = asNumber(payload.visitas_centro);
    rows.push([
      field != null ? `Campo C${field}` : "",
      day ? `Dia ${day}` : "",
      visits != null ? `Visitas centro: ${visits}` : "",
    ].filter(Boolean));
    rows.push([
      center != null ? `Tempo centro: ${center.toFixed(2)}s` : "",
      border != null ? `Tempo borda: ${border.toFixed(2)}s` : "",
    ].filter(Boolean));
    rows.push([
      distanceM != null ? `Dist: ${distanceM.toFixed(3)}m` : "",
      speed != null ? `Vel: ${speed.toFixed(3)}m/s` : "",
      treatment ? `Trat: ${treatment}` : "",
    ].filter(Boolean));
    return rows.filter((r) => r.length > 0);
  }

  if (apLabel === "CC") {
    const minutes = asNumber(payload.session_minutes);
    const w = asNumber(payload.behavior_walking);
    const s = asNumber(payload.behavior_sniffing);
    const g = asNumber(payload.behavior_grooming);
    const r = asNumber(payload.behavior_resting);
    const re = asNumber(payload.behavior_rearing);
    rows.push([
      field != null ? `Campo C${field}` : "",
      day ? `Dia ${day}` : "",
      minutes != null ? `Sessao: ${minutes} min` : "",
    ].filter(Boolean));
    rows.push([
      distanceM != null ? `Dist: ${distanceM.toFixed(3)}m` : "",
      speed != null ? `Vel: ${speed.toFixed(3)}m/s` : "",
      treatment ? `Trat: ${treatment}` : "",
    ].filter(Boolean));
    rows.push([
      w != null ? `Walk ${w}` : "",
      s != null ? `Sniff ${s}` : "",
      g != null ? `Groom ${g}` : "",
      r != null ? `Rest ${r}` : "",
      re != null ? `Rear ${re}` : "",
    ].filter(Boolean));
    return rows.filter((r) => r.length > 0);
  }

  if (apLabel === "EI") {
    const lat = asNumber(payload.latencia_s);
    const plat = asNumber(payload.tempo_plataforma_s);
    const grid = asNumber(payload.tempo_grade_s);
    const bp = asNumber(payload.bouts_plataforma);
    const bg = asNumber(payload.bouts_grade);
    rows.push([
      day ? `Dia ${day}` : "",
      field != null ? `Campo C${field}` : "",
      lat != null ? `Latencia: ${lat.toFixed(2)}s` : "",
    ].filter(Boolean));
    rows.push([
      plat != null ? `Plataforma: ${plat.toFixed(2)}s` : "",
      grid != null ? `Grade: ${grid.toFixed(2)}s` : "",
      bp != null ? `Bouts P: ${bp}` : "",
      bg != null ? `Bouts G: ${bg}` : "",
    ].filter(Boolean));
    rows.push([
      distanceM != null ? `Dist: ${distanceM.toFixed(3)}m` : "",
      speed != null ? `Vel: ${speed.toFixed(3)}m/s` : "",
      treatment ? `Trat: ${treatment}` : "",
    ].filter(Boolean));
    return rows.filter((r) => r.length > 0);
  }

  return [];
}

function formatDate(iso: string): string {
  try {
    return new Date(iso).toLocaleString("pt-BR", {
      day: "2-digit", month: "2-digit", year: "numeric",
      hour: "2-digit", minute: "2-digit",
    });
  } catch { return iso; }
}

function formatDateOnly(iso: string): string {
  try {
    const [year, month, day] = iso.split("-");
    return `${day}/${month}/${year}`;
  } catch { return iso; }
}

// Delete Animal Modal
function DeleteAnimalModal({
  visible, animalCode, onCancel, onConfirm,
}: { visible: boolean; animalCode: string; onCancel: () => void; onConfirm: () => void }) {
  const [typed, setTyped] = useState("");
  const match = typed.trim().toUpperCase() === animalCode.trim().toUpperCase();

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onCancel}>
      <View style={modal.overlay}>
        <View style={modal.box}>
          <Text style={modal.title}>Excluir Animal</Text>
          <Text style={modal.warn}>
            Esta acao e <Text style={modal.warnBold}>irreversivel</Text>.{"\n"}
            Todo o historico sera apagado permanentemente.
          </Text>
          <Text style={modal.label}>Para confirmar, digite o ID do animal:</Text>
          <Text style={modal.codeHint}>{animalCode}</Text>
          <TextInput
            style={[modal.input, match && modal.inputMatch]}
            placeholder="Digite o ID exato"
            placeholderTextColor={PLACEHOLDER_COLOR}
            value={typed}
            onChangeText={setTyped}
            autoCapitalize="characters"
          />
          <View style={modal.btnRow}>
            <TouchableOpacity style={modal.cancelBtn} onPress={onCancel}>
              <Text style={modal.cancelText}>Cancelar</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[modal.deleteBtn, !match && modal.btnDisabled]}
              onPress={() => { if (match) onConfirm(); }}
              disabled={!match}
            >
              <Text style={modal.deleteBtnText}>Excluir</Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </Modal>
  );
}

// Add Event Modal
function AddEventModal({
  visible, onCancel, onSave,
}: {
  visible: boolean;
  onCancel: () => void;
  onSave: (type: string, title: string, description: string, extra?: Record<string, unknown>) => Promise<void>;
}) {
  const [eventType, setEventType] = useState<AddEventType>("note");
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [weight, setWeight] = useState("");
  const [apparatus, setApparatus] = useState<ApparatusValue>("nor");
  const [fase, setFase] = useState("");
  const [saving, setSaving] = useState(false);

  function reset() {
    setEventType("note"); setTitle(""); setDescription("");
    setWeight(""); setApparatus("nor"); setFase("");
  }

  function autoTitle(): string {
    if (eventType !== "experiment") return title;
    const ap = APPARATUS_OPTIONS.find((o) => o.value === apparatus)?.label ?? apparatus.toUpperCase();
    return fase.trim() ? `${ap} - ${fase.trim()}` : ap;
  }

  async function handleSave() {
    const finalTitle = eventType === "experiment" ? autoTitle() : title.trim();
    if (!finalTitle) return;
    setSaving(true);
    try {
      let extra: Record<string, unknown> | undefined;
      if (eventType === "weight" && weight) extra = { weight_g: Number(weight) };
      if (eventType === "experiment") extra = { apparatus, day: fase.trim() || undefined };
      await onSave(
        eventType === "experiment" ? "experiment_session" : eventType,
        finalTitle,
        description.trim(),
        extra,
      );
      reset();
    } finally { setSaving(false); }
  }

  const isExperiment = eventType === "experiment";
  const titlePlaceholder =
    eventType === "weight" ? "Ex: Pesagem semanal" :
    eventType === "health" ? "Ex: Observacao clinica" :
    "Ex: Inicio do protocolo";
  const canSave = isExperiment ? true : !!title.trim();

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onCancel}>
      <View style={modal.overlay}>
        <View style={modal.box}>
          <Text style={modal.title}>Adicionar ao Historico</Text>

          <Text style={modal.label}>Tipo</Text>
          <View style={styles.chipRow}>
            {ADD_EVENT_TYPES.map((opt) => {
              const active = eventType === opt.value;
              return (
                <TouchableOpacity
                  key={opt.value}
                  style={[styles.chip, active && styles.chipActive]}
                  onPress={() => setEventType(opt.value)}
                >
                  <Text style={[styles.chipText, active && styles.chipTextActive]}>{opt.label}</Text>
                </TouchableOpacity>
              );
            })}
          </View>

          {isExperiment ? (
            <>
              <Text style={modal.label}>Aparato</Text>
              <View style={styles.chipRow}>
                {APPARATUS_OPTIONS.map((opt) => {
                  const active = apparatus === opt.value;
                  return (
                    <TouchableOpacity
                      key={opt.value}
                      style={[styles.chip, active && styles.chipExperiment]}
                      onPress={() => setApparatus(opt.value)}
                    >
                      <Text style={[styles.chipText, active && styles.chipTextActive]}>{opt.label}</Text>
                    </TouchableOpacity>
                  );
                })}
              </View>
              <Text style={modal.label}>Fase / Dia <Text style={styles.optional}>(opcional)</Text></Text>
              <TextInput
                style={modal.input}
                placeholder="Ex: Treino, Teste, E1..."
                placeholderTextColor={PLACEHOLDER_COLOR}
                value={fase}
                onChangeText={setFase}
              />
              <Text style={[modal.label, { fontSize: 11, color: "#94a3b8", marginTop: 2 }]}>
                Titulo gerado: {autoTitle()}
              </Text>
            </>
          ) : (
            <>
              <Text style={modal.label}>Titulo</Text>
              <TextInput
                style={modal.input}
                placeholder={titlePlaceholder}
                placeholderTextColor={PLACEHOLDER_COLOR}
                value={title}
                onChangeText={setTitle}
              />
              {eventType === "weight" && (
                <>
                  <Text style={modal.label}>Peso (g)</Text>
                  <TextInput
                    style={modal.input}
                    placeholder="Ex: 280"
                    placeholderTextColor={PLACEHOLDER_COLOR}
                    value={weight}
                    onChangeText={setWeight}
                    keyboardType="numeric"
                  />
                </>
              )}
            </>
          )}

          <Text style={modal.label}>Descricao <Text style={styles.optional}>(opcional)</Text></Text>
          <TextInput
            style={[modal.input, modal.inputMulti]}
            placeholder="Detalhes adicionais..."
            placeholderTextColor={PLACEHOLDER_COLOR}
            value={description}
            onChangeText={setDescription}
            multiline
          />

          <View style={modal.btnRow}>
            <TouchableOpacity style={modal.cancelBtn} onPress={() => { reset(); onCancel(); }}>
              <Text style={modal.cancelText}>Cancelar</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[modal.saveBtn, (!canSave || saving) && modal.btnDisabled]}
              onPress={handleSave}
              disabled={!canSave || saving}
            >
              <Text style={modal.saveBtnText}>{saving ? "Salvando..." : "Salvar"}</Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </Modal>
  );
}

// Event Card
function EventCard({
  item, onDelete,
}: { item: AnimalEvent; onDelete: (event: AnimalEvent) => void }) {
  const audit = isAudit(item);
  const cfg = audit
    ? { icon: "A", color: "#94a3b8", label: "Auditoria" }
    : (EVENT_CONFIG[item.event_type] ?? { icon: "*", color: "#64748b", label: item.event_type });
  const actorName = typeof item.payload?.actor_name === "string" ? item.payload.actor_name : "";
  const apLabel = apparatusLabel(item.payload);
  const experimentRows =
    item.event_type === "experiment_session"
      ? metricRowsForExperiment(item.payload ?? null, apLabel)
      : [];

  if (audit) {
    return (
      <View style={styles.row}>
        <View style={styles.lineCol}>
          <View style={[styles.dot, { backgroundColor: "#e2e8f0" }]}>
            <Text style={[styles.dotIcon, { color: "#94a3b8" }]}>{cfg.icon}</Text>
          </View>
          <View style={styles.line} />
        </View>
        <View style={[styles.card, styles.auditCard]}>
          <Text style={styles.auditLabel}>Auditoria</Text>
          <Text style={styles.auditTitle}>{item.title}</Text>
          {!!item.description && <Text style={styles.auditDesc}>{item.description}</Text>}
          {!!actorName && <Text style={styles.actorLine}>Responsavel: {actorName}</Text>}
          <Text style={styles.date}>{formatDate(item.event_at)}</Text>
        </View>
      </View>
    );
  }

  return (
    <View style={styles.row}>
      <View style={styles.lineCol}>
        <View style={[styles.dot, { backgroundColor: cfg.color }]}>
          <Text style={styles.dotIcon}>{cfg.icon}</Text>
        </View>
        <View style={styles.line} />
      </View>
      <View style={styles.card}>
        <View style={styles.cardHeader}>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 6, flex: 1 }}>
            <Text style={[styles.eventType, { color: cfg.color }]}>{cfg.label}</Text>
            {apLabel ? (
              <View style={[styles.apBadge, { borderColor: cfg.color }]}>
                <Text style={[styles.apBadgeText, { color: cfg.color }]}>{apLabel}</Text>
              </View>
            ) : null}
          </View>
          {item.event_type !== "entry" && (
            <TouchableOpacity
              style={styles.eventDeleteBtn}
              onPress={() => onDelete(item)}
              hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
            >
              <Text style={styles.eventDeleteBtnText}>X</Text>
            </TouchableOpacity>
          )}
        </View>
        <Text style={styles.eventTitle}>{item.title}</Text>
        {!!item.description && <Text style={styles.desc}>{item.description}</Text>}
        {!!actorName && <Text style={styles.actorLine}>Responsavel: {actorName}</Text>}
        {item.payload?.weight_g != null && (
          <Text style={styles.weightTag}>{String(item.payload.weight_g)} g</Text>
        )}
        {experimentRows.length > 0 && (
          <View style={styles.metricsBox}>
            {experimentRows.map((row, rowIdx) => (
              <View key={`row-${rowIdx}`} style={styles.metricRow}>
                {row.map((token, tokenIdx) => (
                  <Text key={`token-${rowIdx}-${tokenIdx}`} style={styles.metricText}>{token}</Text>
                ))}
              </View>
            ))}
          </View>
        )}
        <Text style={styles.date}>{formatDate(item.event_at)}</Text>
      </View>
    </View>
  );
}

// Confirm Event Delete Modal
function ConfirmEventDeleteModal({
  event, onCancel, onConfirm,
}: { event: AnimalEvent | null; onCancel: () => void; onConfirm: () => void }) {
  return (
    <Modal visible={!!event} transparent animationType="fade" onRequestClose={onCancel}>
      <View style={modal.overlay}>
        <View style={modal.box}>
          <Text style={modal.title}>Excluir registro</Text>
          <Text style={modal.warn}>
            Excluir <Text style={{ fontWeight: "700" }}>"{event?.title}"</Text>?
          </Text>
          <Text style={[modal.warn, { marginTop: 6, fontSize: 13, color: "#64748b" }]}>
            Uma nota de auditoria sera adicionada ao historico registrando esta exclusao.
          </Text>
          <View style={modal.btnRow}>
            <TouchableOpacity style={modal.cancelBtn} onPress={onCancel}>
              <Text style={modal.cancelText}>Cancelar</Text>
            </TouchableOpacity>
            <TouchableOpacity style={modal.deleteBtn} onPress={onConfirm}>
              <Text style={modal.deleteBtnText}>Excluir</Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </Modal>
  );
}

// Profile Tab
function ProfileTab({ animalId }: { animalId: number }) {
  const [animal, setAnimal] = useState<Animal | null>(null);
  const [species, setSpecies] = useState<Species | null>(null);
  const [strain, setStrain] = useState<Strain | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    getAnimal(animalId)
      .then(async (a) => {
        setAnimal(a);
        const allSpecies = await fetchSpecies();
        const sp = allSpecies.find((s) => s.id === a.species_id) ?? null;
        setSpecies(sp);
        if (sp) {
          const allStrains = await fetchStrains(sp.id);
          setStrain(allStrains.find((st) => st.id === a.strain_id) ?? null);
        }
      })
      .catch((err) => setError((err as Error).message))
      .finally(() => setLoading(false));
  }, [animalId]);

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator color="#1f4f7c" />
      </View>
    );
  }

  if (error || !animal) {
    return <Text style={styles.errorInline}>{error ?? "Erro ao carregar prontuário."}</Text>;
  }

  const statusColor = STATUS_COLOR[animal.status];

  return (
    <ScrollView contentContainerStyle={styles.profileScroll}>
      <View style={styles.profileCard}>
        <View style={styles.profileHeaderRow}>
          <Text style={styles.profileCode}>{animal.internal_id}</Text>
          <View style={[styles.statusBadge, { backgroundColor: statusColor + "20" }]}>
            <Text style={[styles.statusBadgeText, { color: statusColor }]}>
              {STATUS_LABEL[animal.status]}
            </Text>
          </View>
        </View>

        <View style={styles.divider} />

        <ProfileRow label="Sexo" value={SEX_LABEL[animal.sex]} />
        <ProfileRow label="Espécie" value={species?.common_name ?? `ID ${animal.species_id}`} />
        {species?.scientific_name && (
          <ProfileRow label="" value={species.scientific_name} italic />
        )}
        <ProfileRow label="Linhagem" value={strain?.name ?? `ID ${animal.strain_id}`} />
        {strain?.source && (
          <ProfileRow label="Fonte" value={strain.source} />
        )}

        <View style={styles.divider} />

        <ProfileRow label="Data de entrada" value={formatDateOnly(animal.entry_date)} />
        {animal.marking_date && (
          <ProfileRow label="Data de marcacao" value={formatDateOnly(animal.marking_date)} />
        )}
        {animal.initial_weight_g != null && (
          <ProfileRow label="Peso inicial" value={`${animal.initial_weight_g} g`} />
        )}

        {(animal.euthanasia_date || animal.euthanasia_reason) && (
          <>
            <View style={styles.divider} />
            {animal.euthanasia_date && (
              <ProfileRow label="Data de eutanásia" value={formatDateOnly(animal.euthanasia_date)} />
            )}
            {animal.euthanasia_reason && (
              <ProfileRow label="Motivo" value={animal.euthanasia_reason} />
            )}
          </>
        )}

        {animal.notes && (
          <>
            <View style={styles.divider} />
            <Text style={styles.profileLabel}>Observações</Text>
            <Text style={styles.profileNotes}>{animal.notes}</Text>
          </>
        )}
      </View>
    </ScrollView>
  );
}

function ProfileRow({ label, value, italic }: { label: string; value: string; italic?: boolean }) {
  return (
    <View style={styles.profileRow}>
      {label ? <Text style={styles.profileLabel}>{label}</Text> : null}
      <Text style={[styles.profileValue, italic && { fontStyle: "italic", color: "#94a3b8" }]}>
        {value}
      </Text>
    </View>
  );
}

// Main Screen
export default function AnimalTimelineScreen({ route, navigation }: Props) {
  const { animalId, animalCode } = route.params;
  const [activeTab, setActiveTab] = useState<Tab>("history");
  const [events, setEvents] = useState<AnimalEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showDeleteAnimal, setShowDeleteAnimal] = useState(false);
  const [showAddEvent, setShowAddEvent] = useState(false);
  const [eventToDelete, setEventToDelete] = useState<AnimalEvent | null>(null);

  function loadEvents() {
    setLoading(true);
    setError(null);
    animalTimeline(animalId)
      .then(setEvents)
      .catch((err) => setError((err as Error).message))
      .finally(() => setLoading(false));
  }

  useEffect(() => { loadEvents(); }, [animalId]);

  async function handleDeleteAnimal() {
    try {
      await deleteAnimal(animalId);
      setShowDeleteAnimal(false);
      navigation.goBack();
    } catch (err) {
      setShowDeleteAnimal(false);
      setError((err as Error).message);
    }
  }

  async function confirmDeleteEvent() {
    if (!eventToDelete) return;
    const target = eventToDelete;
    setEventToDelete(null);
    try {
      await deleteAnimalEvent(animalId, target.id);
      loadEvents();
    } catch (err) {
      setError((err as Error).message);
    }
  }

  async function handleAddEvent(
    type: string,
    title: string,
    description: string,
    extra?: Record<string, unknown>
  ) {
    await addAnimalEvent(animalId, {
      event_type: type,
      title,
      description: description || undefined,
      payload: extra,
    });
    setShowAddEvent(false);
    loadEvents();
  }

  return (
    <SafeAreaView style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <View>
          <Text style={styles.headerLabel}>Animal</Text>
          <Text style={styles.code}>{animalCode}</Text>
        </View>
        <View style={styles.headerBtns}>
          {activeTab === "history" && (
            <TouchableOpacity style={styles.addBtn} onPress={() => setShowAddEvent(true)}>
              <Text style={styles.addBtnText}>+ Evento</Text>
            </TouchableOpacity>
          )}
          <TouchableOpacity style={styles.deleteAnimalBtn} onPress={() => setShowDeleteAnimal(true)}>
            <Text style={styles.deleteAnimalBtnText}>Excluir</Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* Tab Bar */}
      <View style={styles.tabBar}>
        <TouchableOpacity
          style={[styles.tabItem, activeTab === "history" && styles.tabItemActive]}
          onPress={() => setActiveTab("history")}
        >
          <Text style={[styles.tabLabel, activeTab === "history" && styles.tabLabelActive]}>
            {"\u23F1"} Historico
          </Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.tabItem, activeTab === "profile" && styles.tabItemActive]}
          onPress={() => setActiveTab("profile")}
        >
          <Text style={[styles.tabLabel, activeTab === "profile" && styles.tabLabelActive]}>
            {"\uD83D\uDCCB"} Prontuario
          </Text>
        </TouchableOpacity>
      </View>

      {/* Error Banner */}
      {error && (
        <View style={styles.errorBanner}>
          <Text style={styles.errorText}>{error}</Text>
          <TouchableOpacity onPress={() => setError(null)}>
            <Text style={styles.errorDismiss}>X</Text>
          </TouchableOpacity>
        </View>
      )}

      {/* Tab Content */}
      {activeTab === "history" ? (
        <>
          {loading && (
            <View style={styles.center}>
              <ActivityIndicator color="#1f4f7c" />
            </View>
          )}
          <FlatList
            data={events}
            keyExtractor={(item) => String(item.id)}
            contentContainerStyle={styles.list}
            ListEmptyComponent={
              !loading ? <Text style={styles.empty}>Nenhum evento registrado.</Text> : null
            }
            renderItem={({ item }) => (
              <EventCard item={item} onDelete={setEventToDelete} />
            )}
          />
        </>
      ) : (
        <ProfileTab animalId={animalId} />
      )}

      {/* Modals */}
      <DeleteAnimalModal
        visible={showDeleteAnimal}
        animalCode={animalCode}
        onCancel={() => setShowDeleteAnimal(false)}
        onConfirm={handleDeleteAnimal}
      />
      <AddEventModal
        visible={showAddEvent}
        onCancel={() => setShowAddEvent(false)}
        onSave={handleAddEvent}
      />
      <ConfirmEventDeleteModal
        event={eventToDelete}
        onCancel={() => setEventToDelete(null)}
        onConfirm={confirmDeleteEvent}
      />
    </SafeAreaView>
  );
}

// Styles
const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: "#f7f8fa" },
  header: {
    flexDirection: "row", alignItems: "center", justifyContent: "space-between",
    padding: 16, paddingBottom: 10,
  },
  headerLabel: { fontSize: 12, color: "#64748b", fontWeight: "600" },
  code: { fontSize: 20, fontWeight: "700", color: "#1f4f7c", fontFamily: "monospace" },
  headerBtns: { flexDirection: "row", gap: 8 },
  addBtn: { backgroundColor: "#1f4f7c", paddingHorizontal: 12, paddingVertical: 7, borderRadius: 8 },
  addBtnText: { color: "white", fontWeight: "600", fontSize: 13 },
  deleteAnimalBtn: { backgroundColor: "#fee2e2", paddingHorizontal: 12, paddingVertical: 7, borderRadius: 8 },
  deleteAnimalBtnText: { color: "#dc2626", fontWeight: "600", fontSize: 13 },
  tabBar: {
    flexDirection: "row", borderBottomWidth: 1, borderColor: "#e2e8f0",
    backgroundColor: "white",
  },
  tabItem: {
    flex: 1, paddingVertical: 12, alignItems: "center",
    borderBottomWidth: 2, borderBottomColor: "transparent",
  },
  tabItemActive: { borderBottomColor: "#1f4f7c" },
  tabLabel: { fontSize: 14, fontWeight: "600", color: "#94a3b8" },
  tabLabelActive: { color: "#1f4f7c" },
  errorBanner: {
    flexDirection: "row", alignItems: "center", justifyContent: "space-between",
    backgroundColor: "#fee2e2", padding: 10, marginHorizontal: 16, borderRadius: 8, marginTop: 6,
  },
  errorText: { color: "#b91c1c", flex: 1, fontSize: 13 },
  errorDismiss: { color: "#b91c1c", fontSize: 20, paddingLeft: 8 },
  errorInline: { color: "#b91c1c", textAlign: "center", marginTop: 40, paddingHorizontal: 20 },
  list: { paddingHorizontal: 16, paddingBottom: 20, paddingTop: 8 },
  center: { padding: 20, alignItems: "center" },
  empty: { textAlign: "center", color: "#94a3b8", marginTop: 40 },
  row: { flexDirection: "row", gap: 12, marginBottom: 4 },
  lineCol: { alignItems: "center", width: 36 },
  dot: { width: 32, height: 32, borderRadius: 16, alignItems: "center", justifyContent: "center" },
  dotIcon: { color: "white", fontSize: 13, fontWeight: "700" },
  line: { flex: 1, width: 2, backgroundColor: "#e2e8f0", marginTop: 2 },
  card: {
    flex: 1, backgroundColor: "white", borderRadius: 10, padding: 12,
    borderWidth: 1, borderColor: "#e2e8f0", marginBottom: 10, gap: 3,
  },
  auditCard: { backgroundColor: "#f8fafc", borderColor: "#e2e8f0", borderStyle: "dashed" },
  cardHeader: { flexDirection: "row", alignItems: "center", justifyContent: "space-between" },
  eventType: { fontSize: 11, fontWeight: "700", textTransform: "uppercase", letterSpacing: 0.5 },
  apBadge: { borderWidth: 1, borderRadius: 8, paddingHorizontal: 6, paddingVertical: 1 },
  apBadgeText: { fontSize: 10, fontWeight: "700" },
  eventTitle: { fontSize: 14, fontWeight: "600", color: "#1e293b" },
  desc: { fontSize: 13, color: "#475569" },
  actorLine: { fontSize: 12, color: "#334155", fontWeight: "600" },
  weightTag: { fontSize: 12, color: "#2563eb", fontWeight: "600" },
  metricsBox: {
    marginTop: 2,
    padding: 8,
    borderRadius: 8,
    backgroundColor: "#f8f5ff",
    borderWidth: 1,
    borderColor: "#e9ddff",
    gap: 4,
  },
  metricRow: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
  metricText: { fontSize: 12, color: "#5b3ea8", fontWeight: "600" },
  date: { fontSize: 11, color: "#94a3b8", marginTop: 2 },
  eventDeleteBtn: {
    width: 22, height: 22, borderRadius: 11,
    backgroundColor: "#fee2e2", alignItems: "center", justifyContent: "center",
  },
  eventDeleteBtnText: { color: "#dc2626", fontSize: 16, fontWeight: "700", lineHeight: 20 },
  auditLabel: { fontSize: 10, fontWeight: "700", color: "#94a3b8", textTransform: "uppercase", letterSpacing: 0.5 },
  auditTitle: { fontSize: 13, fontWeight: "600", color: "#64748b", fontStyle: "italic" },
  auditDesc: { fontSize: 12, color: "#94a3b8", fontStyle: "italic" },
  chipRow: { flexDirection: "row", flexWrap: "wrap", gap: 8, marginTop: 6 },
  chip: {
    paddingHorizontal: 14, paddingVertical: 8, borderRadius: 20,
    borderWidth: 1.5, borderColor: "#cbd5e1", backgroundColor: "white",
  },
  chipActive: { backgroundColor: "#1f4f7c", borderColor: "#1f4f7c" },
  chipExperiment: { backgroundColor: "#7c3aed", borderColor: "#7c3aed" },
  chipText: { fontSize: 14, color: "#334155" },
  chipTextActive: { color: "white", fontWeight: "600" },
  optional: { fontSize: 12, fontWeight: "400", color: "#94a3b8" },
  // Profile tab
  profileScroll: { padding: 16, paddingBottom: 40 },
  profileCard: {
    backgroundColor: "white", borderRadius: 12,
    borderWidth: 1, borderColor: "#e2e8f0", padding: 16, gap: 0,
  },
  profileHeaderRow: {
    flexDirection: "row", alignItems: "center", justifyContent: "space-between",
    marginBottom: 12,
  },
  profileCode: { fontSize: 18, fontWeight: "700", color: "#1f4f7c", fontFamily: "monospace" },
  statusBadge: { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 12 },
  statusBadgeText: { fontSize: 12, fontWeight: "700" },
  divider: { height: 1, backgroundColor: "#f1f5f9", marginVertical: 10 },
  profileRow: { flexDirection: "row", justifyContent: "space-between", alignItems: "flex-start", paddingVertical: 4 },
  profileLabel: { fontSize: 13, color: "#94a3b8", fontWeight: "500", flex: 1 },
  profileValue: { fontSize: 13, color: "#1e293b", fontWeight: "600", flex: 2, textAlign: "right" },
  profileNotes: { fontSize: 13, color: "#475569", lineHeight: 20, marginTop: 4 },
});

const modal = StyleSheet.create({
  overlay: {
    flex: 1, backgroundColor: "rgba(0,0,0,0.5)",
    justifyContent: "center", alignItems: "center", padding: 20,
  },
  box: {
    backgroundColor: "white", borderRadius: 14, padding: 24,
    width: "100%", maxWidth: 440, gap: 8,
  },
  title: { fontSize: 18, fontWeight: "700", color: "#1e293b", marginBottom: 4 },
  warn: { fontSize: 14, color: "#475569", lineHeight: 20 },
  warnBold: { fontWeight: "700", color: "#dc2626" },
  label: { fontSize: 13, fontWeight: "600", color: "#475569", marginTop: 8 },
  codeHint: {
    fontFamily: "monospace", fontSize: 16, fontWeight: "700", color: "#1f4f7c",
    backgroundColor: "#f1f5f9", padding: 8, borderRadius: 6, textAlign: "center",
  },
  input: {
    borderWidth: 1.5, borderColor: "#cbd5e1", borderRadius: 8,
    padding: 10, fontSize: 15, color: "#1e293b", marginTop: 4,
  },
  inputMatch: { borderColor: "#16a34a", backgroundColor: "#f0fdf4" },
  inputMulti: { minHeight: 72, textAlignVertical: "top" },
  btnRow: { flexDirection: "row", gap: 10, marginTop: 16 },
  cancelBtn: {
    flex: 1, padding: 12, borderRadius: 8,
    borderWidth: 1.5, borderColor: "#cbd5e1", alignItems: "center",
  },
  cancelText: { color: "#334155", fontWeight: "600" },
  deleteBtn: { flex: 1, padding: 12, borderRadius: 8, backgroundColor: "#dc2626", alignItems: "center" },
  deleteBtnText: { color: "white", fontWeight: "700" },
  saveBtn: { flex: 1, padding: 12, borderRadius: 8, backgroundColor: "#1f4f7c", alignItems: "center" },
  saveBtnText: { color: "white", fontWeight: "700" },
  btnDisabled: { opacity: 0.4 },
});




