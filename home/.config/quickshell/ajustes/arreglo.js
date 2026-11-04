// Colocar monitores: dónde cae uno al soltarlo. Sin Quickshell, para poder probarlo aparte.
// rect = { n: nombre, x, y, w, h } en píxeles lógicos.
.pragma library

function solapan(a, b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}
function limitar(v, min, max) { return Math.max(min, Math.min(max, v)) }

// Posición válida más cercana para r: pegado a un lado de otro monitor (para que el cursor pueda pasar),
// sin solapar a nadie, y alineado con el borde del otro si está a menos de "iman" píxeles.
function colocar(r, otros, iman) {
    if (otros.length === 0) return { x: r.x, y: r.y }
    function alinear(v, a, b, tam) {   // a..b = extremo del otro; alinea inicio o final
        if (Math.abs(v - a) <= iman) return a
        if (Math.abs(v + tam - b) <= iman) return b - tam
        return v
    }
    var mejor = null
    otros.forEach(o => {
        // Siempre un tramo compartido cómodo: con 1 px el cursor apenas podría pasar de un monitor a otro
        var ty = Math.min(200, r.h, o.h), tx = Math.min(200, r.w, o.w)
        var y = limitar(alinear(r.y, o.y, o.y + o.h, r.h), o.y - r.h + ty, o.y + o.h - ty)
        var x = limitar(alinear(r.x, o.x, o.x + o.w, r.w), o.x - r.w + tx, o.x + o.w - tx)
        var candidatos = [
            { x: o.x - r.w, y: y }, { x: o.x + o.w, y: y },
            { x: x, y: o.y - r.h }, { x: x, y: o.y + o.h }
        ]
        candidatos.forEach(c => {
            var prueba = { x: c.x, y: c.y, w: r.w, h: r.h }
            if (otros.some(p => solapan(prueba, p))) return
            var d = (c.x - r.x) * (c.x - r.x) + (c.y - r.y) * (c.y - r.y)
            if (!mejor || d < mejor.d) mejor = { x: c.x, y: c.y, d: d }
        })
    })
    return mejor ? { x: mejor.x, y: mejor.y } : { x: r.x, y: r.y }
}

// Todos desde (0,0): las coordenadas quedan limpias en la config
function normalizar(rects) {
    var mx = Math.min.apply(null, rects.map(r => r.x))
    var my = Math.min.apply(null, rects.map(r => r.y))
    return rects.map(r => Object.assign({}, r, { x: r.x - mx, y: r.y - my }))
}
