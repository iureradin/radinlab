#!/usr/bin/env python3
# ============================================================================
# radinlab-discovery.py — Descoberta de rede do RadinLab
# ----------------------------------------------------------------------------
# Versionado em git@github.com:iureradin/radinlab.git (branch prod),
# em scripts/radinlab-discovery.py — mesmo padrão dos outros workflows.
#
# O N8N (CT 108), a cada 30 min, clona o repo e roda a versão NOVA. Se o
# clone falhar (GitHub fora, sem rede), roda a CÓPIA LOCAL em /opt do CT 108
# (versão possivelmente desatualizada) — a descoberta nunca deixa de rodar.
#
# Fluxo do script:
#   1. nmap ARP-scan do /24 -> hosts vivos AGORA (ip, mac, fabricante)
#   2. lê inventario.yaml do share //10.0.0.50/obsidian -> hosts CONHECIDOS
#   3. diff por MAC (IP como fallback) -> NOVOS
#   4. atualiza visto_em dos conhecidos e grava o YAML de volta
#   5. imprime JSON no stdout -> o N8N manda Telegram se houver novo
#
# Sem dependências de pip (parser YAML mínimo por regex; write-back textual
# que preserva o arquivo). Config por variáveis de ambiente:
#   SUBNET (10.0.0.0/24) SMB_HOST (10.0.0.50) SMB_SHARE (obsidian)
#   SMB_USER (Jarvis) SMB_PASS (obrigatória, injetada pela credencial do N8N)
#   YAML_PATH (pessoal/wiki/infraestrutura/inventario.yaml)
# ============================================================================
import os, re, sys, json, subprocess, tempfile, datetime

SUBNET    = os.environ.get("SUBNET", "10.0.0.0/24")
SMB_HOST  = os.environ.get("SMB_HOST", "10.0.0.50")
SMB_SHARE = os.environ.get("SMB_SHARE", "obsidian")
SMB_USER  = os.environ.get("SMB_USER", "Jarvis")
SMB_PASS  = os.environ.get("SMB_PASS", "")
# path do YAML DENTRO do share 'obsidian' (o vault pessoal é um subdir)
YAML_PATH = os.environ.get("YAML_PATH", "pessoal/wiki/infraestrutura/inventario.yaml")
# smbclient usa separador do estilo Windows
YAML_SMB  = YAML_PATH.replace("/", "\\")
TODAY     = datetime.date.today().isoformat()

def die(msg, code=1):
    print(json.dumps({"erro": msg}), flush=True)
    sys.exit(code)

# ---------------------------------------------------------------------------
# 1. ARP-scan via nmap -> [{ip, mac, vendor}]
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
            cur = {"ip": m.group(1), "mac": None, "vendor": None}
            hosts.append(cur)
        m = re.search(r"MAC Address: ([0-9A-Fa-f:]{17}) \((.*)\)", line)
        if m and cur is not None:
            cur["mac"] = m.group(1).upper()
            cur["vendor"] = m.group(2)
    # hosts sem MAC = a própria máquina (CT108); mantém pelo IP
    return hosts

# ---------------------------------------------------------------------------
# 2. smbclient helpers — baixa e sobe o YAML (arquivo-a-arquivo)
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
# 3. YAML mínimo: extrai os MACs/IPs conhecidos SEM pyyaml (regex nos campos),
#    e atualiza visto_em por reescrita textual preservando o arquivo.
# ---------------------------------------------------------------------------
def known_set(yaml_text):
    macs, ips = set(), set()
    for m in re.finditer(r'mac:\s*"?([0-9A-Fa-f:]{17})"?', yaml_text):
        macs.add(m.group(1).upper())
    for m in re.finditer(r'ip:\s*([\d.]+)', yaml_text):
        ips.add(m.group(1))
    return macs, ips

def bump_visto(yaml_text):
    # atualiza TODA ocorrência de visto_em: <data> para hoje (hosts conhecidos vistos agora)
    return re.sub(r'(visto_em:\s*)\d{4}-\d{2}-\d{2}', r'\g<1>' + TODAY, yaml_text)

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def main():
    if not SMB_PASS:
        die("SMB_PASS não definida no ambiente")
    vivos = scan()
    with tempfile.TemporaryDirectory() as td:
        path = pull_yaml(td)
        text = open(path, encoding="utf-8").read()
        macs, ips = known_set(text)

        novos = []
        for h in vivos:
            if h["mac"] is None:          # é o próprio CT108, ignora
                continue
            conhecido = h["mac"] in macs or h["ip"] in ips
            if not conhecido:
                novos.append(h)

        # atualiza visto_em dos conhecidos e grava de volta
        new_text = bump_visto(text)
        if new_text != text:
            open(path, "w", encoding="utf-8").write(new_text)
            push_yaml(td)

    print(json.dumps({
        "data": TODAY,
        "total_vivos": len([h for h in vivos if h["mac"]]),
        "total_conhecidos": len(macs),
        "novos": novos,
        "houve_novo": bool(novos),
    }, ensure_ascii=False), flush=True)

if __name__ == "__main__":
    main()
