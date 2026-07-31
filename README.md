# RadinLab

Infrastructure as Code para o homelab Proxmox.

## Estrutura

```
radinlab/
├── ansible/
│   ├── playbooks/           # Playbooks Ansible para Proxmox host
│   │   ├── proxmox-postinstall.yml
│   │   ├── proxmox-acme.yml
│   │   └── proxmox-ui.yml
│   └── inventory/
├── terraform/
│   └── immich/              # LXC container com Immich (foto/vídeo)
├── scripts/
│   ├── daily_snapshot.sh    # Snapshots automáticos
│   ├── setup-docker.sh      # Instalação Docker CE em LXC
│   └── setup-immich.sh      # Deploy Immich via Docker Compose
└── .github/workflows/
    ├── ci-cd.yml            # Ansible: lint + postinstall + ACME + UI
    └── terraform-immich.yml # Terraform: plan + apply + provision Immich
```

## Workflows

| Workflow | Trigger | Ação |
|----------|---------|------|
| `ci-cd.yml` | Push para prod/dev | Lint Ansible → Post-install → ACME → UI |
| `terraform-immich.yml` | Push/PR para prod/dev (paths: terraform/immich/**) | Plan → Apply → Provision Docker + Immich |

## Terraform - Immich

Provisiona um container LXC privilegiado no Proxmox com Docker + [Immich](https://immich.app/).

**Módulo utilizado:** [terraform-proxmox-lxc](https://github.com/iureradin/terraform-proxmox-lxc) (v1.0.0)

### Specs do Container

| Recurso | Valor |
|---------|-------|
| CPU | 4 cores |
| Memória | 8 GB |
| Disco root | 50 GB |
| Armazenamento fotos | 500 GB (/mnt/photos) |
| Rede | DHCP em vmbr0 |
| Features | nesting=1, keyctl=1 |

### Secrets necessários (GitHub)

| Secret | Descrição |
|--------|-----------|
| `PROXMOX_API_URL` | URL da API (ex: `https://10.0.0.70:8006`) |
| `PROXMOX_API_TOKEN` | Token no formato `user@realm!tokenid=secret` |
| `LXC_ROOT_PASSWORD` | Senha root do container |
| `IMMICH_DB_PASSWORD` | Senha do PostgreSQL do Immich |

### Variáveis necessárias (GitHub)

| Variable | Descrição |
|----------|-----------|
| `IMMICH_HOST` | IP do container Immich (para SSH de provisionamento) |

## Uso Local

```bash
cd terraform/immich
export TF_VAR_proxmox_api_token="terraform@pam!terraform=seu-token"
export TF_VAR_root_password="senha-segura"
terraform init
terraform plan
terraform apply
```

## Runner

Todos os workflows rodam em **self-hosted runner** no próprio Proxmox host.
