import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

// Servidor de notificaciones propio (reemplaza a mako).
// - "emergentes": los popups que se ven ahora (arriba a la derecha).
// - "historial": todo lo recibido (se ve en el panel del reloj).
// - No molestar y pantalla completa: no salen popups (salvo las urgentes), pero sí se guardan en el historial.
// El historial se copia en $XDG_RUNTIME_DIR/avisos (memoria, se borra al cerrar sesión)
// para sobrevivir a un reinicio de la barra; tras reiniciar ya no tiene botones de acción.
Scope {
    id: av

    property int maxHistorial: 60
    property int maxEmergentes: 4
    property int duracionNormal: 6000      // ms si la app no pide otra cosa
    // Si la lista no se está viendo, se quita al instante (sin esperar a la animación)
    property bool historialVisible: false
    property bool emergentesVisibles: true
    onHistorialVisibleChanged: if (!historialVisible) av.purgar(historial)
    onEmergentesVisiblesChanged: if (!emergentesVisibles) av.purgar(emergentes)
    function purgar(modelo) {
        for (var i = modelo.count - 1; i >= 0; i--) if (modelo.get(i).saliendo) modelo.remove(i)
    }
    property int sinLeer: 0
    readonly property bool noMolestar: ajustes.noMolestar
    // Hay una ventana a pantalla completa en el monitor enfocado (lo pone la barra)
    property bool callarPantallaCompleta: false
    // Qué hacer entonces con los normales: campanita | silencio | completo (Ajustes → Notificaciones)
    property string modoPantallaCompleta: "campanita"
    readonly property bool callarPC: av.callarPantallaCompleta && av.modoPantallaCompleta !== "completo"
    signal vaAMostrar()
    readonly property bool callar: av.noMolestar || av.callarPC
    // Al entrar en pantalla completa se retiran los popups normales que había (siguen en el historial)
    onCallarPCChanged: if (callarPC)
        for (var i = emergentes.count - 1; i >= 0; i--)
            if (emergentes.get(i).urgencia !== 2) av.quitarEmergente(emergentes.get(i).clave)
    // Campanita: el número acumula durante esa pantalla completa, aunque la píldora se vaya y vuelva
    property int nuevosPC: 0
    property string tituloPC: ""
    signal sonarCampanita()
    onCallarPantallaCompletaChanged: if (!callarPantallaCompleta) av.nuevosPC = 0
    // Claves de avisos callados por pantalla completa: si la app los retira, siguen en el historial
    property var sinVer: ({})

    property ListModel historial: ListModel {}
    property ListModel emergentes: ListModel {}

    // clave -> objeto Notification vivo (para acciones y descartar)
    property var vivos: ({})
    // Claves únicas también entre reinicios (empiezan en la hora actual en ms)
    property real contador: Date.now()
    property string carpeta: Quickshell.env("XDG_RUNTIME_DIR") + "/avisos"

    function ponerNoMolestar(v) { ajustes.noMolestar = v }

    // ===== Servidor D-Bus =====
    NotificationServer {
        id: servidor
        // Al recargar, el historial sale del archivo; si no, se duplicarían
        keepOnReload: false
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: false

        onNotification: n => av.recibir(n)
    }

    // ===== Iconos =====
    function esRuta(t) { return t && (t.startsWith("/") || t.startsWith("file://")) }
    function aUrl(t) { return t.startsWith("/") ? "file://" + t : t }
    function esImagen(t) { return /\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(t) }

    function iconoDe(n) {
        var ic = n.appIcon || ""
        if (ic !== "" && !av.esRuta(ic)) {
            var p = Quickshell.iconPath(ic, true)
            if (p) return p
        }
        if (av.esRuta(ic) && !av.esImagen(ic)) return av.aUrl(ic)
        // notify-send -i <nombre> llega como imagen "image://icon/<nombre>": es un icono
        if (n.image && n.image.startsWith("image://icon/") && !av.esFotoIcono(n.image)) return n.image
        var e = n.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : null
        if (!e && n.appName) e = DesktopEntries.heuristicLookup(n.appName)
        if (e && e.icon) {
            var q = Quickshell.iconPath(e.icon, true)
            if (q) return q
        }
        return ""
    }
    // Imagen grande: la que manda la app, o un -i con ruta a una foto (p. ej. capturas)
    // "image://icon//ruta/a/foto.png" = notify-send -i con una ruta a imagen
    function esFotoIcono(t) { return t.startsWith("image://icon//") && av.esImagen(t) }
    function imagenDe(n) {
        if (n.image && av.esFotoIcono(n.image)) return "file://" + n.image.slice("image://icon/".length)
        if (n.image && !n.image.startsWith("image://icon/")) return n.image
        var ic = n.appIcon || ""
        if (av.esRuta(ic) && av.esImagen(ic)) return av.aUrl(ic)
        return ""
    }

    // ===== Adónde lleva cada aviso =====
    // Los avisos propios dicen su destino con la pista x-hola-destino (notify-send -h string:x-hola-destino:…):
    //   captura:<ruta>  clic → Gwenview, botón Editar → GIMP
    //   video:<ruta>    clic → Haruna, botón Carpeta → Dolphin
    //   carpeta:<ruta>  clic → Dolphin con el archivo seleccionado
    //   pagina:<nombre> clic → esa página del panel de estado
    //   ajustes:<sec>   clic → Ajustes en esa sección
    // Sin destino: la acción "default" de la app si sigue viva, y enfocar su ventana en niri.
    // Se guarda en el historial: funciona también tras recargar la barra.
    function destinoDe(n) {
        var h = n.hints || {}
        var v = h["x-hola-destino"]
        if (v) return String(v)
        // Capturas antiguas (antes de la pista): la ruta llega como -i
        var foto = av.imagenDe(n)
        if (n.appName === "Capturas" && foto.startsWith("file://")) return "captura:" + foto.slice(7)
        return ""
    }
    function botonesDe(destino) {
        if (destino.startsWith("captura:")) return [{ id: "hola:editar", texto: "Editar" }]
        if (destino.startsWith("video:")) return [{ id: "hola:carpeta", texto: "Carpeta" }]
        return []
    }

    function datos(n, clave) {
        var acc = []
        var lista = n.actions || []
        for (var i = 0; i < lista.length; i++)
            acc.push({ id: lista[i].identifier, texto: lista[i].text })
        return {
            clave: clave,
            app: n.appName || "Aviso",
            icono: av.iconoDe(n),
            imagen: av.imagenDe(n),
            resumen: n.summary || "",
            cuerpo: n.body || "",
            hora: Date.now(),
            urgencia: n.urgency === NotificationUrgency.Critical ? 2 : n.urgency === NotificationUrgency.Low ? 0 : 1,
            acciones: JSON.stringify(acc),
            destino: av.destinoDe(n),
            botones: JSON.stringify(av.botonesDe(av.destinoDe(n))),
            entrada: n.desktopEntry || "",
            nota: "",
            vivo: true,
            // ms (expireTimeout ya viene en ms); 0 = se queda hasta que la cierres
            duracion: n.expireTimeout > 0 ? Math.round(n.expireTimeout)
                : n.expireTimeout === 0 ? 0
                : n.urgency === NotificationUrgency.Critical ? 0 : av.duracionNormal,
            saliendo: false
        }
    }

    function indice(modelo, clave) {
        for (var i = 0; i < modelo.count; i++)
            if (modelo.get(i).clave === clave) return i
        return -1
    }
    function claveDe(n) {
        for (var k in av.vivos) if (av.vivos[k] === n) return parseInt(k)
        return -1
    }

    // ===== Llegada =====
    function recibir(n) {
        // niri avisa en inglés al hacer captura; el panel de Capturas manda uno propio
        if (n.appName === "niri" && /Screenshot captured/i.test(n.summary)) return

        var previa = av.claveDe(n)
        if (previa >= 0) { av.actualizar(previa, true); return }

        n.tracked = true
        var clave = ++av.contador
        av.vivos[clave] = n
        var fila = av.datos(n, clave)

        historial.insert(0, fila)
        while (historial.count > av.maxHistorial) av.olvidar(historial.get(historial.count - 1).clave)

        n.closed.connect(function (motivo) { av.alCerrar(clave, motivo) })
        var refresco = function () { av.actualizar(clave, false) }
        n.summaryChanged.connect(refresco)
        n.bodyChanged.connect(refresco)
        n.actionsChanged.connect(refresco)
        n.imageChanged.connect(refresco)

        av.sinLeer++
        if (!av.callar || fila.urgencia === 2) av.mostrar(fila)
        else if (av.callarPC) av.calladoEnPC(fila)
        guardar.restart()
    }

    function calladoEnPC(fila) {
        av.sinVer[fila.clave] = true
        if (av.noMolestar || av.modoPantallaCompleta !== "campanita" || !av.emergentesVisibles) return
        av.nuevosPC++
        av.tituloPC = fila.resumen || fila.app
        av.sonarCampanita()
    }

    function mostrar(fila) {
        var i = av.indice(emergentes, fila.clave)
        if (i >= 0) { emergentes.set(i, fila); return }
        av.vaAMostrar()    // antes de insertar: así la ventana ya está en su monitor
        emergentes.insert(0, fila)
        // Demasiados: el más viejo se va (sigue en el historial)
        var visibles = 0
        for (var j = 0; j < emergentes.count; j++) {
            if (emergentes.get(j).saliendo) continue
            if (++visibles > av.maxEmergentes) emergentes.setProperty(j, "saliendo", true)
        }
    }

    // La app cambió la notificación (o la reemplazó con replaces_id)
    function actualizar(clave, reaparecer) {
        var n = av.vivos[clave]
        if (!n) return
        var nueva = av.datos(n, clave)
        var i = av.indice(historial, clave)
        if (i >= 0) {
            nueva.hora = reaparecer ? Date.now() : historial.get(i).hora
            historial.set(i, nueva)
            if (reaparecer && i > 0) historial.move(i, 0, 1)
        }
        var j = av.indice(emergentes, clave)
        if (j >= 0) emergentes.set(j, nueva)
        else if (reaparecer && (!av.callar || nueva.urgencia === 2)) av.mostrar(nueva)
        guardar.restart()
    }

    function alCerrar(clave, motivo) {
        delete av.vivos[clave]
        var sinVer = !!av.sinVer[clave]
        delete av.sinVer[clave]
        // La app la retiró: fuera de todas partes, salvo si llegó en pantalla completa y no se llegó a ver
        if (motivo === NotificationCloseReason.CloseRequested && !sinVer) {
            av.quitarEmergente(clave)
            av.quitarHistorial(clave)
        } else {
            var i = av.indice(historial, clave)
            if (i >= 0) { historial.setProperty(i, "vivo", false); historial.setProperty(i, "acciones", "[]") }
        }
        guardar.restart()
    }

    // ===== Acciones del usuario =====
    // Ocultar el popup (sigue en el historial)
    function quitarEmergente(clave) {
        var i = av.indice(emergentes, clave)
        if (i < 0) return
        if (av.emergentesVisibles) emergentes.setProperty(i, "saliendo", true)
        else emergentes.remove(i)
    }
    // Lo llama el popup cuando terminó su animación de salida
    function borrarEmergente(clave) {
        var i = av.indice(emergentes, clave)
        if (i >= 0) emergentes.remove(i)
    }
    function quitarHistorial(clave) {
        var i = av.indice(historial, clave)
        if (i < 0) return
        if (av.historialVisible) historial.setProperty(i, "saliendo", true)
        else { historial.remove(i); guardar.restart() }
    }
    function borrarHistorial(clave) {
        var i = av.indice(historial, clave)
        if (i >= 0) historial.remove(i)
        guardar.restart()
    }
    // Sin animación (recorte del historial)
    function olvidar(clave) {
        var n = av.vivos[clave]
        delete av.vivos[clave]
        if (n) n.dismiss()
        var i = av.indice(historial, clave)
        if (i >= 0) historial.remove(i)
    }

    // ✕: descartar de verdad (popup + historial) y avisar a la app
    function descartar(clave) {
        var n = av.vivos[clave]
        delete av.vivos[clave]
        av.quitarEmergente(clave)
        av.quitarHistorial(clave)
        if (n) n.dismiss()
        guardar.restart()
    }

    function invocar(clave, idAccion) {
        var n = av.vivos[clave]
        if (!n) return false
        var residente = n.resident
        var lista = n.actions || []
        var a = null
        for (var i = 0; i < lista.length; i++) if (lista[i].identifier === idAccion) a = lista[i]
        if (!a) return false
        a.invoke()
        if (residente) {
            av.quitarEmergente(clave)
        } else {
            // Quickshell puede haberla cerrado ya al invocar; si no, la cerramos
            if (av.vivos[clave]) { delete av.vivos[clave]; n.dismiss() }
            av.quitarEmergente(clave)
            av.quitarHistorial(clave)
        }
        guardar.restart()
        return true
    }

    // Clic en el cuerpo (id "") o en un botón propio ("hola:…"): lleva a su destino.
    // Al terminar emite hecho(clave): el popup se va y el panel de avisos se cierra.
    signal hecho(real clave)
    signal irAPagina(string nombre)
    function clicCuerpo(clave) { av.activar(clave, "") }

    function fila(clave) {
        var i = av.indice(historial, clave)
        if (i >= 0) return historial.get(i)
        var j = av.indice(emergentes, clave)
        return j >= 0 ? emergentes.get(j) : null
    }
    function listo(clave) {
        av.quitarEmergente(clave)
        av.hecho(clave)
    }
    function ponerNota(clave, texto) {
        var i = av.indice(historial, clave)
        if (i >= 0) historial.setProperty(i, "nota", texto)
        var j = av.indice(emergentes, clave)
        if (j >= 0) emergentes.setProperty(j, "nota", texto)
    }

    function activar(clave, id) {
        var f = av.fila(clave)
        if (!f) return
        var dest = f.destino || ""
        var p = dest.indexOf(":")
        var tipo = p > 0 ? dest.slice(0, p) : ""
        var arg = p > 0 ? dest.slice(p + 1) : ""
        if (tipo === "captura" || tipo === "video" || tipo === "carpeta") {
            var cmd = tipo === "captura" ? (id === "hola:editar" ? ["gimp", arg] : ["gwenview", arg])
                : tipo === "video" ? (id === "hola:carpeta" ? ["dolphin", "--select", arg] : ["haruna", arg])
                : ["dolphin", "--select", arg]
            av.abrirArchivo(clave, arg, cmd)
            return
        }
        if (tipo === "pagina") { av.listo(clave); av.irAPagina(arg); return }
        if (tipo === "ajustes") {
            Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/ajustes-abrir.sh", arg])
            av.listo(clave)
            return
        }
        // Avisos de otras apps: su acción "default" si sigue viva y, además, enfocar su ventana
        var n = av.vivos[clave]
        if (n && (n.actions || []).some(a => a.identifier === "default")) av.invocar(clave, "default")
        av.enfocarApp(clave, [f.entrada || "", f.app || ""])
    }

    // Comprueba que el archivo existe y que el programa está instalado antes de abrirlo
    function abrirArchivo(clave, ruta, cmd) {
        if (pAbrir.running) return
        pAbrir.clave = clave
        pAbrir.cmd = cmd
        pAbrir.ruta = ruta
        pAbrir.command = ["sh", "-c", '[ -e "$1" ] || exit 3; command -v "$2" >/dev/null || exit 4', "sh", ruta, cmd[0]]
        pAbrir.running = true
    }
    Process {
        id: pAbrir
        property real clave
        property var cmd: []
        property string ruta: ""
        onExited: code => {
            if (code === 0) {
                Quickshell.execDetached(pAbrir.cmd)
                av.listo(pAbrir.clave)
            } else if (code === 4) {
                av.ponerNota(pAbrir.clave, "Falta instalar " + pAbrir.cmd[0])
            } else {
                av.ponerNota(pAbrir.clave, "El archivo ya no existe: " + pAbrir.ruta.replace(/^.*\//, ""))
            }
        }
    }

    // app_id de niri frente al nombre de la app o su .desktop (firefox, org.telegram.desktop…)
    function coincide(appId, nombres) {
        var a = (appId || "").toLowerCase()
        if (a === "") return false
        return nombres.some(function (n) {
            n = (n || "").toLowerCase().replace(/\.desktop$/, "")
            if (n.length < 3) return false
            return a === n || a.endsWith("." + n) || n.endsWith("." + a) || (n.length >= 4 && a.indexOf(n) >= 0)
        })
    }
    function enfocarApp(clave, nombres) {
        if (pVentanas.running) { av.listo(clave); return }
        pVentanas.clave = clave
        pVentanas.nombres = nombres
        pVentanas.running = true
    }
    Process {
        id: pVentanas
        property real clave
        property var nombres: []
        command: ["niri", "msg", "-j", "windows"]
        stdout: StdioCollector { id: salidaVentanas }
        onExited: {
            var l = []
            try { l = JSON.parse(salidaVentanas.text) } catch (e) {}
            // La que pidió atención primero (la app la marca urgente al avisar)
            var c = l.filter(w => av.coincide(w.app_id, pVentanas.nombres))
                     .sort((x, y) => (y.is_urgent ? 1 : 0) - (x.is_urgent ? 1 : 0))
            if (c.length > 0) Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(c[0].id)])
            av.listo(pVentanas.clave)
        }
    }

    function limpiar() {
        for (var k in av.vivos) {
            var n = av.vivos[k]
            if (n) n.dismiss()
        }
        av.vivos = ({})
        if (av.emergentesVisibles) for (var i = 0; i < emergentes.count; i++) emergentes.setProperty(i, "saliendo", true)
        else emergentes.clear()
        historial.clear()
        av.sinLeer = 0
        av.nuevosPC = 0
        guardar.restart()
    }

    // ===== Texto de hora relativa =====
    function hace(ms, ahora) {
        var s = Math.max(0, (ahora.getTime() - ms) / 1000)
        if (s < 60) return "ahora"
        if (s < 3600) return "hace " + Math.floor(s / 60) + " min"
        var d = new Date(ms)
        if (s < 6 * 3600) return "hace " + Math.floor(s / 3600) + " h"
        var hoy = new Date(ahora.getFullYear(), ahora.getMonth(), ahora.getDate())
        if (d >= hoy) return Qt.formatTime(d, "hh:mm")
        if (d >= new Date(hoy.getTime() - 86400000)) return "ayer " + Qt.formatTime(d, "hh:mm")
        return Qt.formatDateTime(d, "d MMM hh:mm")
    }

    // ===== No molestar (se recuerda en hola/avisos.json) =====
    FileView {
        id: archivoAjustes
        path: Quickshell.shellDir + "/avisos.json"
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter() }
        onAdapterUpdated: writeAdapter()
        JsonAdapter {
            id: ajustes
            property bool noMolestar: false
        }
    }

    // ===== Copia del historial en memoria ($XDG_RUNTIME_DIR) =====
    Process {
        id: preparar
        running: true
        command: ["mkdir", "-p", "-m", "700", av.carpeta]
        onExited: archivoHistorial.path = av.carpeta + "/historial.json"
    }
    FileView {
        id: archivoHistorial
        printErrors: false
        onLoaded: {
            try {
                var l = JSON.parse(text())
                for (var i = 0; i < l.length; i++) {
                    var f = l[i]
                    f.vivo = false
                    f.acciones = "[]"
                    f.saliendo = false
                    // Capturas guardadas antes de existir el destino: la ruta está en la imagen
                    f.destino = f.destino || (f.app === "Capturas" && (f.imagen || "").startsWith("file://")
                                              ? "captura:" + f.imagen.slice(7) : "")
                    f.botones = JSON.stringify(av.botonesDe(f.destino))
                    f.entrada = f.entrada || ""
                    f.nota = ""
                    if (av.indice(historial, f.clave) < 0) historial.append(f)
                    av.contador = Math.max(av.contador, f.clave)
                }
            } catch (e) {}
        }
    }
    Timer {
        id: guardar
        interval: 600
        onTriggered: {
            if (archivoHistorial.path === "") return
            var l = []
            for (var i = 0; i < historial.count; i++) {
                var f = historial.get(i)
                if (f.saliendo) continue
                l.push({ clave: f.clave, app: f.app, icono: f.icono,
                    // las imágenes en memoria de la app (image://) no sobreviven
                    imagen: f.imagen.startsWith("image://") ? "" : f.imagen,
                    resumen: f.resumen, cuerpo: f.cuerpo, hora: f.hora, urgencia: f.urgencia,
                    duracion: f.duracion, destino: f.destino, entrada: f.entrada })
            }
            archivoHistorial.setText(JSON.stringify(l))
        }
    }
}
