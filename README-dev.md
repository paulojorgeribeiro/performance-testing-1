# 🧱 Performance Test Stack – Guia DEV

## 📌 Objetivo
Ambiente **DEV (Development)** para execução de workflows GitHub de performance, com:
- **Runner self-hosted** (dentro de contentor, via Podman);
- **Vault DEV** (modo de desenvolvimento, token root);
- **Integração contínua** com o workflow `performance-test.yml`.

---

## 🚀 Passo 1 — Subir o ambiente DEV

Na VM de testes:

```bash
cd ~/stack-runner
./up.sh
```

✅ Verás algo como:
```
[OK] Containers prontos:
NAMES       STATUS      IMAGE
gh-runner   Up ...      docker.io/myoung34/github-runner:latest
vault-dev   Up ...      docker.io/hashicorp/vault:1.16
```

Ambos os contentores sobem automaticamente sempre que a VM é reiniciada (graças à política `--restart=always`).

---

## 🧩 Passo 2 — Confirmar saúde do ambiente

1. **Verificar containers:**
```bash
podman ps
```

2. **Verificar Vault DEV:**
```bash
curl -s http://127.0.0.1:18200/v1/sys/health | jq
```

Deve retornar algo semelhante a:
```json
{"initialized":true,"sealed":false,"standby":false,"version":"1.16.3"}
```

3. **Confirmar runner ativo no GitHub:**
- Vai a *Settings → Actions → Runners*  
- O runner deve aparecer como **Online** ✅

---

## 🔑 Passo 3 — Vault DEV automático

O `up.sh` já chama automaticamente o script `vault/seed-vault.sh`, que:
- Cria (se não existir) o **KV v2 mount** `devplatforms/`
- Semeia a secret necessária:
  ```
  devplatforms/data/performance-platform/application
  └── ptp_api_key = dummy-ptp-key-123
  ```

Para confirmar manualmente:
```bash
curl -s -H "X-Vault-Token: root"   http://127.0.0.1:18200/v1/devplatforms/data/performance-platform/application   | jq -r '.data.data.ptp_api_key'
```

✅ Deve devolver `dummy-ptp-key-123`.

---

## 🧪 Passo 4 — Executar um teste DEV

No GitHub → **Actions → Performance Test → Run workflow**

Escolhe:
- **ENVIRONMENT:** `dev`
- **LAC_ID:** `LAC.0001`
- **TEST_ID:** `TEST.0001`

O pipeline:
1. Valida o runner remoto via Podman;
2. Confirma o Vault DEV (`host.containers.internal:18200`);
3. Busca `ptp_api_key` da secret local;
4. Executa `run-test.sh` com o patch DEV;
5. Faz cleanup final.

---

## ⚙️ Passo 5 — Reinício da VM

Após desligar/ligar a VM:

1. Entra novamente:
   ```bash
   ssh pribeiro@dcvx-jmtapp-g1
   cd ~/stack-runner
   ./up.sh
   ```
2. Confirma que o runner e Vault estão “Up” (`podman ps`).
3. O script fará o *seed* automático da secret no Vault DEV.

Não é necessário reinstalar ou reconfigurar nada.  

---

## 🧭 Passo 6 — Passar a PROD

Quando for altura de usar o ambiente real:

1. No GitHub → *Settings → Secrets and variables → Actions*
2. Cria os seguintes **Secrets** e **Variables**:
   - `secrets.VAULT_PROD_ADDR`
   - `secrets.VAULT_PROD_TOKEN`
   - `secrets.DPT_REGISTRY_URL`
   - `vars.DPT_API_VERSION`
3. No workflow `performance-test.yml`, ao correr manualmente:
   - Define `ENVIRONMENT=prod`.

O pipeline muda automaticamente para:
- usar o Vault real;
- aplicar autenticação `app`;
- deixar de semear secrets locais.

---

## 🧰 Passo 7 — Utilitários úteis

- **Ver logs do Vault:**
  ```bash
  podman logs vault-dev --tail 30
  ```

- **Ver logs do runner:**
  ```bash
  podman logs gh-runner --tail 50
  ```

- **Remover e limpar stack (reset total):**
  ```bash
  cd ~/stack-runner
  ./down.sh
  ```

---

## 📜 Sumário rápido

| Ação | Comando | Resultado |
|------|----------|------------|
| Subir stack | `./up.sh` | Runner + Vault DEV |
| Confirmar saúde | `curl :18200/v1/sys/health` | JSON ok |
| Executar teste DEV | Workflow → `ENVIRONMENT=dev` | Teste local |
| Reiniciar VM | `./up.sh` | Reativa tudo |
| Migrar para PROD | `ENVIRONMENT=prod` | Usa secrets reais |
