#!/usr/bin/env python3
# ============================================================================
# radinlab-discovery.py — Descoberta de rede do RadinLab (v2, enriquecida)
# ----------------------------------------------------------------------------
# Roda DENTRO do CT 108 (n8n), disparado pelo N8N a cada 30 min.
#   1. nmap ARP-scan do /24 -> hosts vivos AGORA (ip, mac, fabricante OUI)
#   2. ENRIQUECE cada vivo:
#        - portas abertas (nmap --top-ports) -> serviços + palpite de TIPO
#        - reverse-DNS (resolver do Mikrotik) -> hostname amigável
#        - latência (fio vs wifi, pista fraca)
#        - flags: ssh/web/rdp/smb/iot
#   3. lê inventario.yaml do share //10.0.0.50/obsidian -> hosts CONHECIDOS
#   4. diff por MAC (IP como fallback) -> NOVOS (já com o enriquecimento)
#   5. atualiza visto_em dos conhecidos e grava o YAML de volta
#   6. imprime JSON no stdout: { novos:[...], vivos:[...], totais }
#
# O N8N lê o JSON do stdout: se `novos` não vazio -> manda Telegram
# (agora com tipo/hostname/portas, não só ip+mac).
#
# Sem dependências de pip. Pipeline inteiro ~7s no /24 (medido no CT108).
#
# Config por variáveis de ambiente (o N8N/credencial injeta SMB_PASS):
#   SUBNET        (default 10.0.0.0/24)
#   SMB_HOST      (default 10.0.0.50)
#   SMB_SHARE     (default obsidian)
#   SMB_USER      (default Jarvis)
#   SMB_PASS      (obrigatória — senha do share; NÃO hardcodar)
#   YAML_PATH     (default pessoal/wiki/infraestrutura/inventario.yaml)
#   TOP_PORTS     (default 25 — portas mais comuns a sondar por host)
#   ENRICH        (default 1 — 0 desliga o enriquecimento e volta ao scan simples)
# ============================================================================
import os, re, sys, json, socket, subprocess, tempfile, datetime

SUBNET    = os.environ.get("SUBNET", "10.0.0.0/24")
SMB_HOST  = os.environ.get("SMB_HOST", "10.0.0.50")
SMB_SHARE = os.environ.get("SMB_SHARE", "obsidian")
SMB_USER  = os.environ.get("SMB_USER", "Jarvis")
SMB_PASS  = os.environ.get("SMB_PASS", "")
YAML_PATH = os.environ.get("YAML_PATH", "pessoal/wiki/infraestrutura/inventario.yaml")
YAML_SMB  = YAML_PATH.replace("/", "\\")
TOP_PORTS = os.environ.get("TOP_PORTS", "25")
ENRICH    = os.environ.get("ENRICH", "1") != "0"
TODAY     = datetime.date.today().isoformat()

# porta -> rótulo de serviço legível
PORT_LABEL = {
    21: "ftp", 22: "ssh", 23: "telnet", 25: "smtp", 53: "dns",
    80: "http", 110: "pop3", 135: "msrpc", 139: "netbios", 143: "imap",
    443: "https", 445: "smb", 515: "printer", 548: "afp", 554: "rtsp",
    631: "ipp", 1883: "mqtt", 2283: "immich", 3000: "http-app", 3389: "rdp",
    5000: "http-app", 5080: "http-app", 5476: "http-app", 5678: "n8n",
    8008: "chromecast", 8009: "chromecast", 8080: "http-alt", 8096: "jellyfin",
    8123: "home-assistant", 8291: "winbox", 8443: "https-alt", 9000: "http-app",
    13378: "audiobookshelf", 32400: "plex", 5353: "mdns",
}

def die(msg, code=1):
    print(json.dumps({"erro": msg}, ensure_ascii=False), flush=True)
    sys.exit(code)

# ---------------------------------------------------------------------------
# 1. ARP-scan via nmap -> [{ip, mac, vendor, latency_ms}]
# ---------------------------------------------------------------------------
def scan():
    try:
        out = subprocess.run(
            ["nmap", "-sn", "-n", SUBNET],
            capture_output=True, text=True, timeout=180
        ).stdout
    except Exception as e:
        die(f"nmap falhou: {e}")
    hosts, cur = [], None
    for line in out.splitlines():
        m = re.search(r"Nmap scan report for ([\d.]+)", line)
        if m:
            cur = {"ip": m.group(1), "mac": None, "vendor": None,
                   "latency_ms": None, "hostname": None,
                   "portas": [], "servicos": [], "tipo": None, "link": None}
            hosts.append(cur)
        m = re.search(r"Host is up \(([\d.]+)s latency\)", line)
        if m and cur is not None:
            cur["latency_ms"] = round(float(m.group(1)) * 1000, 2)
        m = re.search(r"MAC Address: ([0-9A-Fa-f:]{17}) \((.*)\)", line)
        if m and cur is not None:
            cur["mac"] = m.group(1).upper()
            cur["vendor"] = m.group(2)
    return hosts

# ---------------------------------------------------------------------------
# 2. ENRIQUECIMENTO: portas + reverse-DNS + classificação por assinatura
# ---------------------------------------------------------------------------
def port_scan(ips):
    """Um único nmap --top-ports para TODOS os vivos; devolve {ip:[portas]}."""
    if not ips:
        return {}
    try:
        out = subprocess.run(
            ["nmap", "-n", "-Pn", "--top-ports", TOP_PORTS, "-T4",
             "--host-timeout", "15s", *ips],
            capture_output=True, text=True, timeout=240
        ).stdout
    except Exception:
        return {}
    res, cur = {}, None
    for line in out.splitlines():
        m = re.search(r"Nmap scan report for ([\d.]+)", line)
        if m:
            cur = m.group(1); res[cur] = []
        m = re.match(r"(\d+)/tcp\s+open", line)
        if m and cur:
            res[cur].append(int(m.group(1)))
    return res

def reverse_dns(ip):
    try:
        name = socket.gethostbyaddr(ip)[0]
        # ignora PTR genérico tipo 76.0.0.10.in-addr.arpa
        if name and not name.endswith(".in-addr.arpa"):
            return name
    except Exception:
        pass
    return None

def classify(vendor, portas):
    """Palpite de TIPO a partir da assinatura de portas + fabricante."""
    ps = set(portas)
    v = (vendor or "").lower()
    if {135, 445}.issubset(ps) or 3389 in ps:
        return "windows"
    if {21, 23}.issubset(ps) or (23 in ps and 80 in ps):
        return "iot"            # telnet+ftp/http = device embarcado (ESP/câmera)
    if 1883 in ps or 8123 in ps:
        return "iot-hub"
    if ps & {8096, 32400, 2283, 13378, 5678, 5080}:
        return "servico-midia"  # jellyfin/plex/immich/audiobookshelf/n8n/openobserve
    if 22 in ps and not (ps & {80, 443}):
        return "servidor-linux"
    if ps & {80, 443, 8080}:
        return "web/appliance"
    if "apple" in v:
        return "apple"
    if "amazon" in v:
        return "amazon-echo"
    if "samsung" in v:
        return "samsung"
    if not ps:
        return "quieto"         # vivo mas sem portas comuns (celular/privacidade)
    return "desconhecido"

def enrich(vivos):
    ips = [h["ip"] for h in vivos if h["mac"]]  # ignora o próprio CT108 (sem MAC)
    ports_by_ip = port_scan(ips)
    for h in vivos:
        p = ports_by_ip.get(h["ip"], [])
        h["portas"] = p
        h["servicos"] = [PORT_LABEL.get(x, str(x)) for x in p]
        h["hostname"] = reverse_dns(h["ip"])
        h["tipo"] = classify(h["vendor"], p)
        if h["latency_ms"] is not None:
            h["link"] = "fio" if h["latency_ms"] < 2 else "wifi"
    return vivos

# ---------------------------------------------------------------------------
# 3. smbclient helpers — baixa e sobe o YAML
# ---------------------------------------------------------------------------
def smb(cmd, localdir):
    base = ["smbclient", f"//{SMB_HOST}/{SMB_SHARE}", "-U", f"{SMB_USER}%{SMB_PASS}", "-c", cmd]
    return subprocess.run(base, capture_output=True, text=True, cwd=localdir, timeout=60)

def pull_yaml(localdir):
    r = smb(f'get "{YAML_SMB}" inv.yaml', localdir)
    if r.returncode != 0:
        die(f"smbclient get falhou: {r.stderr.strip() or r.stdout.strip()}")
    return os.path.join(localdir, "inv.yaml")

def push_yaml(localdir):
    r = smb(f'put inv.yaml "{YAML_SMB}"', localdir)
    if r.returncode != 0:
        die(f"smbclient put falhou: {r.stderr.strip() or r.stdout.strip()}")

# ---------------------------------------------------------------------------
# 4. YAML mínimo sem pyyaml
# ---------------------------------------------------------------------------
def known_set(yaml_text):
    macs, ips = set(), set()
    for m in re.finditer(r'mac:\s*"?([0-9A-Fa-f:]{17})"?', yaml_text):
        macs.add(m.group(1).upper())
    for m in re.finditer(r'ip:\s*([\d.]+)', yaml_text):
        ips.add(m.group(1))
    return macs, ips

def bump_visto(yaml_text):
    return re.sub(r'(visto_em:\s*)\d{4}-\d{2}-\d{2}', r'\g<1>' + TODAY, yaml_text)

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def main():
    if not SMB_PASS:
        die("SMB_PASS não definida no ambiente")
    vivos = scan()
    if ENRICH:
        vivos = enrich(vivos)

    with tempfile.TemporaryDirectory() as td:
        path = pull_yaml(td)
        text = open(path, encoding="utf-8").read()
        macs, ips = known_set(text)

        novos = []
        for h in vivos:
            if h["mac"] is None:          # é o próprio CT108, ignora
                continue
            if not (h["mac"] in macs or h["ip"] in ips):
                novos.append(h)

        new_text = bump_visto(text)
        if new_text != text:
            open(path, "w", encoding="utf-8").write(new_text)
            push_yaml(td)

    vivos_reais = [h for h in vivos if h["mac"]]
    print(json.dumps({
        "data": TODAY,
        "total_vivos": len(vivos_reais),
        "total_conhecidos": len(macs),
        "total_novos": len(novos),
        "houve_novo": bool(novos),
        "novos": novos,
        "vivos": vivos_reais,
    }, ensure_ascii=False), flush=True)

if __name__ == "__main__":
    main()
