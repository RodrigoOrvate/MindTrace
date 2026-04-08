// qml/ArenaSetup.qml
// Mosaico 2×2 — zonas arrastáveis via Shift+Esq (drag em tempo real).
// Dev Mode: exibe diâmetro das zonas; Shift+Scroll redimensiona.
// Vídeo offline: um VideoOutput no canto + ShaderEffectSource por campo (sem bug de hardware overlay).

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import QtQuick.Dialogs
import MindTrace.Backend 1.0

Item {
    id: root

    property string experimentPath: ""
    property string context: ""
    property string pair1: ""
    property string pair2: ""
    property string pair3: ""
    property string videoPath: ""
    property bool   devMode:   false
    // Mode: "offline" (video already exists) or "ao_vivo" (camera, save when done)
    property string analysisMode: ""
    property string saveDirectory: ""

    signal pairsEdited(string p1, string p2, string p3)
    signal analysisModeChangedExternally(string mode)

    // 6 zonas, 2 por campo: { x: xRatio, y: yRatio, r: radiusRatio }
    property var zones: [
        {x: 0.3, y: 0.5, r: 0.12}, {x: 0.7, y: 0.5, r: 0.12},
        {x: 0.3, y: 0.5, r: 0.12}, {x: 0.7, y: 0.5, r: 0.12},
        {x: 0.3, y: 0.5, r: 0.12}, {x: 0.7, y: 0.5, r: 0.12}
    ]

    // NOVO: A borda externa agora é um polígono livre de 4 pontos (Topo das paredes)!
    property var arenaPoints: [
        [{x:0.02, y:0.02}, {x:0.98, y:0.02}, {x:0.98, y:0.98}, {x:0.02, y:0.98}],
        [{x:0.02, y:0.02}, {x:0.98, y:0.02}, {x:0.98, y:0.98}, {x:0.02, y:0.98}],
        [{x:0.02, y:0.02}, {x:0.98, y:0.02}, {x:0.98, y:0.98}, {x:0.02, y:0.98}]
    ]

    // (Mantenha o floorPoints aqui embaixo igualzinho)
    property var floorPoints: [
        [{x: 0.15, y: 0.15}, {x: 0.85, y: 0.15}, {x: 0.85, y: 0.85}, {x: 0.15, y: 0.85}],
        [{x: 0.15, y: 0.15}, {x: 0.85, y: 0.15}, {x: 0.85, y: 0.85}, {x: 0.15, y: 0.85}],
        [{x: 0.15, y: 0.15}, {x: 0.85, y: 0.15}, {x: 0.85, y: 0.85}, {x: 0.15, y: 0.85}]
    ]

    function zoneIdsForPair(pair) {
        if (!pair || pair.length < 2) return ["—", "—"]
        var a = pair[0], b = pair[1]
        if (a === b) return ["OBJ" + a, "OBJ" + a + "1"]
        return ["OBJ" + a, "OBJ" + b]
    }

    // ── COLOQUE A NOVA FUNÇÃO AQUI ──────────────────────────
    function getRadiusForObject(objId) {
        var match = objId.match(/OBJ([A-Z])/);
        if (!match) return 0.12;

        var letter = match[1];

        // A sua biblioteca exata da UFRN
        var pxSizes = {
            "A": 42, "B": 42, "C": 47, "G": 56,
            "F": 37, "J": 37, "N": 42, "D": 39,
            "R": 32, "E": 50, "P": 47, "I": 63
        };

        var px = pxSizes[letter];
        if (px === undefined) return 0.12; 

        // Regra de três: normaliza baseado no padrão de 93px (0.12)
        return (px / 93.0) * 0.12;
    }

    onExperimentPathChanged: {
        if (experimentPath !== "") {
            var expName = experimentPath.split('/').pop().split('\\').pop();

            ArenaConfigModel.loadConfig(root.context, expName);

            var meta = ExperimentManager.readMetadataFromPath(experimentPath);
            
            root.pair1 = meta.pair1 || "";
            root.pair2 = meta.pair2 || "";
            root.pair3 = meta.pair3 || "";
            
            var savedArena = ArenaConfigModel.getArenaPoints();
            var savedFloor = ArenaConfigModel.getFloorPoints();
            
            if (savedArena && savedArena !== "") {
                root.arenaPoints = JSON.parse(savedArena);
            }
            if (savedFloor && savedFloor !== "") {
                root.floorPoints = JSON.parse(savedFloor);
            }
            
            zoneInitTimer.restart();
        }
    }

    Connections {
        target: ArenaConfigModel
        onConfigChanged: zoneInitTimer.restart()
    }

    Timer {
        id: zoneInitTimer; interval: 60; repeat: false
        onTriggered: {
            var n = ArenaConfigModel.zoneCount()
            var nz = []
            
            for (var i = 0; i < 6; i++) {
                // Descobre de qual campo e de qual par este círculo pertence
                var campoIdx = Math.floor(i / 2)
                var campoPair = campoIdx === 0 ? root.pair1 : (campoIdx === 1 ? root.pair2 : root.pair3)
                
                // Extrai o ID ("OBJA", "OBJB", etc)
                var ids = root.zoneIdsForPair(campoPair)
                var objId = ids[i % 2]
                
                // Puxa o raio matemático automático baseado na letra
                var dynamicRadius = root.getRadiusForObject(objId)

                if (i < n) {
                    var z = ArenaConfigModel.zone(i)
                    // Força o círculo a ignorar o raio antigo salvo e usar o novo raio dinâmico!
                    nz.push({ x: z.xRatio, y: z.yRatio, r: dynamicRadius })
                } else {
                    // Círculos novos também já nascem com o tamanho correto
                    nz.push({ x: (i % 2 === 0 ? 0.3 : 0.7), y: 0.5, r: dynamicRadius })
                }
            }
            zones = nz
        }
    }

    // ── Player de vídeo offline ──────────────────────────────────────────────
    // Qt 6: MediaPlayer.videoOutput aponta para o VideoOutput; status → mediaStatus
    MediaPlayer {
        id: videoPlayer
        autoPlay: false
        videoOutput: framePreview
        onMediaStatusChanged: {
            // Quando o vídeo carrega, pulamos para 1 segundo (segurança contra tela preta)
            if (mediaStatus === MediaPlayer.LoadedMedia) {
                setPosition(1000)  // Qt 6: seek() → setPosition()
                pause()
            }
        }
    }

    FileDialog {
        id: videoFileDialog
        title: "Selecionar Vídeo de Análise"
        nameFilters: ["Vídeos (*.mp4 *.mpg *.mpeg *.avi *.mov)", "Todos os arquivos (*)"]
        onAccepted: {
            videoPlayer.stop()
            root.videoPath = selectedFile.toString()  // Qt 6: fileUrl → selectedFile
            videoPlayer.source = selectedFile
        }
    }

    // Popup: análise offline ou ao vivo?
    Popup {
        id: analysisModePrompt
        width: 400; height: 220
        anchors.centerIn: parent
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape

        background: Rectangle {
            radius: 14; color: "#1a1a2e"
            border.color: "#ab3d4c"; border.width: 1
        }

        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 14

            Text {
                text: "Tipo de Análise"; color: "#e8e8f0"
                font.pixelSize: 16; font.weight: Font.Bold
            }

            Text {
                Layout.fillWidth: true
                text: root.analysisMode === "" ? "Escolha o modo e carregue o vídeo:" : "Pronto para gravar!"
                color: "#8888aa"; font.pixelSize: 13
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 12

                // Análise Offline
                Rectangle {
                    Layout.fillWidth: true; height: 80; radius: 8
                    color: offBtnMa.offlineHover ? "#2a1f30" : "#16162e"
                    border.color: "#ab3d4c"; border.width: 2

                    property bool offlineHover: offBtnMa.containsMouse

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 4
                        Text {
                            text: "🎬  Análise Offline"; color: "#e8e8f0"
                            font.pixelSize: 13; font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            text: "Vídeo pré-gravado"; color: "#8888aa"
                            font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    MouseArea {
                        id: offBtnMa; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.analysisMode = "offline"
                            root.saveDirectory = ""
                            analysisModePrompt.close()
                            videoFileDialog.open()
                        }
                    }
                }

                // Análise Ao Vivo
                Rectangle {
                    Layout.fillWidth: true; height: 80; radius: 8
                    color: liveBtnMa.liveHover ? "#162a22" : "#16162e"
                    border.color: "#3a8a50"; border.width: 2

                    property bool liveHover: liveBtnMa.containsMouse

                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 4
                        Text {
                            text: "📹  Análise Ao Vivo"; color: "#e8e8f0"
                            font.pixelSize: 13; font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            text: "Câmera (salva o vídeo)"; color: "#8888aa"
                            font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    MouseArea {
                        id: liveBtnMa; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.analysisMode = "ao_vivo"
                            root.saveDirectory = ""
                            analysisModePrompt.close()
                            saveDirDialog.open()
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Item { Layout.fillWidth: true }
                GhostButton {
                    text: "Cancelar"; onClicked: {
                        root.videoPath = ""
                        analysisModePrompt.close()
                    }
                }
            }
        }
    }

    // Dialog: escolher diretório para salvar vídeo ao vivo
    Popup {
        id: saveDirDialog
        anchors.centerIn: parent
        width: 440; height: 180
        modal: true; focus: true; closePolicy: Popup.CloseOnEscape
        background: Rectangle {
            radius: 14; color: "#1a1a2e"
            border.color: "#ab3d4c"; border.width: 1
        }
        ColumnLayout {
            anchors { fill: parent; margins: 20 }
            spacing: 12
            Text {
                text: "Selecionar diretório"
                color: "#e8e8f0"; font.pixelSize: 15; font.weight: Font.Bold
            }
            TextField {
                id: savePathField
                Layout.fillWidth: true
                placeholderText: "Cole o caminho da pasta ou clique Pesquisar..."
                color: "#e8e8f0"; placeholderTextColor: "#8888aa"; font.pixelSize: 12
                onTextChanged: root.saveDirectory = text
                background: Rectangle {
                    radius: 6; color: "#12122a"
                    border.color: savePathField.activeFocus ? "#ab3d4c" : "#3a3a5c"
                    border.width: 1
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                GhostButton { text: "Cancelar"; onClicked: saveDirDialog.close() }
                Button {
                    text: "Confirmar"
                    enabled: savePathField.text.trim().length > 0
                    onClicked: {
                        root.saveDirectory = savePathField.text.trim()
                        saveDirDialog.close()
                    }
                    background: Rectangle {
                        radius: 8
                        color: parent.enabled ? (parent.hovered ? "#8a2e3b" : "#ab3d4c") : "#2d2d4a"
                    }
                    contentItem: Text {
                        text: parent.text; color: "#e8e8f0"
                        font.pixelSize: 13; font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    leftPadding: 18; rightPadding: 18; topPadding: 9; bottomPadding: 9
                }
            }
        }
    }

    // ── Layout principal ─────────────────────────────────────────────────────
    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 10

        // ── Barra superior ───────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 8

            Text {
                text: "Configuração da Arena"
                color: "#e8e8f0"; font.pixelSize: 14; font.weight: Font.Bold
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "Shift: Objetos  |  Ctrl: Quinas da Parede  |  Alt: Quinas do Chão"
                color: "#444466"; font.pixelSize: 10; verticalAlignment: Text.AlignVCenter
            }

            // ── Editar Pares ──
            Button {
                id: editPairsBtn
                text: "✏ Editar Pares"
                onClicked: editPairsPopup.open()
                
                background: Rectangle {
                    radius: 6
                    color: editPairsBtn.hovered ? "#25253e" : "#16162e"
                    border.color: editPairsBtn.hovered ? "#666688" : "#4a4a6c"
                    border.width: 2
                }
                
                contentItem: Text {
                    text: parent.text
                    color: editPairsBtn.hovered ? "#e8e8f0" : "#8888aa"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                leftPadding: 14; rightPadding: 14; topPadding: 6; bottomPadding: 6
            }

            // ── Dev Mode ──
            Button {
                id: devModeBtn
                text: root.devMode ? "🔧 Dev ON" : "🔧 Dev OFF"
                onClicked: root.devMode = !root.devMode
                
                background: Rectangle {
                    radius: 6
                    color: root.devMode ? (devModeBtn.hovered ? "#7a5500" : "#8a6200") : (devModeBtn.hovered ? "#25253e" : "#16162e")
                    border.color: root.devMode ? "#c88000" : (devModeBtn.hovered ? "#666688" : "#4a4a6c")
                    border.width: 2
                }
                
                contentItem: Text {
                    text: parent.text
                    color: root.devMode ? "#ffffff" : (devModeBtn.hovered ? "#e8e8f0" : "#8888aa")
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                // O padding força o botão a manter o seu tamanho independentemente do texto
                leftPadding: 14; rightPadding: 14; topPadding: 6; bottomPadding: 6
            }

            // ── Carregar Vídeo ────────────────────────────────────────────────
            Button {
                id: videoBtnRect
                text: root.videoPath !== "" ? "🎬 Vídeo ✓" : "🎬 Carregar Vídeo"
                onClicked: analysisModePrompt.open()
                
                background: Rectangle {
                    radius: 6
                    color: root.videoPath !== "" ? (videoBtnRect.hovered ? "#1a3a22" : "#1f4428") : (videoBtnRect.hovered ? "#25253e" : "#16162e")
                    border.color: root.videoPath !== "" ? "#3a8a50" : (videoBtnRect.hovered ? "#666688" : "#4a4a6c")
                    border.width: 2
                }
                
                contentItem: Text {
                    text: parent.text
                    color: root.videoPath !== "" ? "#ffffff" : (videoBtnRect.hovered ? "#e8e8f0" : "#8888aa")
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                // Mantém a área de clique grande e o botão estável
                leftPadding: 14; rightPadding: 14; topPadding: 6; bottomPadding: 6
            }

            // ── Salvar Configuração ──────────────────────────────────────────
            Button {
                text: "💾 Salvar Configuração"
                enabled: experimentPath !== "" && pair1 !== ""
                onClicked: {
                    var allZones = []
                    for (var i = 0; i < 6; i++) {
                        var z = zones[i]
                        // r: z.r já salva o tamanho do objeto atualizado!
                        allZones.push({ "xRatio": z.x, "yRatio": z.y, "radiusRatio": z.r, "objectId": "" })
                    }
                    
                    // Empacota os polígonos 3D em texto (JSON) para o C++
                    var arenaStr = JSON.stringify(root.arenaPoints)
                    var floorStr = JSON.stringify(root.floorPoints)

                    var expName = experimentPath.split('/').pop().split('\\').pop();

                    var pairId = pair1 + "/" + pair2 + "/" + pair3
                    if (ArenaConfigModel.saveConfig(root.context, expName, pairId, "", allZones, arenaStr, floorStr))
                        saveToast.show("Configuração salva em Documentos/MindTrace_Data!");
                }
                background: Rectangle {
                    radius: 7
                    color: parent.enabled ? (parent.hovered ? "#8a2e3b" : "#ab3d4c") : "#2d2d4a"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                contentItem: Text {
                    text: parent.text; color: "#e8e8f0"
                    font.pixelSize: 12; font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                leftPadding: 14; rightPadding: 14; topPadding: 7; bottomPadding: 7
            }
        }

        // ── Mosaico 2×2 ──────────────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            columns: 2; rowSpacing: 8; columnSpacing: 8

            // ── 3 Campos ─────────────────────────────────────────────────────
            Repeater {
                model: 3
                delegate: Item {
                    id: campoCell
                    Layout.fillWidth: true; Layout.fillHeight: true

                    property int    campoIndex: index
                    property string campoPair:  index === 0 ? root.pair1
                                              : index === 1 ? root.pair2
                                              : root.pair3
                    property var    campoIds:   root.zoneIdsForPair(campoPair)

                    ColumnLayout {
                        anchors { fill: parent; margins: 4 }
                        spacing: 4

                        // Rótulo
                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            Text {
                                text: "Campo " + (campoCell.campoIndex + 1)
                                color: "#8888aa"; font.pixelSize: 11; font.weight: Font.Bold
                            }
                            Rectangle {
                                visible: campoCell.campoPair !== ""
                                radius: 3; color: "#1f0d10"
                                border.color: "#ab3d4c"; border.width: 1
                                implicitWidth: pairTxt.implicitWidth + 10; implicitHeight: 16
                                Text {
                                    id: pairTxt; anchors.centerIn: parent
                                    text: "Par " + campoCell.campoPair
                                    color: "#ab3d4c"; font.pixelSize: 9
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }

                        // Arena quadrada
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true

                            Rectangle {
                                id: arenaRect
                                width:  Math.min(parent.width, parent.height)
                                height: width
                                anchors.centerIn: parent
                                color: "#0a0a16"
                                border.color: "#ab3d4c"; border.width: 2
                                clip: true

                                ShaderEffectSource {
                                    anchors.fill: parent
                                    visible: root.videoPath !== ""
                                    sourceItem: framePreview // Usando o id correto que configuramos

                                    // Recorta o quadrante 2×2 correspondente ao campo
                                    sourceRect: {
                                        if (!framePreview || framePreview.width === 0) return Qt.rect(0,0,0,0)

                                        // Puxa as coordenadas EXATAS do vídeo, ignorando faixas pretas
                                        var cr = framePreview.contentRect
                                        var cw = cr.width / 2
                                        var ch = cr.height / 2
                                        var cx = cr.x
                                        var cy = cr.y

                                        // Divide o quadrado do vídeo igual por igual
                                        if (campoCell.campoIndex === 0) return Qt.rect(cx,      cy,      cw, ch) // Topo-Esq (Campo 1)
                                        if (campoCell.campoIndex === 1) return Qt.rect(cx + cw, cy,      cw, ch) // Topo-Dir (Campo 2)
                                        return Qt.rect(cx,      cy + ch, cw, ch) // Baixo-Esq (Campo 3)
                                    }
                                    opacity: 0.9
                                }

                                // ── Limites 3D da Arena (Paredes + Chão Livres) ───────────
                                Canvas {
                                    id: arenaCanvas
                                    anchors.fill: parent
                                    visible: true

                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()
                                    Component.onCompleted: requestPaint()

                                    Connections {
                                        target: root
                                        onArenaPointsChanged: arenaCanvas.requestPaint()
                                        onFloorPointsChanged: arenaCanvas.requestPaint()
                                        onDevModeChanged:     arenaCanvas.requestPaint()
                                    }

                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);

                                        // Puxa as 8 variáveis de pontos
                                        var ap = root.arenaPoints[campoCell.campoIndex]; // <-- Novos pontos externos
                                        var fp = root.floorPoints[campoCell.campoIndex]; // <-- Pontos internos
                                        if (!ap || !fp) return;

                                        var w = width, h = height;

                                        // Borda Externa (Topo das paredes - Quadrilátero Livre)
                                        var oTL = {x: ap[0].x*w, y: ap[0].y*h}, oTR = {x: ap[1].x*w, y: ap[1].y*h};
                                        var oBR = {x: ap[2].x*w, y: ap[2].y*h}, oBL = {x: ap[3].x*w, y: ap[3].y*h};
                                        
                                        // Borda Interna (Chão - Quadrilátero Livre)
                                        var iTL = {x: fp[0].x*w, y: fp[0].y*h}, iTR = {x: fp[1].x*w, y: fp[1].y*h};
                                        var iBR = {x: fp[2].x*w, y: fp[2].y*h}, iBL = {x: fp[3].x*w, y: fp[3].y*h};

                                        function drawPoly(pts, fill, stroke) {
                                            ctx.beginPath();
                                            ctx.moveTo(pts[0].x, pts[0].y);
                                            for(var i=1; i<pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y);
                                            ctx.closePath();
                                            ctx.fillStyle = fill; ctx.fill();
                                            ctx.lineWidth = 1; ctx.strokeStyle = stroke; ctx.stroke();
                                        }

                                        // 3. DESENHA Paredes e Chão (na ordem correta de transparência)
                                        // Chão (Magenta)
                                        drawPoly([iTL, iTR, iBR, iBL], "rgba(255, 0, 255, 0.15)", "rgba(255, 0, 255, 0.6)");
                                        // Parede Topo (Vermelho)
                                        drawPoly([oTL, oTR, iTR, iTL], "rgba(255, 0, 0, 0.15)", "rgba(255, 0, 0, 0.6)");
                                        // Parede Fundo (Verde)
                                        drawPoly([iBL, iBR, oBR, oBL], "rgba(0, 255, 0, 0.15)", "rgba(0, 255, 0, 0.6)");
                                        // Parede Esquerda (Ciano)
                                        drawPoly([oTL, iTL, iBL, oBL], "rgba(0, 255, 255, 0.15)", "rgba(0, 255, 255, 0.6)");
                                        // Parede Direita (Amarelo)
                                        drawPoly([iTR, oTR, oBR, iBR], "rgba(255, 255, 0, 0.15)", "rgba(255, 255, 0, 0.6)");
                                        
                                        // Borda externa Laranja viva para referência
                                        ctx.strokeStyle = "rgba(255, 170, 0, 0.8)";
                                        ctx.lineWidth = 2;
                                        ctx.beginPath();
                                        ctx.moveTo(oTL.x, oTL.y); ctx.lineTo(oTR.x, oTR.y); ctx.lineTo(oBR.x, oBR.y); ctx.lineTo(oBL.x, oBL.y);
                                        ctx.closePath(); ctx.stroke();

                                        // 4. DESENHA Alças (bolinhas brancas) apenas em dev mode
                                        if (root.devMode) {
                                            ctx.fillStyle = "#ffffff";
                                            ctx.strokeStyle = "#000000";
                                            ctx.lineWidth = 1;
                                            var allPts = [iTL, iTR, iBR, iBL, oTL, oTR, oBR, oBL];
                                            for(var j=0; j<8; j++) {
                                                ctx.beginPath();
                                                ctx.arc(allPts[j].x, allPts[j].y, 4, 0, 2*Math.PI);
                                                ctx.fill(); ctx.stroke();
                                            }
                                        }
                                    }
                                }

                                // ── Zona A (vinho) ────────────────────────────
                                Rectangle {
                                    id: zoneA
                                    property var zd: root.zones[campoCell.campoIndex * 2]
                                    width:  arenaRect.width  * zd.r * 2
                                    height: width; radius: width / 2
                                    x: arenaRect.width  * zd.x - width  / 2
                                    y: arenaRect.height * zd.y - height / 2
                                    color: "#40ab3d4c"; border.color: "#ab3d4c"; border.width: 2

                                    Column {
                                        anchors.centerIn: parent; spacing: 1
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: campoCell.campoIds[0]; color: "#e8e8f0"
                                            font.pixelSize: Math.max(7, zoneA.width * 0.22)
                                            font.weight: Font.Bold
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Text {
                                            visible: root.devMode
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Math.round(zoneA.zd.r * arenaRect.width * 2) + "px Ø"
                                            color: "#ffcc00"
                                            font.pixelSize: Math.max(6, zoneA.width * 0.16)
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                    }
                                }

                                // ── Zona B (azul) ─────────────────────────────
                                Rectangle {
                                    id: zoneB
                                    property var zd: root.zones[campoCell.campoIndex * 2 + 1]
                                    width:  arenaRect.width  * zd.r * 2
                                    height: width; radius: width / 2
                                    x: arenaRect.width  * zd.x - width  / 2
                                    y: arenaRect.height * zd.y - height / 2
                                    color: "#404466aa"; border.color: "#4466aa"; border.width: 2

                                    Column {
                                        anchors.centerIn: parent; spacing: 1
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: campoCell.campoIds[1]; color: "#e8e8f0"
                                            font.pixelSize: Math.max(7, zoneB.width * 0.22)
                                            font.weight: Font.Bold
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Text {
                                            visible: root.devMode
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Math.round(zoneB.zd.r * arenaRect.width * 2) + "px Ø"
                                            color: "#ffcc00"
                                            font.pixelSize: Math.max(6, zoneB.width * 0.16)
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                    }
                                }

                                // ── Badge CAM (overlay canto sup-dir) ─────────
                                Rectangle {
                                    visible: root.videoPath !== ""
                                    anchors { top: parent.top; right: parent.right; margins: 4 }
                                    radius: 3; color: "#0d1f10"
                                    border.color: "#3a8a50"; border.width: 1
                                    width: camBadgeTxt.implicitWidth + 10; height: 16
                                    z: 10
                                    Text {
                                        id: camBadgeTxt; anchors.centerIn: parent
                                        text: "CAM " + (campoCell.campoIndex + 1)
                                        color: "#5aaa70"; font.pixelSize: 9
                                    }
                                }

                                // ── Overlay de interação ──────────────────────
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton
                                    
                                    property int dragZoneIdx: -1
                                    
                                    // Variáveis de quina livre
                                    property int dragOuterCorner: -1 // <-- Qual quina da PAREDE está a ser puxada (0 a 3)
                                    property int dragFloorCorner: -1 // <-- Qual quina do CHÃO está a ser puxada (0 a 3)

                                    onPressed: {
                                        if (!root.devMode) return;

                                        // Raio de captura de ~30 pixels (em ratio quadrado para otimizar)
                                        var capturingDist = 900;

                                        if (mouse.modifiers & Qt.ShiftModifier) {
                                            // -- Mover Objetos --
                                            var i0 = campoCell.campoIndex * 2, i1 = i0 + 1
                                            var cx0 = root.zones[i0].x * arenaRect.width
                                            var cy0 = root.zones[i0].y * arenaRect.height
                                            var cx1 = root.zones[i1].x * arenaRect.width
                                            var cy1 = root.zones[i1].y * arenaRect.height
                                            var d0 = (mouse.x-cx0)*(mouse.x-cx0)+(mouse.y-cy0)*(mouse.y-cy0)
                                            var d1 = (mouse.x-cx1)*(mouse.x-cx1)+(mouse.y-cy1)*(mouse.y-cy1)
                                            dragZoneIdx = d0 <= d1 ? i0 : i1
                                            var nz = root.zones.slice()
                                            nz[dragZoneIdx] = { x: mouse.x/arenaRect.width, y: mouse.y/arenaRect.height, r: root.zones[dragZoneIdx].r }
                                            root.zones = nz
                                        } else if (mouse.modifiers & Qt.ControlModifier) {
                                            // -- Puxar uma QUINA da PAREDE (Arena Externa) --
                                            var ap = root.arenaPoints[campoCell.campoIndex]
                                            var minDistOuter = capturingDist
                                            dragOuterCorner = -1
                                            for (var c=0; c<4; c++) {
                                                var px = ap[c].x * arenaRect.width
                                                var py = ap[c].y * arenaRect.height
                                                var dist = (mouse.x-px)*(mouse.x-px) + (mouse.y-py)*(mouse.y-py)
                                                if (dist < minDistOuter) { minDistOuter = dist; dragOuterCorner = c }
                                            }
                                        } else if (mouse.modifiers & Qt.AltModifier) {
                                            // -- Puxar uma QUINA do CHÃO --
                                            var fp = root.floorPoints[campoCell.campoIndex]
                                            var minDistFloor = capturingDist
                                            dragFloorCorner = -1
                                            for (var c=0; c<4; c++) {
                                                var px2 = fp[c].x * arenaRect.width
                                                var py2 = fp[c].y * arenaRect.height
                                                var dist2 = (mouse.x-px2)*(mouse.x-px2) + (mouse.y-py2)*(mouse.y-py2)
                                                if (dist2 < minDistFloor) { minDistFloor = dist2; dragFloorCorner = c }
                                            }
                                        }
                                    }

                                    onPositionChanged: {
                                        if (!root.devMode) return;
                                        if (dragZoneIdx >= 0) {
                                            var nz = root.zones.slice()
                                            nz[dragZoneIdx] = { x: mouse.x/arenaRect.width, y: mouse.y/arenaRect.height, r: root.zones[dragZoneIdx].r }
                                            root.zones = nz
                                        } else if (dragOuterCorner >= 0) {
                                            // -- Atualiza apenas a quina da PAREDE --
                                            var nap = root.arenaPoints.slice()
                                            var ptsAp = [{x: nap[campoCell.campoIndex][0].x, y: nap[campoCell.campoIndex][0].y},
                                                       {x: nap[campoCell.campoIndex][1].x, y: nap[campoCell.campoIndex][1].y},
                                                       {x: nap[campoCell.campoIndex][2].x, y: nap[campoCell.campoIndex][2].y},
                                                       {x: nap[campoCell.campoIndex][3].x, y: nap[campoCell.campoIndex][3].y}]
                                            
                                            ptsAp[dragOuterCorner] = { x: mouse.x / arenaRect.width, y: mouse.y / arenaRect.height }
                                            nap[campoCell.campoIndex] = ptsAp
                                            root.arenaPoints = nap // Triggers Connections requestPaint
                                        } else if (dragFloorCorner >= 0) {
                                            // -- Atualiza apenas a quina do CHÃO --
                                            var nfp = root.floorPoints.slice()
                                            var ptsFp = [{x: nfp[campoCell.campoIndex][0].x, y: nfp[campoCell.campoIndex][0].y},
                                                       {x: nfp[campoCell.campoIndex][1].x, y: nfp[campoCell.campoIndex][1].y},
                                                       {x: nfp[campoCell.campoIndex][2].x, y: nfp[campoCell.campoIndex][2].y},
                                                       {x: nfp[campoCell.campoIndex][3].x, y: nfp[campoCell.campoIndex][3].y}]
                                            
                                            ptsFp[dragFloorCorner] = { x: mouse.x / arenaRect.width, y: mouse.y / arenaRect.height }
                                            nfp[campoCell.campoIndex] = ptsFp
                                            root.floorPoints = nfp // Triggers Connections requestPaint
                                        }
                                    }

                                    onReleased: { dragZoneIdx = -1; dragOuterCorner = -1; dragFloorCorner = -1 }

                                    // (Mantenha o seu onWheel atual aqui embaixo igualzinho para os objetos)
                                    onWheel: {
                                        if (!root.devMode) return;
                                        
                                        if (wheel.modifiers & Qt.ShiftModifier) {
                                            // -- Redimensionar Objeto --
                                            var i0 = campoCell.campoIndex * 2, i1 = i0 + 1
                                            var cx0 = root.zones[i0].x * arenaRect.width
                                            var cy0 = root.zones[i0].y * arenaRect.height
                                            var cx1 = root.zones[i1].x * arenaRect.width
                                            var cy1 = root.zones[i1].y * arenaRect.height
                                            var d0 = (wheel.x-cx0)*(wheel.x-cx0)+(wheel.y-cy0)*(wheel.y-cy0)
                                            var d1 = (wheel.x-cx1)*(wheel.x-cx1)+(wheel.y-cy1)*(wheel.y-cy1)
                                            var ti = d0 <= d1 ? i0 : i1
                                            var stepObj = wheel.angleDelta.y > 0 ? 1.05 : 0.952
                                            var nz = root.zones.slice()
                                            nz[ti] = { x: nz[ti].x, y: nz[ti].y, r: Math.max(0.04, Math.min(0.48, nz[ti].r * stepObj)) }
                                            root.zones = nz
                                        }
                                    }
                                }

                                // Placeholder quando par não definido e sem vídeo
                                Text {
                                    anchors.centerIn: parent
                                    visible: campoCell.campoPair === "" && root.videoPath === ""
                                    text: "Par não definido"
                                    color: "#2d2d4a"; font.pixelSize: 10
                                }
                            }
                        }
                    }
                }
            }

            // ── Célula vazia: VideoOutput mestre + controles ──────────────────
            // masterVideoOut renderiza o vídeo inteiro aqui. ShaderEffectSource
            // nos campos acima captura esse item (via scene graph, não hardware overlay).
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                color: "#08080f"; border.color: "#1a1a2e"; border.width: 1; radius: 2

                ColumnLayout {
                    anchors { fill: parent; margins: 8 }
                    spacing: 6
                    visible: root.videoPath !== ""

                    // VideoOutput mestre — ocupa a maior parte da célula
                    // Qt 6: sem propriedade "source"; o MediaPlayer referencia este item
                    VideoOutput {
                        id: framePreview
                        anchors.fill: parent
                        fillMode: VideoOutput.PreserveAspectFit
                        visible: root.videoPath !== ""
                        opacity: 0.5 // Deixa o fundo suave para desenhar as zonas por cima
                    }

                    // Status do player
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            var s = videoPlayer.mediaStatus  // Qt 6: status → mediaStatus
                            if (s === MediaPlayer.LoadingMedia)  return "⏳ Carregando…"
                            if (s === MediaPlayer.InvalidMedia)  return "⚠ Formato inválido"
                            if (s === MediaPlayer.NoMedia)       return "Sem mídia"
                            return ""
                        }
                        color: videoPlayer.mediaStatus === MediaPlayer.InvalidMedia ? "#e84c5a" : "#8888aa"
                        font.pixelSize: 9
                        visible: text !== ""
                    }

                    // Controles: Play/Pause + Remover
                    RowLayout {
                        Layout.fillWidth: true; spacing: 6

                        // Play / Pause
                        Rectangle {
                            Layout.fillWidth: true; height: 24; radius: 5
                            color: playMa.containsMouse ? "#1a4a2a" : "#1f5430"
                            border.color: "#3a8a50"; border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: videoPlayer.playbackState === MediaPlayer.PlayingState
                                      ? "⏸ Pausar" : "▶ Reproduzir"
                                color: "#5aaa70"; font.pixelSize: 10; font.weight: Font.Bold
                            }
                            MouseArea {
                                id: playMa; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (videoPlayer.playbackState === MediaPlayer.PlayingState)
                                        videoPlayer.pause()
                                    else
                                        videoPlayer.play()
                                }
                            }
                        }

                        // Remover vídeo
                        Rectangle {
                            height: 24; radius: 5
                            implicitWidth: rmLbl.implicitWidth + 16
                            color: rmMa.containsMouse ? "#3a0d15" : "#2a0c18"
                            border.color: "#ab3d4c"; border.width: 1
                            Text {
                                id: rmLbl; anchors.centerIn: parent
                                text: "✕ Remover"; color: "#e88080"
                                font.pixelSize: 10
                            }
                            MouseArea {
                                id: rmMa; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    videoPlayer.stop()
                                    root.videoPath = ""
                                }
                            }
                        }
                    }
                }

                // Placeholder sem vídeo
                Column {
                    anchors.centerIn: parent
                    spacing: 6; visible: root.videoPath === ""
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "🎬"; font.pixelSize: 22; opacity: 0.15
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Análise offline\n(câmera 4 não usada)"
                        color: "#2d2d4a"; font.pixelSize: 9
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    // ── Popup para Editar Pares ─────────────────────────────────────────────
    Popup {
        id: editPairsPopup
        anchors.centerIn: parent
        width: 320; height: 260
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        // Quando abre, preenche os campos com os pares atuais
        onOpened: {
            editP1.text = root.pair1
            editP2.text = root.pair2
            editP3.text = root.pair3
        }

        background: Rectangle {
            radius: 12; color: "#1a1a2e"
            border.color: "#3a3a5c"; border.width: 1
        }

        ColumnLayout {
            anchors { fill: parent; margins: 20 }
            spacing: 14

            Text { text: "Editar Pares de Objetos"; color: "#e8e8f0"; font.pixelSize: 15; font.weight: Font.Bold }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#2d2d4a" }

            RowLayout {
                spacing: 10
                Text { text: "Campo 1:"; color: "#8888aa"; font.pixelSize: 12; Layout.preferredWidth: 60 }
                TextField {
                    id: editP1; Layout.fillWidth: true
                    color: "#e8e8f0"; font.pixelSize: 13; placeholderText: "Ex: AA"
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                    background: Rectangle { color: "#12122a"; border.color: editP1.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1; radius: 5 }
                }
            }
            RowLayout {
                spacing: 10
                Text { text: "Campo 2:"; color: "#8888aa"; font.pixelSize: 12; Layout.preferredWidth: 60 }
                TextField {
                    id: editP2; Layout.fillWidth: true
                    color: "#e8e8f0"; font.pixelSize: 13; placeholderText: "Ex: BB"
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                    background: Rectangle { color: "#12122a"; border.color: editP2.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1; radius: 5 }
                }
            }
            RowLayout {
                spacing: 10
                Text { text: "Campo 3:"; color: "#8888aa"; font.pixelSize: 12; Layout.preferredWidth: 60 }
                TextField {
                    id: editP3; Layout.fillWidth: true
                    color: "#e8e8f0"; font.pixelSize: 13; placeholderText: "Ex: CC"
                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                    background: Rectangle { color: "#12122a"; border.color: editP3.activeFocus ? "#ab3d4c" : "#3a3a5c"; border.width: 1; radius: 5 }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                Button {
                    text: "Cancelar"; onClicked: editPairsPopup.close()
                    background: Rectangle { color: "transparent" }
                    contentItem: Text { text: parent.text; color: "#8888aa"; font.pixelSize: 12; font.weight: Font.Bold }
                }
                Button {
                    text: "Aplicar"
                    onClicked: {
                        var p1 = editP1.text.trim().toUpperCase()
                        var p2 = editP2.text.trim().toUpperCase()
                        var p3 = editP3.text.trim().toUpperCase()

                        // Atualiza as variáveis locais da Arena
                        root.pair1 = p1
                        root.pair2 = p2
                        root.pair3 = p3

                        // Propaga para o dashboard (atualiza aba Dados e SessionResultDialog)
                        root.pairsEdited(p1, p2, p3)

                        // Força a re-leitura dos tamanhos dos objetos (sua biblioteca)
                        zoneInitTimer.restart()

                        editPairsPopup.close()
                        saveToast.show("Pares alterados! Não esqueça de Salvar a Configuração.")
                    }
                    background: Rectangle { radius: 6; color: parent.hovered ? "#8a2e3b" : "#ab3d4c" }
                    contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 12; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    leftPadding: 16; rightPadding: 16; topPadding: 8; bottomPadding: 8
                }
            }
        }
    }

    Toast {
        id: saveToast; successMode: true
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 12 }
    }
}
