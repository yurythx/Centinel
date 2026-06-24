# Centinel

Stack de infraestrutura unificada para ambientes homelab/VPS. Combina identidade centralizada, painel de controle visual, acesso público seguro via Cloudflare Tunnel e conectividade privada via Tailscale — tudo sem expor portas no servidor.

---

## Visão geral da arquitetura

```
Internet
    │
    ▼
Cloudflare Edge  ←── Zero Trust Access (políticas de acesso)
    │
    ▼
cloudflared (tunnel)          ← sem porta exposta no servidor
    │
    ├── auth.seudominio.com.br  →  Keycloak:8080
    └── home.seudominio.com.br  →  Heimdall:80

Tailscale (canal privado separado)
    └── Proxmox / homelab  ──────────────────  VPS

Redes Docker internas:
    rede-db       → postgres + keycloak (banco isolado da internet)
    rede-servicos → keycloak + heimdall + cloudflared + tailscale
```

Todo o tráfego público passa pelo túnel do Cloudflare — o servidor nunca abre portas para a internet. O banco de dados fica em uma rede `internal: true`, inacessível por qualquer container que tenha saída para fora. A comunicação com o Proxmox ou outros nós da rede privada ocorre exclusivamente pelo Tailscale, sem depender de IP público.

---

## Serviços

### PostgreSQL
Banco de dados relacional usado como backend persistente do Keycloak. Substitui o banco H2 embutido (que é volátil e não suportado em produção). Os dados sobrevivem a reinicializações e atualizações de container via volume Docker.

### Keycloak
Identity Provider (IdP) open source. Centraliza autenticação e autorização para todos os serviços da stack. Com ele é possível configurar Single Sign-On (SSO), integração com provedores externos (Google, GitHub, LDAP) e controle de acesso baseado em roles.

Roda em modo `start` (produção), com `KC_PROXY: edge` porque o TLS é terminado pelo Cloudflare antes de chegar ao container.

### Heimdall
Painel visual para organizar e acessar todos os serviços em um único lugar. Funciona como página inicial da infraestrutura, com ícones e links para cada serviço.

### cloudflared
Cliente do Cloudflare Tunnel. Abre uma conexão de saída (outbound) com a borda do Cloudflare e expõe os serviços internos publicamente via hostnames configurados no dashboard — sem abrir portas no firewall do servidor.

### Tailscale
VPN mesh baseada em WireGuard. Cria uma rede privada entre o VPS e outros nós (Proxmox, máquinas locais) com autenticação mútua e criptografia ponta-a-ponta. Ideal para tráfego administrativo e acesso a serviços que não devem ser expostos publicamente.

---

## Pré-requisitos

- Servidor com Docker e Docker Compose instalados
- Domínio configurado no Cloudflare
- Conta no Cloudflare Zero Trust (plano gratuito disponível)
- Conta no Tailscale (plano gratuito disponível)

---

## Deploy passo a passo

### 1. Clonar o repositório

```bash
git clone https://github.com/seuusuario/centinel.git
cd centinel
```

### 2. Criar o arquivo de variáveis de ambiente

```bash
cp .env.example .env
```

Abra o `.env` e preencha todos os valores. Veja a seção [Obtendo os tokens](#obtendo-os-tokens) abaixo.

### 3. Criar o tunnel no Cloudflare

1. Acesse [dash.cloudflare.com](https://dash.cloudflare.com) → **Zero Trust** → **Networks** → **Tunnels**
2. Clique em **Create a tunnel** → escolha **Cloudflared**
3. Dê um nome (ex: `centinel-vps`) e salve
4. Copie o token exibido e cole em `CF_TUNNEL_TOKEN` no seu `.env`

### 4. Configurar os hostnames públicos no Cloudflare

Ainda na tela do tunnel, vá em **Public Hostnames** e adicione:

| Subdomain | Domain | Service |
|---|---|---|
| `auth` | `seudominio.com.br` | `http://keycloak:8080` |
| `home` | `seudominio.com.br` | `http://heimdall:80` |

> Os nomes `keycloak` e `heimdall` funcionam como hostnames porque todos os containers estão na mesma rede Docker `rede-servicos`.

### 5. Obter a Auth Key do Tailscale

1. Acesse [tailscale.com/admin/settings/keys](https://tailscale.com/admin/settings/keys)
2. Clique em **Generate auth key**
3. Marque **Reusable** e defina uma tag (ex: `tag:vps`)
4. Copie a chave e cole em `TS_AUTHKEY` no seu `.env`

### 6. Subir a stack

```bash
docker compose up -d
```

Aguarde o Postgres passar pelo healthcheck antes do Keycloak iniciar (feito automaticamente pelo `depends_on`).

### 7. Verificar os containers

```bash
docker compose ps
```

Todos devem estar com status `running`. Para ver os logs de um serviço específico:

```bash
docker compose logs -f keycloak
docker compose logs -f cloudflared
```

### 8. Acessar os serviços

| Serviço | URL |
|---|---|
| Keycloak (admin) | `https://auth.seudominio.com.br` |
| Heimdall | `https://home.seudominio.com.br` |

No primeiro acesso ao Keycloak, use as credenciais definidas em `KC_ADMIN_USER` e `KC_ADMIN_PASSWORD`.

---

## Obtendo os tokens

### Cloudflare Tunnel Token
```
Cloudflare Dashboard
  └── Zero Trust
        └── Networks
              └── Tunnels
                    └── [seu tunnel]
                          └── Configure → token
```

### Tailscale Auth Key
```
tailscale.com/admin/settings/keys
  └── Generate auth key
        └── Reusable: sim
        └── Tags: tag:vps (opcional)
```

---

## Comandos úteis

```bash
make up                   # sobe todos os serviços
make down                 # derruba todos os serviços
make logs                 # logs de todos em tempo real
make logs s=keycloak      # logs de um serviço específico
make ps                   # status dos containers
make restart s=keycloak   # reinicia um serviço
make update               # atualiza imagens e recria containers
make backup               # dump do Postgres com timestamp
```

---

## Segurança

- O arquivo `.env` está no `.gitignore` — nunca commite segredos
- O Keycloak roda com `KC_PROXY: edge` pois o TLS é encerrado no Cloudflare
- Nenhuma porta é exposta no host (`ports:` não está definido em nenhum serviço)
- Recomendado: configure **Cloudflare Access** no Zero Trust para proteger os hostnames com autenticação adicional (email OTP, Google, etc.)

---

## Adicionando novos serviços

1. Adicione o serviço no `docker-compose.yml` na rede `rede-servicos`
2. No dashboard do Cloudflare, adicione um novo hostname apontando para `http://nome-do-container:porta`
3. `docker compose up -d nome-do-servico`

Não é necessário reiniciar os outros serviços.
