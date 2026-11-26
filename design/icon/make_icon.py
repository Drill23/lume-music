# Lume Music 5.0 — ícone claro, translúcido, minimalista (disco de vidro com brilho prisma)
import numpy as np
from PIL import Image, ImageFilter
import sys, os

S = 2048  # render 2x, reduz para 1024
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
cx = cy = S / 2
dx, dy = xx - cx, yy - cy
r = np.sqrt(dx**2 + dy**2)
ang = np.arctan2(dy, dx)

PRISM = [(255, 196, 160), (255, 158, 196), (190, 160, 255), (140, 205, 255)]  # pêssego, rosa, lavanda, céu

def lerp(a, b, t): return a + (b - a) * t
def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)

def blob(img, x, y, rad, col, a):
    m = np.exp(-(((xx - x)**2 + (yy - y)**2) / (2 * rad**2)))[..., None] * a
    return img * (1 - m) + np.array(col, np.float32) * m

def prism_at(t):
    t = np.mod(t, 1.0) * len(PRISM)
    i = np.floor(t).astype(int); f = (t - i)[..., None]
    P = np.array(PRISM + [PRISM[0]], np.float32)
    return P[i] * (1 - f) + P[i + 1] * f

def render(mode):
    dark = mode == "dark"
    # fundo
    top = np.array([16, 17, 24] if dark else [252, 252, 254], np.float32)
    bot = np.array([6, 6, 10] if dark else [234, 236, 245], np.float32)
    t = (yy / S)[..., None]
    img = top * (1 - t) + bot * t
    # aurora pastel difusa
    k = 0.16 if dark else 0.55
    img = blob(img, S*0.22, S*0.20, S*0.26, PRISM[0], k)
    img = blob(img, S*0.82, S*0.26, S*0.24, PRISM[1], k*0.9)
    img = blob(img, S*0.20, S*0.86, S*0.26, PRISM[3], k)
    img = blob(img, S*0.86, S*0.84, S*0.24, PRISM[2], k*0.95)

    R = S * 0.335   # raio do disco
    disc = smooth(R + 1.5, R - 1.5, r)
    # sombra suave do disco (deslocada para baixo)
    sh = np.exp(-np.maximum(np.sqrt(dx**2 + (dy - S*0.035)**2) - R*0.92, 0)**2 / (2*(S*0.045)**2))
    sh = sh * (1 - disc)
    img = img * (1 - (sh * (0.55 if dark else 0.16))[..., None])

    # vidro: fundo "refratado" (borrado/clareado) dentro do disco
    base = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(S*0.03))
    glass = np.asarray(base).astype(np.float32)
    white = np.array([255, 255, 255], np.float32)
    frost = 0.10 if dark else 0.36
    glass = glass * (1 - frost) + white * frost
    if dark:
        glass = glass * 0.9 + np.array([40, 42, 58], np.float32) * 0.1
    # sulcos ultra-sutis
    rn = r / R
    grooves = (0.5 + 0.5*np.cos(rn * 2*np.pi * 46)) * smooth(0.40, 0.46, rn) * smooth(0.97, 0.90, rn)
    glass = glass * (1 - grooves[..., None] * (0.045 if not dark else 0.07))
    # reflexo anisotrópico em "gravata" (claro) girado ~ -35°
    a2 = ang + np.deg2rad(35)
    bow = (np.cos(a2)**2) ** 5 * smooth(0.30, 0.55, rn) * smooth(1.0, 0.85, rn)
    glass = glass + (white - glass) * (bow * (0.80 if not dark else 0.30))[..., None]
    # tom iridescente sutil acompanhando o ângulo
    iri = prism_at((ang / (2*np.pi)) + 0.15)
    glass = glass * (1 - 0.10) + iri * 0.10 * smooth(0.45, 1.0, rn)[..., None]

    # anel prisma ao redor do selo
    LR = R * 0.36
    ring = smooth(LR + S*0.012, LR + S*0.004, r) * smooth(LR - S*0.004, LR + S*0.002, r)
    ringcol = prism_at(ang / (2*np.pi) + 0.6)
    glass = glass * (1 - ring[..., None]) + ringcol * ring[..., None]
    # brilho suave do anel
    glow = np.exp(-((r - LR)**2) / (2*(S*0.018)**2)) * 0.35
    glass = glass * (1 - glow[..., None]) + ringcol * glow[..., None]
    # selo central: vidro mais claro
    lab = smooth(LR - S*0.002, LR - S*0.006, r)
    lg = smooth(-LR, LR, -dy)[..., None]
    labcol = (white * (0.97 if not dark else 0.24) + glass * (0.03 if not dark else 0.76)) * (0.96 + 0.04*lg)
    glass = glass * (1 - lab[..., None]) + labcol * lab[..., None]
    # furo central
    hole = smooth(S*0.020, S*0.016, r)
    holecol = np.array([214, 216, 226] if not dark else [8, 8, 12], np.float32)
    glass = glass * (1 - hole[..., None]) + holecol * hole[..., None]

    img = img * (1 - disc[..., None]) + glass * disc[..., None]

    # aro do vidro: luz em cima-esquerda, sombra fina embaixo
    rim = np.exp(-((r - R + S*0.004)**2) / (2*(S*0.0035)**2))
    light = (0.5 + 0.5*np.cos(ang + np.deg2rad(135)))
    img = img + (white - img) * (rim * (0.25 + 0.75*light) * (0.9 if not dark else 0.6))[..., None]
    img = img * (1 - (rim * (1-light) * (0.10 if not dark else 0.0))[..., None])
    # brilho interno curvo superior (lente)
    inner = np.exp(-((r - R*0.93)**2) / (2*(S*0.012)**2)) * smooth(0.2, 0.9, light)
    img = img + (white - img) * (inner * (0.28 if not dark else 0.18))[..., None]

    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS)

out = sys.argv[1]
light = render("light"); light.save(os.path.join(out, "icon.png"))
dark = render("dark"); dark.save(os.path.join(out, "icon-dark.png"))
light.convert("L").convert("RGB").save(os.path.join(out, "icon-tinted.png"))
print("ok")
