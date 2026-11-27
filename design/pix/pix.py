"""Gera payload Pix (BR Code estático) e QR em SVG no estilo dos sites Lume."""
import sys, qrcode

def tlv(i, v): return f"{i}{len(v):02d}{v}"

def crc16(s):
    crc = 0xFFFF
    for b in s.encode():
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else (crc << 1)
            crc &= 0xFFFF
    return f"{crc:04X}"

def payload(key, name="ADRIANO ALMEIDA", city="BRASIL", amount=None, txid="***"):
    p = tlv("00", "01") + tlv("26", tlv("00", "BR.GOV.BCB.PIX") + tlv("01", key)) + tlv("52", "0000") + tlv("53", "986")
    if amount: p += tlv("54", f"{amount:.2f}")
    p += tlv("58", "BR") + tlv("59", name[:25]) + tlv("60", city[:15]) + tlv("62", tlv("05", txid))
    p += "6304"
    return p + crc16(p)

def svg(data, out, dark="#07080B", module=10, border=2):
    q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, border=0); q.add_data(data); q.make(fit=True)
    m = q.get_matrix(); n = len(m); size = (n + 2 * border) * module
    rects = "".join(f'<rect x="{(x+border)*module}" y="{(y+border)*module}" width="{module}" height="{module}" rx="1.8" fill="{dark}"/>'
                    for y, row in enumerate(m) for x, v in enumerate(row) if v)
    open(out, "w").write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="{size}" height="{size}" shape-rendering="geometricPrecision">\n  <rect width="{size}" height="{size}" rx="18" fill="#FFFFFF"/>\n  {rects}\n</svg>\n')

if __name__ == "__main__":
    key, out = sys.argv[1], sys.argv[2]
    amount = float(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] else None
    p = payload(key, amount=amount); svg(p, out); print(p)
