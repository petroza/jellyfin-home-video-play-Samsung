/*
 * Vyrovnání hlasitosti pro Jellyfin na Samsung TV (Tizen).
 *
 * Během přehrávání filmu:
 *   CH ▲ (kanál nahoru)  = další režim:  Vypnuto → Vyrovnat hlasitost → Noční režim → Vypnuto
 *   CH ▼ (kanál dolů)    = vypnout
 * Zvolený režim si aplikace pamatuje a použije ho i u dalších filmů.
 *
 * Jak to funguje: zvuk videa prochází Web Audio kompresorem (ztiší výbuchy a hudbu,
 * zesílí tiché dialogy). Ve stavu "Vypnuto" se zvuku vůbec nedotýká.
 * Pojistka: když by po zapnutí bylo ticho, samo se vrátí na původní zvuk.
 *
 * Psáno v ES5 kvůli staršímu prohlížeči v TV (Tizen 5.0).
 */
(function () {
    'use strict';

    var MODES = [
        { name: 'Vyrovnání vypnuto', icon: '🔈' },
        { name: 'Vyrovnat hlasitost', icon: '🔊', thr: -28, knee: 10, ratio: 4, att: 0.01, rel: 0.3, gain: 5 },
        { name: 'Noční režim', icon: '🌙', thr: -40, knee: 6, ratio: 12, att: 0.003, rel: 0.25, gain: 11 }
    ];
    var STORE = 'jfVyrovnaniRezim';
    var KEYS_UP = { ChannelUp: 1, 427: 1 };
    var KEYS_DOWN = { ChannelDown: 1, 428: 1 };

    var mode = 0;
    try { mode = parseInt(localStorage.getItem(STORE) || '0', 10) || 0; } catch (e) { mode = 0; }
    if (mode < 0 || mode >= MODES.length) { mode = 0; }

    var ctx = null;
    var graphs = [];          // [{ video, src, comp, gain, analyser }]
    var broken = [];          // videa, kde vyrovnání nejde
    var toastEl = null;
    var toastTimer = null;

    function log() {
        try { console.log.apply(console, ['[vyrovnani]'].concat([].slice.call(arguments))); } catch (e) { /* nic */ }
    }

    function onVideoPage() {
        return location.hash.indexOf('/video') !== -1;
    }

    function getVideo() {
        return document.querySelector('video.htmlvideoplayer') || document.querySelector('video');
    }

    function findGraph(v) {
        for (var i = 0; i < graphs.length; i++) { if (graphs[i].video === v) { return graphs[i]; } }
        return null;
    }

    function toast(text) {
        if (!toastEl) {
            toastEl = document.createElement('div');
            toastEl.style.cssText = 'position:fixed;top:6vh;left:50%;transform:translateX(-50%);z-index:2147483647;' +
                'background:rgba(0,0,0,.78);color:#fff;font:600 2.4vw/1.3 sans-serif;padding:1.2vw 2.4vw;' +
                'border-radius:1vw;pointer-events:none;transition:opacity .4s;opacity:0;white-space:nowrap';
            document.body.appendChild(toastEl);
        }
        toastEl.textContent = text;
        toastEl.style.opacity = '1';
        clearTimeout(toastTimer);
        toastTimer = setTimeout(function () { toastEl.style.opacity = '0'; }, 2200);
    }

    function crossOriginTainted(v) {
        // Cizí původ bez crossOrigin = Web Audio by dalo ticho -> do takového videa nesahat.
        try {
            var src = v.currentSrc || v.src || '';
            if (!src || src.indexOf('blob:') === 0) { return false; }
            var a = document.createElement('a');
            a.href = src;
            var same = (a.protocol + '//' + a.host) === (location.protocol + '//' + location.host);
            return !same && !v.crossOrigin;
        } catch (e) { return true; }
    }

    function ensureGraph(v) {
        var g = findGraph(v);
        if (g) { return g; }
        if (broken.indexOf(v) !== -1 || crossOriginTainted(v)) { return null; }
        var AC = window.AudioContext || window.webkitAudioContext;
        if (!AC) { return null; }
        try {
            ctx = ctx || new AC();
            g = { video: v };
            g.src = ctx.createMediaElementSource(v);
            g.comp = ctx.createDynamicsCompressor();
            g.gain = ctx.createGain();
            g.analyser = ctx.createAnalyser();
            g.analyser.fftSize = 2048;
            graphs.push(g);
            return g;
        } catch (e) {
            log('nelze vytvořit', e);
            broken.push(v);
            return null;
        }
    }

    function route(g, m) {
        try { g.src.disconnect(); } catch (e) { /* nic */ }
        try { g.comp.disconnect(); } catch (e) { /* nic */ }
        try { g.gain.disconnect(); } catch (e) { /* nic */ }
        if (!m.ratio) {
            g.src.connect(ctx.destination);             // vypnuto = čistý průchod
            g.src.connect(g.analyser);
            return;
        }
        var now = ctx.currentTime;
        g.comp.threshold.setValueAtTime(m.thr, now);
        g.comp.knee.setValueAtTime(m.knee, now);
        g.comp.ratio.setValueAtTime(m.ratio, now);
        g.comp.attack.setValueAtTime(m.att, now);
        g.comp.release.setValueAtTime(m.rel, now);
        g.gain.gain.setValueAtTime(Math.pow(10, m.gain / 20), now);
        g.src.connect(g.comp);
        g.comp.connect(g.gain);
        g.gain.connect(ctx.destination);
        g.gain.connect(g.analyser);
    }

    function level(g) {
        var buf = new Float32Array(g.analyser.fftSize);
        if (g.analyser.getFloatTimeDomainData) {
            g.analyser.getFloatTimeDomainData(buf);
        } else {
            var b = new Uint8Array(g.analyser.fftSize);
            g.analyser.getByteTimeDomainData(b);
            for (var j = 0; j < b.length; j++) { buf[j] = (b[j] - 128) / 128; }
        }
        var s = 0;
        for (var i = 0; i < buf.length; i++) { s += buf[i] * buf[i]; }
        return Math.sqrt(s / buf.length);
    }

    function safetyCheck(g) {
        // 3 s po zapnutí: hraje video, není ztlumené, a přesto naprosté ticho -> vrátit původní zvuk.
        var samples = 0, loud = 0;
        var timer = setInterval(function () {
            var v = g.video;
            if (v.paused || v.muted || v.volume === 0) { return; }
            samples++;
            if (level(g) > 0.0005) { loud++; }
            if (samples >= 12) {
                clearInterval(timer);
                if (loud === 0) {
                    log('ticho -> vracím průchod');
                    route(g, MODES[0]);
                    broken.push(v);
                    toast('Vyrovnání tady nejde – zvuk vrácen');
                }
            }
        }, 250);
    }

    function withRunningCtx(cb) {
        // Zvuk smí jít přes Web Audio jen když AudioContext opravdu běží (jinak by bylo ticho).
        var AC = window.AudioContext || window.webkitAudioContext;
        if (!AC) { cb(false); return; }
        try { ctx = ctx || new AC(); } catch (e) { cb(false); return; }
        if (ctx.state === 'running') { cb(true); return; }
        var done = false;
        var finish = function () { if (!done) { done = true; cb(ctx.state === 'running'); } };
        try {
            var p = ctx.resume && ctx.resume();
            if (p && p.then) { p.then(finish, finish); } else { finish(); }
        } catch (e) { finish(); }
        setTimeout(finish, 600);
    }

    function apply(showToast) {
        var v = getVideo();
        var m = MODES[mode];
        if (!v) { if (showToast) { toast(m.icon + ' ' + m.name); } return; }
        var g = findGraph(v);
        if (!g && !m.ratio) { if (showToast) { toast(m.icon + ' ' + m.name); } return; }   // vypnuto: zvuku se nedotýkat
        withRunningCtx(function (running) {
            if (!running) {
                if (!g) { toast(m.icon + ' ' + m.name + ' – zapněte CH ▲'); return; }  // bez stisku klávesy nic neměnit
            }
            g = g || ensureGraph(v);
            if (!g) { if (showToast) { toast('Vyrovnání u tohoto videa nejde'); } return; }
            route(g, m);
            if (m.ratio) { safetyCheck(g); }
            if (showToast) { toast(m.icon + ' ' + m.name); }
            log('režim', m.name);
        });
    }

    // Hlídač: když se AudioContext uspí (aplikace na pozadí apod.), probudit ho, aby film neztichl.
    setInterval(function () {
        if (ctx && graphs.length && ctx.state !== 'running' && ctx.resume) {
            try { ctx.resume(); } catch (e) { /* nic */ }
        }
    }, 2000);
    document.addEventListener('visibilitychange', function () {
        if (!document.hidden && ctx && ctx.resume) { try { ctx.resume(); } catch (e) { /* nic */ } }
    });

    function setMode(n) {
        mode = (n + MODES.length) % MODES.length;
        try { localStorage.setItem(STORE, String(mode)); } catch (e) { /* nic */ }
        apply(true);
    }

    function onKey(e) {
        if (!onVideoPage()) { return; }
        var k = e.key || e.keyIdentifier;
        var up = KEYS_UP[k] || KEYS_UP[e.keyCode];
        var down = KEYS_DOWN[k] || KEYS_DOWN[e.keyCode];
        if (!up && !down) { return; }
        // Jellyfin by jinak na kanál ▲/▼ přeskočil na další/předchozí položku.
        e.preventDefault();
        e.stopImmediatePropagation();
        if (e.type !== 'keydown') { return; }
        setMode(up ? mode + 1 : 0);
    }

    window.addEventListener('keydown', onKey, true);
    window.addEventListener('keyup', onKey, true);

    // Nový film: zapamatovaný režim použít automaticky.
    document.addEventListener('playing', function (e) {
        if (e.target && e.target.tagName === 'VIDEO' && MODES[mode].ratio && !findGraph(e.target)) {
            apply(true);
        }
    }, true);

    window.addEventListener('load', function () {
        try {
            if (window.tizen && tizen.tvinputdevice) {
                tizen.tvinputdevice.registerKey('ChannelUp');
                tizen.tvinputdevice.registerKey('ChannelDown');
            }
        } catch (e) { log('registerKey', e); }
    });

    window.jfVyrovnani = { setMode: setMode, getMode: function () { return mode; }, level: function () {
        var g = findGraph(getVideo()); return g ? level(g) : null;
    }, reduction: function () {
        var g = findGraph(getVideo()); if (!g) { return null; }
        var r = g.comp.reduction; return typeof r === 'number' ? r : (r && r.value);
    } };
    log('připraveno, režim', MODES[mode].name);
})();
