import csv
import os
import sys
import zipfile
from io import BytesIO


def escape_xml(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;").replace("'", "&apos;")


def get_col_name(n):
    return f"{chr(65 + n)}" if n < 26 else f"{chr(64 + (n // 26))}{chr(65 + (n % 26))}"


def normalize_text(s):
    t = str(s or "").strip().lower()
    repl = {
        "á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a",
        "é": "e", "è": "e", "ê": "e", "ë": "e",
        "í": "i", "ì": "i", "î": "i", "ï": "i",
        "ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o",
        "ú": "u", "ù": "u", "û": "u", "ü": "u",
        "ç": "c", "ñ": "n",
    }
    for k, v in repl.items():
        t = t.replace(k, v)
    return t


def contains_any(text, patterns):
    nt = normalize_text(text)
    return any(normalize_text(p) in nt for p in patterns)


def headers_have_any(headers, patterns):
    return any(contains_any(h, patterns) for h in headers)


def detect_language(headers):
    if headers_have_any(headers, ["video directory", "object pair", "time in center", "average speed", "duration"]):
        return "en"
    if headers_have_any(headers, ["directorio del video", "tiempo en centro", "velocidad media", "duracion", "tratamiento"]):
        return "es"
    return "pt"


def create_xlsx(dest_path, base_name_str, apparatus_label, headers, groups, color_hex="FFAB3D4C", lang="pt"):
    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
"""
    for i in range(1, len(groups) + 1):
        content_types += f'    <Override PartName="/xl/worksheets/sheet{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\n'
    content_types += "</Types>"

    rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>"""

    workbook = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
    <sheets>\n"""
    sheet_names = list(groups.keys())
    for i, name in enumerate(sheet_names, 1):
        clean_name = escape_xml(name)[:31]
        workbook += f'        <sheet name="{clean_name}" sheetId="{i}" r:id="rId{i}"/>\n'
    workbook += "    </sheets>\n</workbook>"

    wb_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\n"""
    for i in range(1, len(groups) + 1):
        wb_rels += f'    <Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet{i}.xml"/>\n'
    wb_rels += '    <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\n'
    wb_rels += "</Relationships>"

    styles = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <fonts count="4">
        <font><sz val="11"/><name val="Calibri"/></font>
        <font><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/><b/></font>
        <font><sz val="18"/><color rgb="FFFFFFFF"/><name val="Segoe UI"/><b/></font>
        <font><sz val="11"/><color rgb="FF374151"/><name val="Segoe UI"/><b/></font>
    </fonts>
    <fills count="4">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="{color_hex}"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFF9FAFB"/><bgColor indexed="64"/></patternFill></fill>
    </fills>
    <borders count="2">
        <border><left/><right/><top/><bottom/><diagonal/></border>
        <border><left style="thin"><color rgb="FFE5E7EB"/></left><right style="thin"><color rgb="FFE5E7EB"/></right><top style="thin"><color rgb="FFE5E7EB"/></top><bottom style="thin"><color rgb="FFE5E7EB"/></bottom><diagonal/></border>
    </borders>
    <cellXfs count="6">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"><alignment horizontal="center" vertical="center"/></xf>
        <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment horizontal="center" vertical="center"/></xf>
        <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"><alignment horizontal="center" vertical="center"/></xf>
        <xf numFmtId="0" fontId="2" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"><alignment horizontal="center" vertical="center"/></xf>
        <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"><alignment horizontal="center" vertical="center"/></xf>
        <xf numFmtId="0" fontId="3" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1"><alignment horizontal="center" vertical="center"/></xf>
    </cellXfs>
</styleSheet>"""

    with zipfile.ZipFile(dest_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", content_types)
        zf.writestr("_rels/.rels", rels)
        zf.writestr("xl/workbook.xml", workbook)
        zf.writestr("xl/_rels/workbook.xml.rels", wb_rels)
        zf.writestr("xl/styles.xml", styles)

        for i, name in enumerate(sheet_names, 1):
            rows = groups[name]
            total_rows = len(rows)
            ani_idx = headers.index("Animal") if "Animal" in headers else -1
            unique_animals = len(set(r[ani_idx] for r in rows if len(r) > ani_idx)) if ani_idx >= 0 else 0

            if lang == "en":
                stats_str = f"Total Records in Sheet: {total_rows} | Unique Animals: {unique_animals} | Data Columns: {len(headers)}"
            elif lang == "es":
                stats_str = f"Total de Registros en la Hoja: {total_rows} | Animales Unicos: {unique_animals} | Columnas de Datos: {len(headers)}"
            else:
                stats_str = f"Total de Registros na Planilha: {total_rows} | Animais Unicos: {unique_animals} | Colunas de Dados: {len(headers)}"

            col_widths = [12] * len(headers)
            for c, h in enumerate(headers):
                col_widths[c] = max(col_widths[c], len(str(h)) + 4)
            for r in rows:
                for c, v in enumerate(r):
                    if c < len(col_widths):
                        col_widths[c] = max(col_widths[c], len(str(v)) + 1)

            ws_xml = BytesIO()
            ws_xml.write(b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n')
            ws_xml.write(b'<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\n')
            ws_xml.write(b"  <cols>\n")
            for c in range(len(headers)):
                w = min(255, col_widths[c] * 1.1)
                ws_xml.write(f'    <col min="{c+1}" max="{c+1}" width="{w:.2f}" customWidth="1"/>\n'.encode("utf-8"))
            ws_xml.write(b"  </cols>\n")
            ws_xml.write(b"  <sheetData>\n")

            ws_xml.write(b'    <row r="1" ht="30" customHeight="1">\n')
            ws_xml.write(f'      <c r="A1" s="3" t="inlineStr"><is><t>{escape_xml(base_name_str)}</t></is></c>\n'.encode("utf-8"))
            ws_xml.write(b"    </row>\n")

            ws_xml.write(b'    <row r="2" ht="20" customHeight="1">\n')
            ws_xml.write(f'      <c r="A2" s="4" t="inlineStr"><is><t>{escape_xml(apparatus_label)}</t></is></c>\n'.encode("utf-8"))
            ws_xml.write(b"    </row>\n")

            ws_xml.write(b'    <row r="3" ht="20" customHeight="1">\n')
            ws_xml.write(f'      <c r="A3" s="5" t="inlineStr"><is><t>{escape_xml(stats_str)}</t></is></c>\n'.encode("utf-8"))
            ws_xml.write(b"    </row>\n")

            ws_xml.write(b'    <row r="4" ht="20" customHeight="1">\n')
            for c, h in enumerate(headers):
                cell_ref = f"{get_col_name(c)}4"
                ws_xml.write(f'      <c r="{cell_ref}" s="1" t="inlineStr"><is><t>{escape_xml(h)}</t></is></c>\n'.encode("utf-8"))
            ws_xml.write(b"    </row>\n")

            exclude_numeric = {
                "animal", "campo", "field", "dia", "day", "par de objetos", "object pair",
                "diretorio do video", "diretorio do video", "video directory", "directorio del video"
            }

            v_idx = -1
            d_idx = -1
            t1_idx = -1
            t2_idx = -1
            for h_idx, h_name in enumerate(headers):
                if contains_any(h_name, ["velocidade media", "average speed", "velocidad media"]):
                    v_idx = h_idx
                elif contains_any(h_name, ["distancia total", "total distance"]):
                    d_idx = h_idx
                elif contains_any(h_name, ["tempo no centro", "time in center", "tiempo en centro", "tempo plataforma", "platform time", "tiempo plataforma"]):
                    t1_idx = h_idx
                elif contains_any(h_name, ["tempo na borda", "time at border", "tiempo en borde", "tempo grade", "grid time", "tiempo rejilla"]):
                    t2_idx = h_idx

            for r in rows:
                if v_idx >= 0 and d_idx >= 0 and t1_idx >= 0 and t2_idx >= 0:
                    try:
                        v_val = float(str(r[v_idx]).replace(",", ".")) if len(r) > v_idx and r[v_idx] else 0.0
                        if v_val < 0.001:
                            d_val = float(str(r[d_idx]).replace(",", ".")) if len(r) > d_idx and r[d_idx] else 0.0
                            t1_val = float(str(r[t1_idx]).replace(",", ".")) if len(r) > t1_idx and r[t1_idx] else 0.0
                            t2_val = float(str(r[t2_idx]).replace(",", ".")) if len(r) > t2_idx and r[t2_idx] else 0.0
                            t_total = t1_val + t2_val
                            if t_total > 0.5:
                                r[v_idx] = "{:.3f}".format(d_val / t_total).replace(".", ",")
                    except Exception:
                        pass

            for r_idx, row in enumerate(rows, 5):
                ws_xml.write(f'    <row r="{r_idx}">\n'.encode("utf-8"))
                for c_idx, val in enumerate(row):
                    cell_ref = f"{get_col_name(c_idx)}{r_idx}"
                    header_name = normalize_text(headers[c_idx] if c_idx < len(headers) else "")
                    val_str = str(val).strip()

                    is_num = False
                    if header_name not in exclude_numeric:
                        try:
                            num = float(val_str.replace(",", "."))
                            val_str = str(num)
                            is_num = True
                        except ValueError:
                            pass

                    if is_num:
                        ws_xml.write(f'      <c r="{cell_ref}" s="2"><v>{val_str}</v></c>\n'.encode("utf-8"))
                    else:
                        ws_xml.write(f'      <c r="{cell_ref}" s="2" t="inlineStr"><is><t>{escape_xml(val_str)}</t></is></c>\n'.encode("utf-8"))
                ws_xml.write(b"    </row>\n")

            ws_xml.write(b"  </sheetData>\n")
            last_col = get_col_name(len(headers) - 1) if headers else "A"
            ws_xml.write(b'  <mergeCells count="3">')
            ws_xml.write(f'<mergeCell ref="A1:{last_col}1"/>'.encode("utf-8"))
            ws_xml.write(f'<mergeCell ref="A2:{last_col}2"/>'.encode("utf-8"))
            ws_xml.write(f'<mergeCell ref="A3:{last_col}3"/>'.encode("utf-8"))
            ws_xml.write(b"</mergeCells>\n")
            ws_xml.write(b"</worksheet>")
            zf.writestr(f"xl/worksheets/sheet{i}.xml", ws_xml.getvalue())


def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    source_path = sys.argv[1]
    if not os.path.exists(source_path):
        sys.exit(1)

    base_name = os.path.splitext(os.path.basename(source_path))[0]
    out_path = os.path.splitext(source_path)[0] + ".xlsx"

    rows = []
    for enc in ["utf-8-sig", "utf-8", "latin-1"]:
        try:
            with open(source_path, "r", encoding=enc) as f:
                rows = list(csv.reader(f))
            break
        except UnicodeDecodeError:
            continue

    if not rows:
        sys.exit(0)

    headers = rows[0]
    data = rows[1:]
    lang = detect_language(headers)

    if lang == "en":
        apparatus = "Experiment Data"
    elif lang == "es":
        apparatus = "Datos del Experimento"
    else:
        apparatus = "Dados do Experimento"
    apparatus_color = "FFAB3D4C"

    if headers_have_any(headers, ["Par de Objetos", "Object Pair"]):
        apparatus = {"pt": "Reconhecimento de Objetos (NOR)", "en": "Object Recognition (NOR)", "es": "Reconocimiento de Objetos (NOR)"}[lang]
        apparatus_color = "FFAB3D4C"
    elif headers_have_any(headers, ["latencia (s)", "tempo plataforma (s)", "platform time (s)", "tiempo plataforma (s)"]):
        apparatus = {"pt": "Esquiva Inibitoria (EI)", "en": "Inhibitory Avoidance (EI)", "es": "Evitacion Inhibitoria (EI)"}[lang]
        apparatus_color = "FFC8A000"
    elif headers_have_any(headers, ["tempo no centro (s)", "time in center (s)", "tiempo en centro (s)", "visitas ao centro", "center visits", "visitas al centro"]):
        apparatus = {"pt": "Campo Aberto (CA)", "en": "Open Field (CA)", "es": "Campo Abierto (CA)"}[lang]
        apparatus_color = "FF3D7AAB"
    elif headers_have_any(headers, ["duracao (min)", "duration (min)", "duracion (min)"]):
        apparatus = {"pt": "Comportamento Complexo (CC)", "en": "Complex Behavior (CC)", "es": "Comportamiento Complejo (CC)"}[lang]
        apparatus_color = "FF7A3DAB"

    split_idx = -1
    for i, h in enumerate(headers):
        if contains_any(h, ["Par de Objetos", "Object Pair"]):
            split_idx = i
            break

    groups = {}
    if split_idx >= 0:
        for r in data:
            if len(r) > split_idx:
                key = r[split_idx] if r[split_idx] else {"pt": "Dados", "en": "Data", "es": "Datos"}[lang]
                groups.setdefault(key, []).append(r)
    else:
        groups[{"pt": "Geral", "en": "General", "es": "General"}[lang]] = data

    create_xlsx(out_path, base_name, apparatus, headers, groups, apparatus_color, lang)

    if out_path != source_path:
        try:
            if os.path.exists(out_path):
                os.remove(source_path)
        except Exception:
            pass


if __name__ == "__main__":
    main()
