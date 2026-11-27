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
})();
