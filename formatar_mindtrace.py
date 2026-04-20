import sys
import os
import csv
import zipfile
from io import BytesIO

def escape_xml(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;").replace("'", "&apos;")

def get_col_name(n):
    return f"{chr(65+n)}" if n < 26 else f"{chr(64+(n//26))}{chr(65+(n%26))}"

def create_xlsx(dest_path, base_name_str, apparatus_label, headers, groups, color_hex="FFAB3D4C"):
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
    wb_rels += f'    <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\n'
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
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0">
            <alignment horizontal="center" vertical="center"/>
        </xf>
        <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1">
            <alignment horizontal="center" vertical="center"/>
        </xf>
        <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1">
            <alignment horizontal="center" vertical="center"/>
        </xf>
        <xf numFmtId="0" fontId="2" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1">
            <alignment horizontal="center" vertical="center"/>
        </xf>
        <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1">
            <alignment horizontal="center" vertical="center"/>
        </xf>
        <xf numFmtId="0" fontId="3" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1">
            <alignment horizontal="center" vertical="center"/>
        </xf>
    </cellXfs>
</styleSheet>"""

    with zipfile.ZipFile(dest_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.writestr('[Content_Types].xml', content_types)
        zf.writestr('_rels/.rels', rels)
        zf.writestr('xl/workbook.xml', workbook)
        zf.writestr('xl/_rels/workbook.xml.rels', wb_rels)
        zf.writestr('xl/styles.xml', styles)

        for i, name in enumerate(sheet_names, 1):
            rows = groups[name]
            total_rows = len(rows)
            ani_idx = headers.index("Animal") if "Animal" in headers else -1
            unique_animals = len(set(r[ani_idx] for r in rows if len(r) > ani_idx)) if ani_idx >= 0 else 0
            stats_str = f"Total de Registros na Planilha: {total_rows} | Animais Únicos: {unique_animals} | Colunas de Dados: {len(headers)}"

            col_widths = [12] * len(headers)
            for c, h in enumerate(headers): col_widths[c] = max(col_widths[c], len(str(h)) + 4)
            for r in rows:
                for c, v in enumerate(r):
                    if c < len(col_widths): col_widths[c] = max(col_widths[c], len(str(v)) + 1)
            
            ws_xml = BytesIO()
            ws_xml.write(b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n')
            ws_xml.write(b'<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\n')
            
            ws_xml.write(b'  <cols>\n')
            for c in range(len(headers)):
                w = min(255, col_widths[c] * 1.1)
                ws_xml.write(f'    <col min="{c+1}" max="{c+1}" width="{w:.2f}" customWidth="1"/>\n'.encode('utf-8'))
            ws_xml.write(b'  </cols>\n')
            
            ws_xml.write(b'  <sheetData>\n')
            
            ws_xml.write(b'    <row r="1" ht="30" customHeight="1">\n')
            ws_xml.write(f'      <c r="A1" s="3" t="inlineStr"><is><t>{escape_xml(base_name_str)}</t></is></c>\n'.encode('utf-8'))
            ws_xml.write(b'    </row>\n')

            ws_xml.write(b'    <row r="2" ht="20" customHeight="1">\n')
            ws_xml.write(f'      <c r="A2" s="4" t="inlineStr"><is><t>{escape_xml(apparatus_label)}</t></is></c>\n'.encode('utf-8'))
            ws_xml.write(b'    </row>\n')

            ws_xml.write(b'    <row r="3" ht="20" customHeight="1">\n')
            ws_xml.write(f'      <c r="A3" s="5" t="inlineStr"><is><t>{escape_xml(stats_str)}</t></is></c>\n'.encode('utf-8'))
            ws_xml.write(b'    </row>\n')

            ws_xml.write(b'    <row r="4" ht="20" customHeight="1">\n')
            for c, h in enumerate(headers):
                cell_ref = f"{get_col_name(c)}4"
                ws_xml.write(f'      <c r="{cell_ref}" s="1" t="inlineStr"><is><t>{escape_xml(h)}</t></is></c>\n'.encode('utf-8'))
            ws_xml.write(b'    </row>\n')

            exclude_numeric = ["Animal", "Campo", "Dia", "Par de Objetos", "Diret\u00f3rio do V\u00eddeo"]
            # --- Lógica de 'Healing' para Velocidade Média (Dados antigos) ---
            v_idx = -1
            d_idx = -1
            t1_idx = -1
            t2_idx = -1
            
            # Identificar colunas relevantes para CA ou EI
            for h_idx, h_name in enumerate(headers):
                if "Velocidade Média" in h_name: v_idx = h_idx
                elif "Distância Total" in h_name: d_idx = h_idx
                elif "Tempo no Centro" in h_name: t1_idx = h_idx
                elif "Tempo na Borda" in h_name: t2_idx = h_idx
                elif "Tempo Plataforma" in h_name: t1_idx = h_idx
                elif "Tempo Grade" in h_name: t2_idx = h_idx

            for r in rows:
                # Se temos colunas de dist/tempo e a velocidade veio zerada, tentamos reconstruir
                if v_idx >= 0 and d_idx >= 0 and t1_idx >= 0 and t2_idx >= 0:
                    try:
                        v_val = float(r[v_idx].replace(',', '.')) if len(r) > v_idx and r[v_idx] else 0.0
                        if v_val < 0.001: # Se está zerado ou quase
                            d_val = float(r[d_idx].replace(',', '.'))  if len(r) > d_idx and r[d_idx] else 0.0
                            t1_val = float(r[t1_idx].replace(',', '.')) if len(r) > t1_idx and r[t1_idx] else 0.0
                            t2_val = float(r[t2_idx].replace(',', '.')) if len(r) > t2_idx and r[t2_idx] else 0.0
                            t_total = t1_val + t2_val
                            if t_total > 0.5:
                                new_v = d_val / t_total
                                r[v_idx] = "{:.3f}".format(new_v).replace('.', ',')
                    except Exception:
                        pass

            for r_idx, row in enumerate(rows, 5):
                ws_xml.write(f'    <row r="{r_idx}">\n'.encode('utf-8'))
                for c_idx, val in enumerate(row):
                    cell_ref = f"{get_col_name(c_idx)}{r_idx}"
                    header_name = headers[c_idx] if c_idx < len(headers) else ""
                    val_str = str(val).strip()
                    
                    is_num = False
                    if header_name not in exclude_numeric:
                        try:
                            num = float(val_str.replace(',', '.'))
                            val_str = str(num)
                            is_num = True
                        except ValueError:
                            pass
                    
                    if is_num:
                        ws_xml.write(f'      <c r="{cell_ref}" s="2"><v>{val_str}</v></c>\n'.encode('utf-8'))
                    else:
                        ws_xml.write(f'      <c r="{cell_ref}" s="2" t="inlineStr"><is><t>{escape_xml(val_str)}</t></is></c>\n'.encode('utf-8'))
                        
                ws_xml.write(b'    </row>\n')
            
            ws_xml.write(b'  </sheetData>\n')
            
            last_col = get_col_name(len(headers) - 1) if len(headers) > 0 else "A"
            ws_xml.write(f'  <mergeCells count="3">'.encode('utf-8'))
            ws_xml.write(f'<mergeCell ref="A1:{last_col}1"/>'.encode('utf-8'))
            ws_xml.write(f'<mergeCell ref="A2:{last_col}2"/>'.encode('utf-8'))
            ws_xml.write(f'<mergeCell ref="A3:{last_col}3"/>'.encode('utf-8'))
            ws_xml.write(f'</mergeCells>\n'.encode('utf-8'))
            
            ws_xml.write(b'</worksheet>')
            zf.writestr(f'xl/worksheets/sheet{i}.xml', ws_xml.getvalue())

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    source_path = sys.argv[1]
    if not os.path.exists(source_path):
        sys.exit(1)

    # Identificar o destino. Substitui as extensoes pra manter 1 arquivo limpo
    base_name = os.path.splitext(os.path.basename(source_path))[0]
    out_path = os.path.splitext(source_path)[0] + ".xlsx"

    encodings = ['utf-8-sig', 'utf-8', 'latin-1']
    rows = []
    
    for enc in encodings:
        try:
            with open(source_path, 'r', encoding=enc) as f:
                reader = csv.reader(f)
                rows = list(reader)
            break
        except UnicodeDecodeError:
            continue

    if not rows:
        sys.exit(0)

    headers = rows[0]
    data = rows[1:]

    apparatus = "Dados do Experimento"
    apparatus_color = "FFAB3D4C" # Default Red (NOR)
    if "Par de Objetos" in headers:
        apparatus = "Reconhecimento de Objetos (NOR)"
        apparatus_color = "FFAB3D4C"
    elif "Latência (s)" in headers or "Tempo Plataforma (s)" in headers or "Latência" in headers:
        apparatus = "Esquiva Inibitória (EI)"
        apparatus_color = "FFC8A000" # Yellow
    elif "Tempo no Centro (s)" in headers or "Visitas ao Centro" in headers:
        apparatus = "Campo Aberto (CA)"
        apparatus_color = "FF3D7AAB" # Blue
    elif "Duração (min)" in headers:
        apparatus = "Comportamento Complexo (CC)"
        apparatus_color = "FF7A3DAB" # Purple
    split_idx = -1
    if "Par de Objetos" in headers:
        split_idx = headers.index("Par de Objetos")

    groups = {}
    if split_idx >= 0:
        for r in data:
            if len(r) > split_idx:
                k = r[split_idx]
                if not k: k = "Dados"
                if k not in groups: groups[k] = []
                groups[k].append(r)
    else:
        groups["Geral"] = data

    create_xlsx(out_path, base_name, apparatus, headers, groups, apparatus_color)
    
    # Deletar o arquivo bruto apenas se as extensoes diferirem
    if out_path != source_path:
        try:
            if os.path.exists(out_path):
                os.remove(source_path)
        except Exception:
            pass

if __name__ == "__main__":
    main()
