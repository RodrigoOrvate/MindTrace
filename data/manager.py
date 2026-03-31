"""
data/manager.py
---------------
Handles directory creation and metadata persistence for OuroScan sessions.

Output structure:
    OuroScan_Data/
        <Aparato>/
            <ID_Animal>_<Fase>_<YYYYMMDD_HHMMSS>/
                metadata.csv
                tracking_data.csv   (created later by tracking module)
                video_output.mp4    (created later by recording module)
"""

import csv
from pathlib import Path
from datetime import datetime


# Map internal aparato keys to human-readable folder names
APARATO_NAMES = {
    "nor":       "Reconhecimento_Objetos",
    "openfield": "Campo_Aberto",
    "esquiva":   "Esquiva_Inibitoria",
    "eletrof":   "Eletrofisiologia",
}


def create_session_dir(aparato_key: str, animal_id: str, fase: str) -> Path:
    """
    Create and return the session directory path.

    Parameters
    ----------
    aparato_key : str
        One of the keys in APARATO_NAMES (e.g. 'nor', 'openfield').
    animal_id : str
        Identifier typed by the researcher (e.g. 'Rato_01_Controle').
    fase : str
        Current phase label (e.g. 'Habituacao', 'Treino', 'Teste').

    Returns
    -------
    Path
        Absolute path to the newly created session directory.
    """
    aparato_folder = APARATO_NAMES.get(aparato_key, aparato_key)
    timestamp      = datetime.now().strftime("%Y%m%d_%H%M%S")

    # Sanitise inputs so they are safe as directory names
    safe_id   = _sanitise(animal_id)  or "Animal"
    safe_fase = _sanitise(fase)       or "Sessao"

    session_name = f"{safe_id}_{safe_fase}_{timestamp}"
    session_path = Path("OuroScan_Data") / aparato_folder / session_name
    session_path.mkdir(parents=True, exist_ok=True)
    return session_path


def save_metadata(session_path: Path, metadata: dict) -> Path:
    """
    Write metadata dict to <session_path>/metadata.csv.

    Parameters
    ----------
    session_path : Path
        Directory returned by create_session_dir.
    metadata : dict
        Key-value pairs describing the session (animal ID, drug, weight, etc.).

    Returns
    -------
    Path
        Path to the written CSV file.
    """
    csv_path = session_path / "metadata.csv"
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=metadata.keys())
        writer.writeheader()
        writer.writerow(metadata)
    return csv_path


def start_session(aparato_key: str, metadata: dict) -> tuple[Path, Path]:
    """
    Convenience wrapper: create directory + save metadata in one call.

    'animal_id' and 'fase' must be keys present in the metadata dict.

    Returns
    -------
    (session_path, csv_path)
    """
    animal_id    = metadata.get("animal_id", "Animal")
    fase         = metadata.get("fase", "Sessao")
    session_path = create_session_dir(aparato_key, animal_id, fase)
    csv_path     = save_metadata(session_path, metadata)
    return session_path, csv_path


# ------------------------------------------------------------------
def _sanitise(text: str) -> str:
    """Replace characters that are invalid in directory names."""
    keep = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    return "".join(c if c in keep else "_" for c in text).strip("_")
