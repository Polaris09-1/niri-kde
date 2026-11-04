import QtQuick

// Todo lo que muestra la app: secciones y opciones. Cada opción se declara una sola vez;
// de aquí salen la pantalla, el buscador y "Restablecer". Una sección nueva solo añade filas.
//
// Tipos de opción: interruptor · deslizador (min, max, paso, unidad) · elegir (lista de {v, t}) ·
// texto (ejemplo) · libre (la pinta la propia sección; aquí solo está para que el buscador la encuentre).
// Las claves "niri." e "infinito." se escriben en ~/.config/niri/ajustes.kdl; las demás, en ajustes.json.
QtObject {
    readonly property var secciones: [
        { id: "apariencia", t: "Apariencia", ic: 0xF03D8, fase: 3 },
        { id: "barra", t: "Barra y píldoras", ic: 0xF056E, d: "Qué se ve en la barra superior y cómo se comporta." },
        { id: "dock", t: "Dock y escritorio", ic: 0xF0379, fase: 3 },
        { id: "pantalla", t: "Pantalla", ic: 0xF0379, d: "Cada cambio de monitor se prueba y vuelve solo si no lo confirmas.",
          restablece: "Quita lo elegido aquí para cada monitor. No cambia el brillo ni la luz nocturna." },
        { id: "sonido", t: "Sonido", ic: 0xF057E, d: "Salida, entrada y volumen de cada aplicación.", propia: true,
          restablece: "Pone todas las aplicaciones al 100 % y sin silenciar. No cambia la salida ni la entrada." },
        { id: "red", t: "Red y Bluetooth", ic: 0xF05A9, d: "Conexiones, redes guardadas y dispositivos.", sinRestablecer: true },
        { id: "energia", t: "Energía y bloqueo", ic: 0xF0079, d: "Modos de energía, batería y cuándo se bloquea o suspende.",
          restablece: "Vuelve a los tiempos de fábrica. No cambia el modo de energía, el límite de carga ni la cafeína." },
        { id: "entrada", t: "Teclado, mouse y touchpad", ic: 0xF030C, d: "Se aplica al instante. niri comprueba cada cambio antes de usarlo." },
        { id: "atajos", t: "Atajos", ic: 0xF0633, fase: 4 },
        { id: "avisos", t: "Notificaciones", ic: 0xF009A, d: "Se aplica al instante. Los avisos siempre quedan en el historial de la campana." },
        { id: "apps", t: "Aplicaciones", ic: 0xF003B, fase: 4 },
        { id: "terminal", t: "Terminal", ic: 0xF018D, fase: 5 },
        { id: "fecha", t: "Fecha, hora e idioma", ic: 0xF0150, fase: 5 },
        { id: "acerca", t: "Acerca de", ic: 0xF02FC, fase: 5 }
    ]

    readonly property var opciones: [
        // ---------- Teclado, mouse y touchpad ----------
        { id: "niri.kb.layout", s: "entrada", g: "Teclado", tipo: "texto", def: "", t: "Distribución",
          a: "Una o varias separadas por coma: us, latam, es. Vacío = la del sistema.", ejemplo: "del sistema",
          p: "idioma layout xkb teclado español latino" },
        { id: "niri.kb.options", s: "entrada", g: "Teclado", tipo: "texto", def: "", t: "Opciones de teclado",
          a: "Opciones XKB. Por ejemplo, grp:win_space_toggle cambia de distribución.", ejemplo: "ninguna",
          p: "xkb compose ctrl nocaps" },
        { id: "niri.kb.delay", s: "entrada", g: "Teclado", tipo: "deslizador", def: 600, min: 150, max: 1000, paso: 10, unidad: " ms",
          t: "Espera antes de repetir", a: "Tiempo manteniendo una tecla hasta que empieza a repetirse.", p: "repeticion retardo delay tecla" },
        { id: "niri.kb.rate", s: "entrada", g: "Teclado", tipo: "deslizador", def: 25, min: 5, max: 60, paso: 1, unidad: " /s",
          t: "Velocidad de repetición", a: "Cuántas veces por segundo se repite la tecla.", p: "repeticion rate tecla" },
        { id: "niri.kb.numlock", s: "entrada", g: "Teclado", tipo: "interruptor", def: true, t: "Bloq Num al iniciar", p: "numlock numerico" },

        { id: "niri.tp.tap", s: "entrada", g: "Touchpad", tipo: "interruptor", def: true, t: "Tocar para hacer clic", p: "tap clic toque" },
        { id: "niri.tp.natural", s: "entrada", g: "Touchpad", tipo: "interruptor", def: true, t: "Desplazamiento natural",
          a: "El contenido sigue a los dedos.", p: "scroll natural invertido" },
        { id: "niri.tp.speed", s: "entrada", g: "Touchpad", tipo: "deslizador", def: 0, min: -1, max: 1, paso: 0.05, t: "Velocidad del cursor", p: "aceleracion accel sensibilidad" },
        { id: "niri.tp.scroll", s: "entrada", g: "Touchpad", tipo: "deslizador", def: 1, min: 0.1, max: 3, paso: 0.1, unidad: " ×", t: "Velocidad de desplazamiento", p: "scroll factor" },
        { id: "avisos.pantallaCompleta", s: "avisos", g: "Pantalla completa", tipo: "elegir", def: "campanita", t: "Avisos normales",
          lista: [{ v: "campanita", t: "Campanita discreta" }, { v: "silencio", t: "Silencio total" }, { v: "completo", t: "Aviso completo" }],
          p: "pantalla completa notificaciones avisos silencio campanita video" },
        { id: "niri.tp.perfil", s: "entrada", g: "Touchpad", tipo: "elegir", def: "adaptive", t: "Aceleración",
          lista: [{ v: "adaptive", t: "Adaptable" }, { v: "flat", t: "Plana" }], p: "perfil profile accel" },
        { id: "niri.tp.dwt", s: "entrada", g: "Touchpad", tipo: "interruptor", def: false, t: "Desactivar mientras escribes", p: "dwt palma" },
        { id: "niri.tp.externo", s: "entrada", g: "Touchpad", tipo: "interruptor", def: false, t: "Desactivar con un mouse conectado", p: "externo usb" },

        { id: "niri.mouse.speed", s: "entrada", g: "Mouse", tipo: "deslizador", def: 0, min: -1, max: 1, paso: 0.05, t: "Velocidad del cursor", p: "aceleracion accel sensibilidad raton" },
        { id: "niri.mouse.natural", s: "entrada", g: "Mouse", tipo: "interruptor", def: false, t: "Desplazamiento natural", p: "scroll rueda invertido raton" },
        { id: "niri.mouse.scroll", s: "entrada", g: "Mouse", tipo: "deslizador", def: 1, min: 0.1, max: 3, paso: 0.1, unidad: " ×", t: "Velocidad de la rueda", p: "scroll factor raton" },
        { id: "niri.mouse.perfil", s: "entrada", g: "Mouse", tipo: "elegir", def: "adaptive", t: "Aceleración",
          lista: [{ v: "adaptive", t: "Adaptable" }, { v: "flat", t: "Plana" }], p: "perfil profile accel raton" },
        { id: "niri.mouse.zurdo", s: "entrada", g: "Mouse", tipo: "interruptor", def: false, t: "Botones para zurdos", p: "izquierda left handed raton" },

        { id: "infinito.workspaces", s: "entrada", g: "Modo infinito", tipo: "interruptor", def: true, t: "Workspaces en ciclo",
          a: "Super+U/I, Super+rueda y Super + dos dedos dan la vuelta. El escritorio vacío es una parada.", p: "circular vuelta" },
        { id: "infinito.columnas", s: "entrada", g: "Modo infinito", tipo: "interruptor", def: true, t: "Columnas y ventanas en ciclo",
          a: "Super+flechas dan la vuelta entre columnas y dentro de la columna.", p: "circular vuelta" },

        // ---------- Barra y píldoras ----------
        { id: "barra.islaIzq", s: "barra", g: "Islas", tipo: "interruptor", def: true, t: "Isla de workspaces", a: "Workspaces y ventana activa, a la izquierda.", p: "izquierda" },
        { id: "barra.titulo", s: "barra", g: "Islas", tipo: "interruptor", def: true, t: "Ventana activa", a: "Icono y título de la ventana con el foco.", p: "titulo" },
        { id: "barra.fecha", s: "barra", g: "Islas", tipo: "interruptor", def: true, t: "Fecha junto a la hora", p: "dia reloj" },
        { id: "barra.campana", s: "barra", g: "Islas", tipo: "interruptor", def: true, t: "Campanita de avisos", p: "notificaciones" },
        { id: "barra.bandeja", s: "barra", g: "Islas", tipo: "interruptor", def: true, t: "Bandeja del sistema", p: "tray iconos" },

        { id: "barra.musica", s: "barra", g: "Píldoras", tipo: "interruptor", def: true, t: "Píldora de música", a: "Aparece junto a la hora cuando algo suena.", p: "reproduciendo ondas cancion" },
        { id: "musica.ondasReales", s: "barra", g: "Píldoras", tipo: "interruptor", def: true, t: "Ondas con el sonido real", a: "Apagado: una animación simulada.", p: "cava musica" },
        { id: "musica.esperaOcultar", s: "barra", g: "Píldoras", tipo: "deslizador", def: 10, min: 3, max: 60, paso: 1, unidad: " s", t: "Ocultar la música tras pausar", p: "pausa tiempo" },
        { id: "barra.cafeina", s: "barra", g: "Píldoras", tipo: "interruptor", def: true, t: "Taza de cafeína", a: "Se ve mientras «Mantener despierto» está encendido.", p: "despierto" },
        { id: "barra.iconoWifi", s: "barra", g: "Píldoras", tipo: "interruptor", def: true, t: "Wi-Fi en la píldora de estado", p: "red icono" },
        { id: "barra.iconoVolumen", s: "barra", g: "Píldoras", tipo: "interruptor", def: true, t: "Volumen en la píldora de estado", p: "sonido icono" },
        { id: "barra.iconoBateria", s: "barra", g: "Píldoras", tipo: "interruptor", def: true, t: "Batería en la píldora de estado", p: "energia icono" },

        { id: "barra.esconderPC", s: "barra", g: "Pantalla completa", tipo: "interruptor", def: true, t: "Esconder la barra", a: "Baja al acercar el mouse al borde de arriba.", p: "ocultar fullscreen" },
        { id: "barra.altoSensor", s: "barra", g: "Pantalla completa", tipo: "deslizador", def: 3, min: 1, max: 12, paso: 1, unidad: " px", t: "Alto de la zona que la hace bajar", p: "sensor borde" },

        { id: "barra.abrirAlPasar", s: "barra", g: "Paneles", tipo: "interruptor", def: true, t: "Abrir al pasar el cursor", a: "Hora, campanita y píldora de estado.", p: "hover" },
        { id: "barra.esperaAbrir", s: "barra", g: "Paneles", tipo: "deslizador", def: 60, min: 0, max: 500, paso: 10, unidad: " ms", t: "Espera para abrir", p: "tiempo retardo hover" },
        { id: "barra.esperaCerrar", s: "barra", g: "Paneles", tipo: "deslizador", def: 150, min: 0, max: 1000, paso: 10, unidad: " ms", t: "Espera para cerrar", p: "tiempo retardo hover" },

        // ---------- Energía: tiempos (el resto lo pinta SeccionEnergia.qml) ----------
        { id: "energia.perfil", s: "energia", tipo: "libre", t: "Modo de energía", p: "ahorro equilibrado rendimiento perfil" },
        { id: "energia.limite", s: "energia", tipo: "libre", t: "Límite de carga de la batería", p: "80 salud bateria upower" },
        { id: "energia.cafeina", s: "energia", tipo: "libre", t: "Mantener despierto", p: "cafeina suspender" },
        { id: "energia.bloquearMin", s: "energia", g: "Inactividad", tipo: "deslizador", def: 10, min: 0, max: 120, paso: 1, unidad: " min", cero: "Nunca",
          t: "Bloquear tras", a: "Sin usar el equipo y sin que nada se reproduzca.", p: "bloqueo inactividad tiempo pantalla" },
        { id: "energia.atenuarSeg", s: "energia", g: "Inactividad", tipo: "deslizador", def: 30, min: 0, max: 120, paso: 5, unidad: " s", cero: "No",
          t: "Oscurecer antes de bloquear", a: "Cualquier tecla o movimiento lo cancela.", p: "atenuar aviso" },
        { id: "energia.apagarSeg", s: "energia", g: "Inactividad", tipo: "deslizador", def: 30, min: 0, max: 600, paso: 10, unidad: " s", cero: "Nunca",
          t: "Apagar la pantalla tras bloquear", p: "monitor dpms" },
        { id: "energia.suspenderMin", s: "energia", g: "Inactividad", tipo: "deslizador", def: 30, min: 0, max: 240, paso: 5, unidad: " min", cero: "Nunca",
          t: "Suspender con batería tras", a: "Enchufado no se suspende solo.", p: "dormir reposo" },

        // ---------- Pantalla (la pinta SeccionPantalla.qml) ----------
        { id: "pantalla.uso", s: "pantalla", tipo: "libre", t: "Uso de los monitores", p: "extender reflejar espejo duplicar proyector" },
        { id: "pantalla.orden", s: "pantalla", tipo: "libre", t: "Ordenar monitores", p: "arrastrar posicion izquierda derecha arriba externo hdmi displayport usb" },
        { id: "pantalla.monitores", s: "pantalla", tipo: "libre", t: "Resolución, frecuencia y escala", p: "monitor salida orientacion rotacion girar hz vrr hdmi principal activar desactivar" },
        { id: "pantalla.brillo", s: "pantalla", tipo: "libre", t: "Brillo", p: "luz pantalla" },
        { id: "pantalla.luz", s: "pantalla", tipo: "libre", t: "Luz nocturna", p: "calidez noche ubicacion sol wlsunset" },

        // ---------- Red y Bluetooth (la pinta SeccionRed.qml) ----------
        { id: "red.wifi", s: "red", tipo: "libre", t: "Wi-Fi", p: "redes conectar contraseña" },
        { id: "red.actual", s: "red", tipo: "libre", t: "Conexión activa", p: "ip dns puerta enlace" },
        { id: "red.guardadas", s: "red", tipo: "libre", t: "Redes guardadas", p: "olvidar conectar sola autoconectar" },
        { id: "red.oculta", s: "red", tipo: "libre", t: "Conectar a una red oculta", p: "wifi ssid" },
        { id: "red.avanzado", s: "red", tipo: "libre", t: "VPN, IP fija y proxy", p: "avanzado editor conexiones" },
        { id: "bt.activo", s: "red", tipo: "libre", t: "Bluetooth", p: "emparejar visible" },
        { id: "bt.dispositivos", s: "red", tipo: "libre", t: "Dispositivos Bluetooth", p: "audifonos confianza olvidar bateria" },

        // ---------- Sonido (la pinta SeccionSonido.qml; aquí, para el buscador) ----------
        { id: "sonido.volSalida", s: "sonido", tipo: "libre", t: "Volumen de salida", p: "altavoces audifonos parlantes" },
        { id: "sonido.apps", s: "sonido", tipo: "libre", t: "Volumen por aplicación", p: "app firefox mezclador" },
        { id: "sonido.salida", s: "sonido", tipo: "libre", t: "Dispositivo de salida", p: "altavoces audifonos parlantes bluetooth hdmi" },
        { id: "sonido.volEntrada", s: "sonido", tipo: "libre", t: "Volumen del micrófono", p: "entrada mic" },
        { id: "sonido.entrada", s: "sonido", tipo: "libre", t: "Dispositivo de entrada", p: "microfono mic" }
    ]
}
