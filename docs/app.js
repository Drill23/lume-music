/* Lume Music — site. Sem bibliotecas. */
(() => {
  'use strict';
  const d = document;
  const root = d.documentElement;
  const mq = (q) => (window.matchMedia ? window.matchMedia(q).matches : false);
  const reduce = mq('(prefers-reduced-motion: reduce)');
  const $$ = (s, c = d) => Array.from(c.querySelectorAll(s));

  /* ---------- 1. Detecção do aparelho ---------- */
  const ua = navigator.userAgent || '';
  const isAndroid = /Android/i.test(ua);
  const isIOS = /iPhone|iPad|iPod/i.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  const os = isAndroid ? 'android' : isIOS ? 'ios' : '';
  if (os) {
    root.dataset.os = os;
    $$('[data-os="' + os + '"]').forEach((el) => el.classList.add('is-rec'));
  }

  /* ---------- 2. Vídeos em loop, carregados sob demanda ---------- */
  const videos = $$('video.lv');
  const blocked = new Set();
  const inView = new Set();

  const tryPlay = (v) => {
    v.muted = true;
    const p = v.play();
    if (p && p.catch) p.then(() => blocked.delete(v)).catch(() => blocked.add(v));
  };
  const load = (v) => {
    if (!v.getAttribute('src') && v.dataset.src) {
      v.muted = true;
      v.setAttribute('muted', '');
      v.removeAttribute('controls');
      v.src = v.dataset.src;
    }
  };

  // Vídeos tocam sempre em loop (pedido do Adriano), inclusive com "Reduzir movimento";
  // nesse caso só os efeitos de movimento (parallax, aurora, inclinação) ficam desligados.
  if ('IntersectionObserver' in window) {
    const vio = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        const v = e.target;
        if (e.isIntersecting) { inView.add(v); load(v); tryPlay(v); }
        else { inView.delete(v); v.pause(); blocked.delete(v); }
      });
    }, { rootMargin: '300px 0px 300px 0px', threshold: 0.01 });
    videos.forEach((v) => vio.observe(v));

    // Se o navegador bloqueou o autoplay, tenta de novo no primeiro gesto.
    const kick = () => {
      inView.forEach((v) => { if (v.getAttribute('src') && v.paused) tryPlay(v); });
    };
    ['pointerdown', 'touchstart', 'keydown', 'wheel'].forEach((ev) =>
      window.addEventListener(ev, kick, { once: true, passive: true }));
    window.addEventListener('scroll', kick, { once: true, passive: true });

    d.addEventListener('visibilitychange', () => {
      if (d.hidden) videos.forEach((v) => v.pause());
      else inView.forEach((v) => { if (v.getAttribute('src')) tryPlay(v); });
    });
  }
  else videos.forEach((v) => { load(v); tryPlay(v); });

  /* ---------- 3. Revelação ao rolar ---------- */
  $$('[data-stagger]').forEach((g) => {
    $$('[data-reveal]', g).forEach((el, i) => { if (!el.style.getPropertyValue('--d')) el.style.setProperty('--d', i * 90 + 'ms'); });
  });
  const reveals = $$('[data-reveal]');
  const show = (el) => {
    el.classList.add('in');
    const fin = () => el.classList.add('done');
    el.addEventListener('transitionend', function h(ev) {
      if (ev.target === el && ev.propertyName === 'opacity') { el.removeEventListener('transitionend', h); fin(); }
    });
    setTimeout(fin, 2200);
  };
  if (reduce || !('IntersectionObserver' in window)) {
    reveals.forEach((el) => el.classList.add('in', 'done'));
  } else {
    const rio = new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting) { show(e.target); rio.unobserve(e.target); } });
    }, { threshold: 0.12, rootMargin: '0px 0px -6% 0px' });
    reveals.forEach((el) => rio.observe(el));
  }

  /* ---------- 4. Brilho especular que segue o mouse ---------- */
  d.addEventListener('pointermove', (e) => {
    const t = e.target.closest && e.target.closest('[data-spec]');
    if (!t) return;
    const r = t.getBoundingClientRect();
    t.style.setProperty('--mx', (e.clientX - r.left) + 'px');
    t.style.setProperty('--my', (e.clientY - r.top) + 'px');
  }, { passive: true });

  /* ---------- 5. Barra, parallax e inclinação 3D ---------- */
  const nav = d.querySelector('.nav');
  const par = $$('[data-parallax]').map((el) => ({ el, k: parseFloat(el.dataset.parallax) || 0, y: 0 }));
  const visible = new Set();
  if (!reduce && 'IntersectionObserver' in window) {
    const pio = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        const item = par.find((p) => p.el === e.target);
        if (!item) return;
        if (e.isIntersecting) visible.add(item); else visible.delete(item);
      });
      schedule();
    }, { rootMargin: '120px 0px' });
    par.forEach((p) => pio.observe(p.el));
  }

  const stage = d.querySelector('[data-tilt]');
  const chips = stage ? $$('.chip', stage) : [];
  const tilt = { rx: 4, ry: -9, trx: 4, try_: -9, mx: 0, my: 0, cmx: 0, cmy: 0, on: false, run: false };
  let heroVisible = true;
  if (stage && 'IntersectionObserver' in window) {
    new IntersectionObserver((en) => { heroVisible = en[0].isIntersecting; if (heroVisible) schedule(); }).observe(stage);
  }

  let queued = false;
  function schedule() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(frame);
  }

  function frame() {
    queued = false;
    const sy = window.scrollY || 0;
    if (nav) nav.classList.toggle('is-scrolled', sy > 24);

    if (!reduce) {
      const vh = innerHeight;
      visible.forEach((p) => {
        const r = p.el.getBoundingClientRect();
        const c = r.top + r.height / 2 - p.y;
        const y = Math.max(-72, Math.min(72, -(c - vh / 2) * p.k));
        p.y = y;
        p.el.style.translate = '0 ' + y.toFixed(1) + 'px';
      });

      if (stage && heroVisible) {
        const prog = Math.min(1, sy / (vh * 0.9));
        const baseX = 4 + prog * 6, baseY = -9 + prog * 18;
        tilt.trx = baseX + (tilt.on ? -tilt.my * 8 : 0);
        tilt.try_ = baseY + (tilt.on ? tilt.mx * 12 : 0);
        tilt.rx += (tilt.trx - tilt.rx) * 0.085;
        tilt.ry += (tilt.try_ - tilt.ry) * 0.085;
        tilt.cmx += (tilt.mx - tilt.cmx) * 0.085;
        tilt.cmy += (tilt.my - tilt.cmy) * 0.085;
        stage.style.setProperty('--rx', tilt.rx.toFixed(2) + 'deg');
        stage.style.setProperty('--ry', tilt.ry.toFixed(2) + 'deg');
        chips.forEach((c, i) => {
          const k = (i + 1) * 6;
          c.style.translate = (tilt.cmx * k).toFixed(1) + 'px ' + (tilt.cmy * k * 0.6 - prog * (i + 1) * 14).toFixed(1) + 'px';
        });
        if (Math.abs(tilt.trx - tilt.rx) > 0.02 || Math.abs(tilt.try_ - tilt.ry) > 0.02 ||
            Math.abs(tilt.mx - tilt.cmx) > 0.002 || Math.abs(tilt.my - tilt.cmy) > 0.002) schedule();
      }
    }
  }

  window.addEventListener('scroll', schedule, { passive: true });
  window.addEventListener('resize', schedule, { passive: true });
  if (!reduce && mq('(hover: hover) and (pointer: fine)')) {
    window.addEventListener('pointermove', (e) => {
      if (e.pointerType === 'touch') return;
      tilt.on = true;
      tilt.mx = (e.clientX / innerWidth - 0.5) * 2;
      tilt.my = (e.clientY / innerHeight - 0.5) * 2;
      if (heroVisible) schedule();
    }, { passive: true });
    d.documentElement.addEventListener('pointerleave', () => { tilt.on = false; tilt.mx = 0; tilt.my = 0; schedule(); });
  }
  schedule();

  /* ---------- 6. Galeria horizontal ---------- */
  const gal = d.querySelector('.gallery');
  const arrows = $$('.arrow');
  if (gal && arrows.length) {
    const upd = () => {
      const max = gal.scrollWidth - gal.clientWidth - 2;
      arrows[0].disabled = gal.scrollLeft <= 2;
      arrows[1].disabled = gal.scrollLeft >= max;
    };
    arrows.forEach((b) => b.addEventListener('click', () => {
      const dir = Number(b.dataset.dir) || 1;
      gal.scrollBy({ left: dir * Math.max(280, gal.clientWidth * 0.6), behavior: reduce ? 'auto' : 'smooth' });
    }));
    gal.addEventListener('scroll', upd, { passive: true });
    window.addEventListener('resize', upd, { passive: true });
    gal.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
        e.preventDefault();
        gal.scrollBy({ left: (e.key === 'ArrowRight' ? 1 : -1) * 280, behavior: reduce ? 'auto' : 'smooth' });
      }
    });
    upd();
  }

  /* ---------- 7. Vitalício: compra pelo painel ---------- */
  const vitBuy = d.getElementById('vit-buy');
  if (vitBuy) {
    const FALLBACK_API = 'https://lume-music-painel.adriano-s-almeida.chatgpt.site';
    const CONFIG_URL = 'https://raw.githubusercontent.com/Drill23/lume-music/main/config/painel.json';
    const KEY_DEV = 'lume.web.device', KEY_ORD = 'lume.web.order', KEY_API = 'lume.web.api';
    const $ = (id) => d.getElementById(id);
    const msgBuy = $('vit-msg'), msgPix = $('pix-msg'), done = $('vit-done');
    const qrImg = $('pix-qr-img'), qrDyn = $('pix-qr-dyn'), note = $('pix-note');
    const btnCopy = $('pix-copy'), btnKey = $('pix-key'), btnPaid = $('pix-paid');
    const staticPayload = btnCopy.dataset.payload;
    const pixKey = btnKey.dataset.key;

    const store = {
      get(k) { try { return localStorage.getItem(k); } catch (_) { return null; } },
      set(k, v) { try { localStorage.setItem(k, v); } catch (_) {} },
      del(k) { try { localStorage.removeItem(k); } catch (_) {} }
    };
    const say = (el, text, err) => {
      if (!el) return;
      el.textContent = text || '';
      el.hidden = !text;
      el.classList.toggle('is-err', !!err);
    };

    /* aparelho "web-…" salvo no navegador */
    const deviceId = () => {
      let v = store.get(KEY_DEV);
      if (!v || !/^web-[0-9a-f]{16}$/.test(v)) {
        let hex = '';
        try {
          const a = new Uint8Array(8);
          crypto.getRandomValues(a);
          hex = Array.from(a, (b) => b.toString(16).padStart(2, '0')).join('');
        } catch (_) {
          for (let i = 0; i < 16; i++) hex += Math.floor(Math.random() * 16).toString(16);
        }
        v = 'web-' + hex;
        store.set(KEY_DEV, v);
      }
      return v;
    };

    /* rede com tempo limite e erros amigáveis */
    class NetErr extends Error { constructor(kind, status) { super(kind); this.kind = kind; this.status = status; } }
    const http = async (url, opts, ms = 12000) => {
      const ctl = 'AbortController' in window ? new AbortController() : null;
      const timer = ctl ? setTimeout(() => ctl.abort(), ms) : 0;
      let res;
      try { res = await fetch(url, Object.assign({ cache: 'no-store' }, opts, ctl ? { signal: ctl.signal } : {})); }
      catch (_) {
        /* Sem CORS na resposta (ex.: rota ainda não publicada, 404): se o servidor responde
           a uma chamada "opaca", ele está no ar e a compra pelo site ainda não existe. */
        let up = false;
        try { await fetch(url, { mode: 'no-cors', cache: 'no-store' }); up = true; } catch (_2) {}
        throw new NetErr(up ? 'soon' : 'network');
      }
      finally { clearTimeout(timer); }
      let data = null;
      try { data = await res.json(); } catch (_) { /* sem corpo JSON */ }
      if (!res.ok || !data || data.ok === false) {
        const code = data && data.error;
        throw new NetErr(res.status === 404 && code !== 'order_not_found' ? 'soon' : (code || 'http'), res.status);
      }
      return data;
    };
    const friendly = (e) => {
      switch (e && e.kind) {
        case 'soon': return 'Compra pelo site disponível em breve.';
        case 'rate_limited': return 'Muitas tentativas seguidas. Espere um pouco e tente de novo.';
        case 'purchase_disabled': return 'A compra pelo site está indisponível no momento. Tente mais tarde.';
        case 'network': return 'Não consegui falar com o servidor. Confira sua internet e tente de novo.';
        default: return 'Algo deu errado por aqui. Tente de novo em instantes.';
      }
    };

    /* endereço do painel (config no GitHub, com cache de 1 h) */
    let apiPromise = null;
    const getApi = () => apiPromise || (apiPromise = (async () => {
      try {
        const c = JSON.parse(store.get(KEY_API) || 'null');
        if (c && typeof c.v === 'string' && Date.now() - c.t < 3600e3) return c.v || FALLBACK_API;
      } catch (_) {}
      let v = '';
      try {
        const r = await fetch(CONFIG_URL, { cache: 'no-cache' });
        if (r.ok) { const j = await r.json(); if (j && typeof j.apiBase === 'string') v = j.apiBase.trim().replace(/\/+$/, ''); }
      } catch (_) {}
      if (!/^https:\/\//.test(v)) v = '';
      store.set(KEY_API, JSON.stringify({ v, t: Date.now() }));
      return v || FALLBACK_API;
    })());
    const post = async (path, body) => http((await getApi()) + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
    const getStatus = async (o) => http((await getApi()) + '/api/purchase/status?order=' + encodeURIComponent(o.orderId) + '&device=' + encodeURIComponent(o.device));

    /* pedido guardado */
    let order = null;
    try { order = JSON.parse(store.get(KEY_ORD) || 'null'); } catch (_) {}
    if (!order || !/^LM-[A-Z0-9]{4,12}$/.test(order.orderId || '')) order = null;
    const saveOrder = () => { if (order) store.set(KEY_ORD, JSON.stringify(order)); else store.del(KEY_ORD); };

    /* QR do Pix */
    const showQr = (payload, orderId) => {
      if (!payload) return;
      try {
        qrDyn.innerHTML = qrSvg(payload);
        qrDyn.firstChild.setAttribute('role', 'img');
        qrDyn.firstChild.setAttribute('aria-label', 'QR Code do Pix copia e cola do pedido ' + orderId);
        qrDyn.hidden = false; qrImg.hidden = true;
        btnCopy.dataset.payload = payload;
        note.textContent = 'Pedido ' + orderId + ' · R$ 10,00. Abra o app do seu banco, escolha Pix e leia o QR Code ou use o copia e cola. Depois de pagar, toque em “Já paguei”.';
      } catch (_) { /* mantém o QR estático */ }
    };

    /* copiar */
    const copy = async (text) => {
      try { await navigator.clipboard.writeText(text); return true; } catch (_) {}
      try {
        const t = d.createElement('textarea');
        t.value = text; t.setAttribute('readonly', ''); t.style.cssText = 'position:fixed;left:-9999px;top:0';
        d.body.appendChild(t); t.select(); t.setSelectionRange(0, text.length);
        const ok = d.execCommand('copy'); t.remove(); return ok;
      } catch (_) { return false; }
    };
    const copyBtn = (btn, get, okText) => btn.addEventListener('click', async () => {
      const label = btn.dataset.label || (btn.dataset.label = btn.textContent);
      const ok = await copy(get());
      btn.textContent = ok ? okText : 'Não deu para copiar';
      clearTimeout(btn._t);
      btn._t = setTimeout(() => { btn.textContent = label; }, 1800);
    });
    copyBtn(btnCopy, () => btnCopy.dataset.payload, 'Copiado!');
    copyBtn(btnKey, () => pixKey, 'Chave copiada!');
    copyBtn($('vit-copycode'), () => $('vit-code').textContent, 'Código copiado!');

    /* acompanhar o pagamento (a cada 5 s, só com a aba visível) */
    let pollTimer = 0, polling = false;
    const stopPoll = () => { clearTimeout(pollTimer); pollTimer = 0; polling = false; };
    const showPaid = (code) => {
      stopPoll();
      $('vit-code').textContent = code;
      done.hidden = false;
      say(msgBuy, ''); say(msgPix, '');
      vitBuy.disabled = false;
      try { done.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'center' }); } catch (_) {}
    };
    const check = async () => {
      if (!order) return;
      try {
        const r = await getStatus(order);
        if (r.status === 'paid' && r.code) { order.code = r.code; order.status = 'paid'; saveOrder(); showPaid(r.code); return; }
        if (r.status === 'canceled') {
          stopPoll(); order = null; saveOrder();
          qrDyn.hidden = true; qrImg.hidden = false; btnCopy.dataset.payload = staticPayload;
          say(msgPix, 'Pedido cancelado. Se quiser, é só comprar de novo.', true);
          return;
        }
        if (r.status === 'review' && order.status !== 'review') { order.status = 'review'; saveOrder(); }
        if (order.status === 'review') say(msgPix, 'Recebemos seu aviso. Seu código vitalício aparece aqui assim que o pagamento for confirmado.');
        if (r.status === 'underpaid') say(msgPix, (r && r.message) || 'O valor recebido é menor que R$ 10,00. Fale com o suporte.', true);
      } catch (_) { /* tenta de novo no próximo ciclo; nada trava */ }
      schedulePoll();
    };
    const schedulePoll = () => {
      clearTimeout(pollTimer);
      if (!order || order.status === 'paid' || d.hidden) { polling = false; return; }
      polling = true;
      pollTimer = setTimeout(check, Math.max(3, Math.min(30, order.poll || 5)) * 1000);
    };
    d.addEventListener('visibilitychange', () => { if (!d.hidden && order && order.status !== 'paid' && !polling) check(); });

    /* modo manual (chave Pix + Já paguei) x automático (Pix do Mercado Pago confirmado sozinho) */
    const setManual = (manual) => {
      if (btnPaid) btnPaid.hidden = !manual;
      const k = $('pix-key'); if (k) k.hidden = !manual;
    };

    /* criar pedido */
    const createOrder = async (method) => {
      const r = await post('/api/purchase/create', { device: deviceId(), platform: 'web', app: 'site', method });
      order = { orderId: r.orderId, device: deviceId(), status: r.status || 'pending', poll: r.pollSeconds || 5, copia: r.pix && r.pix.copiaECola || '', checkoutUrl: r.checkoutUrl || null, automatic: !!(r.pix && r.pix.automatic) };
      setManual(!order.automatic);
      saveOrder();
      showQr(order.copia, order.orderId);
      return r;
    };

    vitBuy.addEventListener('click', async () => {
      const label = vitBuy.textContent;
      vitBuy.disabled = true; vitBuy.textContent = 'Preparando…';
      say(msgBuy, '');
      try {
        const r = await createOrder('pix');
        if (r.checkoutUrl && /^https:\/\//.test(r.checkoutUrl)) {
          say(msgBuy, 'Abrindo o pagamento seguro…');
          window.location.href = r.checkoutUrl;
          setTimeout(() => { vitBuy.disabled = false; vitBuy.textContent = label; }, 4000);
          return;
        }
        say(msgBuy, order.automatic
          ? 'Pix de R$ 10,00 gerado (pedido ' + r.orderId + '). Pague pelo QR ou pelo copia e cola abaixo: assim que o Pix cair, seu código vitalício aparece aqui sozinho.'
          : 'Pedido ' + r.orderId + ' criado. Pague pela chave Pix logo abaixo e toque em “Já paguei”.');
        schedulePoll();
        $('pixbox').scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'center' });
      } catch (e) { say(msgBuy, friendly(e), true); }
      vitBuy.disabled = false; vitBuy.textContent = label;
    });

    btnPaid.addEventListener('click', async () => {
      btnPaid.disabled = true;
      say(msgPix, '');
      try {
        if (!order) await createOrder('pix');
        await post('/api/purchase/claim', { order: order.orderId, device: order.device });
        order.status = 'review'; saveOrder();
        say(msgPix, 'Recebemos seu aviso. Seu código vitalício aparece aqui assim que o pagamento for confirmado.');
        stopPoll(); check();
      } catch (e) { say(msgPix, e && e.kind === 'soon' ? 'Aviso de pagamento pelo site disponível em breve. Se já pagou, fale com o suporte.' : friendly(e), true); }
      btnPaid.disabled = false;
    });

    /* retomar pedido após recarregar ou voltar do checkout */
    if (order) {
      if (order.code) showPaid(order.code);
      else {
        showQr(order.copia, order.orderId);
        if (order.status === 'review') say(msgPix, 'Recebemos seu aviso. Seu código vitalício aparece aqui assim que o pagamento for confirmado.');
        check();
      }
    }
  }

  /* ---------- 8. QR Code (modo byte, nível M) ----------
     Encoder mínimo baseado no algoritmo do "QR Code generator library" de Project Nayuki
     (https://www.nayuki.io/page/qr-code-generator-library), licença MIT:
     Copyright (c) Project Nayuki. Permissão concedida, gratuitamente, para usar, copiar,
     modificar e distribuir este software, desde que este aviso seja mantido. O SOFTWARE É
     FORNECIDO "COMO ESTÁ", SEM GARANTIAS DE QUALQUER TIPO. */
  function qrSvg(text) {
    const m = qrEncode(text), n = m.length, b = 2;
    let p = '';
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) if (m[y][x]) p += 'M' + (x + b) + ' ' + (y + b) + 'h1v1h-1z';
    const sz = n + b * 2;
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + sz + ' ' + sz + '" shape-rendering="crispEdges"><rect width="' + sz + '" height="' + sz + '" fill="#fff"/><path d="' + p + '" fill="#07080B"/></svg>';
  }
  function qrEncode(text) {
    const ECC = [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28];
    const BLK = [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49];
    const bytes = Array.from(new TextEncoder().encode(text));
    const raw = (v) => {
      let r = (16 * v + 128) * v + 64;
      if (v >= 2) { const a = Math.floor(v / 7) + 2; r -= (25 * a - 10) * a - 55; if (v >= 7) r -= 36; }
      return r;
    };
    let ver = 1;
    for (;; ver++) {
      if (ver > 40) throw new Error('too long');
      const cap = Math.floor(raw(ver) / 8) - ECC[ver] * BLK[ver];
      if (4 + (ver < 10 ? 8 : 16) + 8 * bytes.length <= cap * 8) break;
    }
    const cap = Math.floor(raw(ver) / 8) - ECC[ver] * BLK[ver];
    const bits = [];
    const put = (val, len) => { for (let i = len - 1; i >= 0; i--) bits.push((val >>> i) & 1); };
    put(4, 4); put(bytes.length, ver < 10 ? 8 : 16); bytes.forEach((x) => put(x, 8));
    put(0, Math.min(4, cap * 8 - bits.length));
    while (bits.length % 8) bits.push(0);
    for (let pad = 0xEC; bits.length < cap * 8; pad ^= 0xEC ^ 0x11) put(pad, 8);
    const data = [];
    for (let i = 0; i < bits.length; i += 8) data.push(parseInt(bits.slice(i, i + 8).join(''), 2));

    /* Reed-Solomon */
    const mul = (x, y) => { let z = 0; for (let i = 7; i >= 0; i--) { z = (z << 1) ^ ((z >>> 7) * 0x11D); z ^= ((y >>> i) & 1) * x; } return z; };
    const rs = (dat, deg) => {
      const div = new Array(deg).fill(0); div[deg - 1] = 1;
      let root = 1;
      for (let i = 0; i < deg; i++) {
        for (let j = 0; j < deg; j++) { div[j] = mul(div[j], root); if (j + 1 < deg) div[j] ^= div[j + 1]; }
        root = mul(root, 2);
      }
      const res = new Array(deg).fill(0);
      dat.forEach((b) => { const f = b ^ res.shift(); res.push(0); div.forEach((c, i) => { res[i] ^= mul(c, f); }); });
      return res;
    };
    const nb = BLK[ver], el = ECC[ver], rc = Math.floor(raw(ver) / 8);
    const ns = nb - (rc % nb), sl = Math.floor(rc / nb);
    const blocks = [];
    for (let i = 0, k = 0; i < nb; i++) {
      const dat = data.slice(k, k + sl - el + (i < ns ? 0 : 1)); k += dat.length;
      const ecc = rs(dat, el);
      if (i < ns) dat.push(0);
      blocks.push(dat.concat(ecc));
    }
    const words = [];
    for (let i = 0; i < blocks[0].length; i++) blocks.forEach((bl, j) => { if (i !== sl - el || j >= ns) words.push(bl[i]); });

    /* matriz */
    const size = ver * 4 + 17;
    const mod = Array.from({ length: size }, () => new Array(size).fill(false));
    const fn = Array.from({ length: size }, () => new Array(size).fill(false));
    const setF = (x, y, v) => { if (x >= 0 && x < size && y >= 0 && y < size) { mod[y][x] = v; fn[y][x] = true; } };
    for (let i = 0; i < size; i++) { setF(6, i, i % 2 === 0); setF(i, 6, i % 2 === 0); }
    [[3, 3], [size - 4, 3], [3, size - 4]].forEach(([cx, cy]) => {
      for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) { const t = Math.max(Math.abs(dx), Math.abs(dy)); setF(cx + dx, cy + dy, t !== 2 && t !== 4); }
    });
    if (ver > 1) {
      const na = Math.floor(ver / 7) + 2;
      const step = ver === 32 ? 26 : Math.ceil((ver * 4 + 4) / (na * 2 - 2)) * 2;
      const pos = [6];
      for (let ps = size - 7; pos.length < na; ps -= step) pos.splice(1, 0, ps);
      pos.forEach((cy, i) => pos.forEach((cx, j) => {
        if ((i === 0 && j === 0) || (i === 0 && j === na - 1) || (i === na - 1 && j === 0)) return;
        for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) setF(cx + dx, cy + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
      }));
    }
    const fmt = (mask) => {
      const dt = (0 << 3) | mask; let r = dt;
      for (let i = 0; i < 10; i++) r = (r << 1) ^ ((r >>> 9) * 0x537);
      const bt = ((dt << 10) | r) ^ 0x5412, g = (i) => ((bt >>> i) & 1) !== 0;
      for (let i = 0; i <= 5; i++) setF(8, i, g(i));
      setF(8, 7, g(6)); setF(8, 8, g(7)); setF(7, 8, g(8));
      for (let i = 9; i < 15; i++) setF(14 - i, 8, g(i));
      for (let i = 0; i < 8; i++) setF(size - 1 - i, 8, g(i));
      for (let i = 8; i < 15; i++) setF(8, size - 15 + i, g(i));
      setF(8, size - 8, true);
    };
    fmt(0);
    if (ver >= 7) {
      let r = ver; for (let i = 0; i < 12; i++) r = (r << 1) ^ ((r >>> 11) * 0x1F25);
      const bt = (ver << 12) | r;
      for (let i = 0; i < 18; i++) { const c = ((bt >>> i) & 1) !== 0, a = size - 11 + (i % 3), b2 = Math.floor(i / 3); setF(a, b2, c); setF(b2, a, c); }
    }
    for (let i = 0, right = size - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (let vert = 0; vert < size; vert++) for (let j = 0; j < 2; j++) {
        const x = right - j, y = ((right + 1) & 2) === 0 ? size - 1 - vert : vert;
        if (!fn[y][x] && i < words.length * 8) { mod[y][x] = ((words[i >>> 3] >>> (7 - (i & 7))) & 1) !== 0; i++; }
      }
    }
    const inv = [
      (x, y) => (x + y) % 2 === 0, (x, y) => y % 2 === 0, (x) => x % 3 === 0, (x, y) => (x + y) % 3 === 0,
      (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0, (x, y) => (x * y) % 2 + (x * y) % 3 === 0,
      (x, y) => ((x * y) % 2 + (x * y) % 3) % 2 === 0, (x, y) => ((x + y) % 2 + (x * y) % 3) % 2 === 0
    ];
    const applyMask = (k) => { for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) if (!fn[y][x] && inv[k](x, y)) mod[y][x] = !mod[y][x]; };
    const penalty = () => {
      let pen = 0, dark = 0;
      const line = (get) => {
        for (let a = 0; a < size; a++) {
          let run = 1, str = '';
          for (let b = 0; b < size; b++) {
            const v = get(a, b); str += v ? '1' : '0'; if (v) dark++;
            if (b > 0 && v === get(a, b - 1)) { run++; if (run === 5) pen += 3; else if (run > 5) pen++; } else run = 1;
          }
          for (let i = 0; i + 11 <= size; i++) { const w = str.substr(i, 11); if (w === '10111010000' || w === '00001011101') pen += 40; }
        }
      };
      line((y, x) => mod[y][x]); line((x, y) => mod[y][x]);
      dark /= 2;
      for (let y = 0; y < size - 1; y++) for (let x = 0; x < size - 1; x++) { const c = mod[y][x]; if (c === mod[y][x + 1] && c === mod[y + 1][x] && c === mod[y + 1][x + 1]) pen += 3; }
      pen += (Math.ceil(Math.abs(dark * 20 - size * size * 10) / (size * size)) - 1) * 10;
      return pen;
    };
    let best = 0, bestPen = Infinity;
    for (let k = 0; k < 8; k++) { fmt(k); applyMask(k); const pn = penalty(); if (pn < bestPen) { best = k; bestPen = pn; } applyMask(k); }
    fmt(best); applyMask(best);
    return mod;
  }
})();
