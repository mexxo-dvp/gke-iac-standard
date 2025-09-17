<a id="ua"></a>
[UA](#ua) | [EN](#en)

# GKE IaC (Terraform) — Standard + Flux bootstrap (via CLI) {#ua}

Цей репозиторій розгортає **VPC‑native кластер GKE Standard** з увімкненим **Workload Identity** і формує локальний **kubeconfig**. Для вашого GitOps‑репозиторію створюється **GitHub deploy key (read‑only)**. Додатково, GitHub Actions‑workflow може **запустити Flux bootstrap** через CLI після готовності кластера.

> **Поточний репозиторій:** `gke-iac-standard` (root IaC)
>
> **Пов’язаний GitOps‑репо (маніфести + SOPS/Flux):** `mexxo-dvp/gitops` (споживається Flux після bootstrap)

---

## Що створюється

1. **VPC і підмережа** (VPC‑native):

   * VPC: `gke-vpc-std`
   * Subnet: `gke-subnet-std` (`10.60.0.0/20`)
   * Вторинні діапазони:

     * Pods   → `gke-pods-std` = `10.80.0.0/14`
     * Svcs   → `gke-services-std` = `10.100.0.0/20`
2. **Кластер GKE Autopilot** (регіональний; `release_channel = STABLE`) з **Workload Identity**:

   * Назва кластера → `var.cluster_name` (за замовчуванням `gke-flux-std`)
   * Регіон → `var.region` (за замовчуванням `europe-west1`)
   * `workload_identity_config.workload_pool = "${var.project}.svc.id.goog"`
   * `deletion_protection = false` (дозволяє заміни/видалення з Terraform)
3. **Kubeconfig**, який записується локально на runner’і:

   * `${repo}/.kube/gke-${var.cluster_name}.kubeconfig` (output `kubeconfig_path`)
4. **GitHub deploy key (read‑only)** для вашого GitOps‑репозиторію через `github_repository_deploy_key`.

> **Примітка:** Flux **не** керується через Terraform у цьому репозиторії. Включений workflow виконує **Flux CLI bootstrap** після створення кластера.

---

## Структура репозиторію

```
.
├─ main.tf                  # VPC/Subnet + GKE Standard + kubeconfig + GH deploy key
├─ providers.tf             # провайдери: google, google-beta, github, local, tls
├─ versions.tf              # обмеження версій Terraform та провайдерів
├─ variables.tf             # вхідні змінні (project/region/zone/тощо)
├─ outputs.tf               # kubeconfig_path
├─ backend.tf               # бекенд стану (GCS bucket)
├─ .gitignore
└─ .github/workflows/
   ├─ create-gke.yaml       # Terraform plan/apply + Flux CLI bootstrap
   └─ destroy-gke.yaml      # Terraform destroy (+ аварійне прибирання)
```

---

## Передумови

### 1) Google Cloud

* **Увімкнені API** у вашому проєкті:

  ```bash
  gcloud services enable container.googleapis.com compute.googleapis.com
  ```
* **Бакет для віддаленого стану** (за потреби відредагуйте `backend.tf`). Наразі використовується:

  ```hcl
  terraform {
    backend "gcs" {
      bucket = "tf-state-fifth-diode-472114-p7"
      prefix = "gke-iac/terraform-state"
    }
  }
  ```

  Якщо ви форкаєте репозиторій або міняєте проєкт — створіть власний бакет і оновіть `backend.tf`.

  ```bash
  PROJECT_ID=$(gcloud config get-value project)
  gsutil mb -l europe-west1 "gs://tf-state-${PROJECT_ID}"
  gsutil versioning set on "gs://tf-state-${PROJECT_ID}"
  ```

### 2) Сервісний акаунт для CI

Створіть сервісний акаунт та надайте мінімально необхідні ролі:

```bash
PROJECT_ID=<your-project>
SA_ID=gha-ci
SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

# створення SA
gcloud iam service-accounts create "$SA_ID" \
  --description="GitHub Actions Terraform runner" \
  --display-name="GitHub Actions CI"

# ролі для мережі та GKE
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role roles/container.admin

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role roles/compute.networkAdmin

# доступ до бакета стану (замініть BUCKET, якщо змінили backend.tf)
BUCKET="tf-state-${PROJECT_ID}"
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role roles/storage.objectAdmin

# необов’язково: якщо з CI будете вмикати/вимикати сервіси
#gcloud projects add-iam-policy-binding "$PROJECT_ID" \
#  --member "serviceAccount:${SA_EMAIL}" \
#  --role roles/serviceusage.serviceUsageAdmin

# створіть JSON‑ключ — завантажте його в GitHub Secret GCP_SA_KEY
gcloud iam service-accounts keys create ./gcp-sa-key.json \
  --iam-account "$SA_EMAIL"
```

### 3) GitHub Secrets (для Actions)

Створіть секрети в **Repo Settings → Secrets and variables → Actions → New repository secret**:

| Назва секрету    | Що це                                                                              |
| ---------------- | ---------------------------------------------------------------------------------- |
| `GCP_SA_KEY`     | **JSON**‑ключ сервісного акаунту CI (вміст `gcp-sa-key.json`).                     |
| `GCP_PROJECT_ID` | Ваш ID проєкту GCP (наприклад, `fifth-diode-472114-p7`).                           |
| `GCP_REGION`     | Регіон кластера (наприклад, `europe-west1`).                                       |
| `GCP_ZONE`       | Зона (наприклад, `europe-west1-b`) — для інструментів/сумісності.                  |
| `GH_TOKEN`       | **PAT (classic)** GitHub зі скоупами: `repo`, `admin:public_key` (для deploy key). |

> **Чому PAT?** Провайдер `github` створює **deploy key** у вашому GitOps‑репозиторії; для цього потрібен скоуп `admin:public_key`.

---

## Локальний запуск (опціонально)

Аутентифікація та встановлення ADC (якщо потрібно):

```bash
# приберіть зламаний ADC, якщо є
unset GOOGLE_APPLICATION_CREDENTIALS
rm -f ~/.config/gcloud/application_default_credentials.json

# новий ADC
gcloud auth application-default login --quiet
PROJECT_ID=$(gcloud config get-value project)
gcloud auth application-default set-quota-project "$PROJECT_ID"
```

Ініціалізація та застосування:

```bash
export TF_VAR_project="$PROJECT_ID"
export TF_VAR_region="europe-west1"
export TF_VAR_zone="europe-west1-b"
export TF_VAR_cluster_name="gke-flux"

terraform init -upgrade
terraform fmt -recursive
terraform validate
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
```

Вивід kubeconfig (для швидкого `kubectl`):

```bash
KUBECONFIG=$(terraform output -raw kubeconfig_path) kubectl get nodes -o wide
```

Локальне знищення:

```bash
terraform destroy -auto-approve
```

---

## GitHub Actions — робочі процеси

### Створення GKE + Flux (CLI)

Workflow: `.github/workflows/create-gke.yaml`

* **Вхідні параметри:**

  * `apply` (bool, за замовчуванням: `true`) — якщо `false`, виконує лише plan/validate.
  * `bootstrap` (bool, за замовчуванням: `true`) — запуск **Flux CLI bootstrap** після apply.
* **Що виконує:**

  1. Авторизація в GCP через `GCP_SA_KEY`.
  2. `terraform init` + `apply` (створює VPC/Subnet, GKE Autopilot, kubeconfig та GH deploy key).
  3. Якщо `bootstrap = true`: отримує kube‑context і виконує

     ```bash
     flux bootstrap github \
       --owner=mexxo-dvp \
       --repository=gitops \
       --branch=main \
       --path=clusters/gke \
       --personal \
       --token-auth
     flux reconcile source git flux-system -n flux-system
     flux reconcile kustomization flux-system -n flux-system --with-source
     ```

> Після bootstrap Flux читає з **`mexxo-dvp/gitops` → `clusters/gke`**. Налаштування SOPS/KMS і маніфести застосунків підтримуються **в тому репозиторії**.

### Знищення GKE

Workflow: `.github/workflows/destroy-gke.yaml`

* Виконує `terraform destroy` з тим самим бекендом і змінними.
* Якщо знищення падає (локи, дріфт), виконується **fallback‑прибирання**:

  * Визначає локацію кластера через `gcloud`, видаляє кластер, чистить застарілі адреси стану TF, потім повторює фінальне destroy.

---

## Змінні (загальний огляд)

Повні описи див. у `variables.tf`.

| Змінна         | За замовчуванням | Примітки                                    |
| -------------- | ---------------- | ------------------------------------------- |
| `project`      | —                | **Обов’язково**: ID проєкту GCP             |
| `region`       | `europe-west1`   | Регіональний кластер Autopilot              |
| `zone`         | `europe-west1-b` | Для інструментів/сумісності                 |
| `cluster_name` | `gke-flux`       | Назва кластера                              |
| `github_owner` | `mexxo-dvp`      | Цільовий власник репозиторію для deploy key |
| `github_repo`  | `gitops`         | Репозиторій, куди додається deploy key      |
| `github_token` | порожньо         | PAT (classic), якщо TF взаємодіє з GitHub   |
| `flux_path`    | `clusters/gke`   | Використовується workflow’ом bootstrap      |

---

## Workload Identity

Кластер створюється з **WI** (`workload_pool = "${project}.svc.id.goog"`). Після bootstrap у **GitOps‑репо** анотуйте KSA (Kubernetes ServiceAccount), яким потрібен доступ до GCP (наприклад, контролери Flux для розшифровки SOPS через GCP KMS). Приклад анотації:

```yaml
metadata:
  annotations:
    iam.gke.io/gcp-service-account: "flux-kustomize@<PROJECT_ID>.iam.gserviceaccount.com"
```

Переконайтеся, що відповідний GSA має роль **KMS CryptoKey Decrypter** для вашого ключа, а також налаштовані зв’язки **Workload Identity User** для цільових KSA.

---

## Вартість і життєвий цикл

* **Autopilot** тарифікується за Pod/vCPU/пам’ять + плата за кластер; вартість залежить від регіону та навантаження.
* Зміна `region` або IP‑діапазонів **пересоздає** мережу та кластер.
* `deletion_protection = false` — свідомий вибір для автоматизації CI/CD.

---

## Усунення несправностей

**Backend “bucket not found”**
Створіть бакет та/або оновіть `backend.tf` на вашу назву; перевірте, що CI‑SA має роль `roles/storage.objectAdmin`.

**Помилка `google-github-actions/auth`**
Перевірте, що `GCP_SA_KEY` — валідний **JSON** від сервісного акаунта у вибраному проєкті та потрібні API увімкнені.

**Проблема на кроці GitHub deploy key**
`GH_TOKEN` має бути PAT (classic) зі скоупами `repo` і `admin:public_key`, а репозиторій `github_owner/repo` має існувати.

**Помилки Flux bootstrap**
Перевірте досяжність кластера (`kubectl cluster-info` з виданим kubeconfig) і що шлях у GitOps‑репо існує (`clusters/gke`). Якщо використовуєте SOPS + GCP KMS у тому репозиторії, звірте **проєкт/регіон ключа** та зв’язки **Workload Identity**.

**kubeconfig не знайдено локально**
Шлях kubeconfig створюється на **runner’і**. Для локальних запусків одразу після apply використовуйте `terraform output -raw kubeconfig_path`.

---
<a id="en"></a>

# GKE IaC (Terraform) — Standard + Flux bootstrap (via CLI) {#en}

This repo provisions **a VPC‑native GKE Standard cluster** with **Workload Identity** and writes a local **kubeconfig**. A GitHub deploy key (read‑only) is created for your GitOps repo. Optionally, a GitHub Actions workflow can **bootstrap Flux** into the cluster.

> **Repo you’re reading:** `gke-iac-std` (root IaC)
>
> **Related GitOps repo (manifests + SOPS/Flux):** `mexxo-dvp/gitops` (consumed by Flux after bootstrap)

---

## What this creates

1. **VPC & Subnet** (VPC‑native):

   * VPC: `gke-vpc`
   * Subnet: `gke-subnet-std` (`10.40.0.0/20`)
   * Secondary ranges:

     * Pods   → `gke-pods-std` = `10.60.0.0/14`
     * Svcs   → `gke-services-std` = `10.100.0.0/20`
2. **GKE Autopilot cluster** (regional; `release_channel = STABLE`), with **Workload Identity**:

   * Cluster name → `var.cluster_name` (default `gke-flux-std`)
   * Region → `var.region` (default `europe-west1`)
   * `workload_identity_config.workload_pool = "${var.project}.svc.id.goog"`
   * `deletion_protection = false` (allows replacements/destroys from TF)
3. **Kubeconfig** written locally on runner:

   * `${repo}/.kube/gke-${var.cluster_name}.kubeconfig` (output `kubeconfig_path`)
4. **GitHub deploy key (read‑only)** for your GitOps repo via `github_repository_deploy_key`.

> **Note:** Flux itself is **not** managed by Terraform here. The included workflow runs **Flux CLI bootstrap** after the cluster is ready.

---

## Repository layout

```
.
├─ main.tf                  # VPC/Subnet + GKE Autopilot + kubeconfig + GH deploy key
├─ providers.tf             # google, google-beta, github, local, tls providers
├─ versions.tf              # provider & TF version constraints
├─ variables.tf             # inputs (project/region/zone/etc.)
├─ outputs.tf               # kubeconfig_path
├─ backend.tf               # GCS backend (state bucket)
├─ .gitignore
└─ .github/workflows/
   ├─ create-gke.yaml       # Terraform plan/apply + Flux CLI bootstrap
   └─ destroy-gke.yaml      # Terraform destroy (+ fallback cleanup)
```

---

## Prerequisites

### 1) Google Cloud

* **APIs enabled** on your project:

  ```bash
  gcloud services enable container.googleapis.com compute.googleapis.com
  ```
* **Remote state bucket** (edit `backend.tf` if needed). This repo currently uses:

  ```hcl
  terraform {
    backend "gcs" {
      bucket = "tf-state-fifth-diode-472114-p7"
      prefix = "gke-iac/terraform-state"
    }
  }
  ```

  If you fork this repo or use another project, create your own bucket and update `backend.tf`.

  ```bash
  PROJECT_ID=$(gcloud config get-value project)
  gsutil mb -l europe-west1 "gs://tf-state-${PROJECT_ID}"
  gsutil versioning set on "gs://tf-state-${PROJECT_ID}"
  ```

### 2) Service Account for CI

Create a CI service account and grant the minimal roles:

```bash
PROJECT_ID=<your-project>
SA_ID=gha-ci
SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

# create SA
gcloud iam service-accounts create "$SA_ID" \
  --description="GitHub Actions Terraform runner" \
  --display-name="GitHub Actions CI"

# roles for networking + GKE
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role roles/container.admin

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role roles/compute.networkAdmin

# remote state bucket access (replace BUCKET if you changed backend.tf)
BUCKET="tf-state-${PROJECT_ID}"
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role roles/storage.objectAdmin

# optional: if you intend to enable/disable services from CI
#gcloud projects add-iam-policy-binding "$PROJECT_ID" \
#  --member "serviceAccount:${SA_EMAIL}" \
#  --role roles/serviceusage.serviceUsageAdmin

# create a JSON key — upload its content to GitHub Secret GCP_SA_KEY
gcloud iam service-accounts keys create ./gcp-sa-key.json \
  --iam-account "$SA_EMAIL"
```

### 3) GitHub Secrets (for Actions)

Set these in **Repo Settings → Secrets and variables → Actions → New repository secret**:

| Secret name      | What it is                                                                              |
| ---------------- | --------------------------------------------------------------------------------------- |
| `GCP_SA_KEY`     | **JSON** key of the CI service account (contents of `gcp-sa-key.json`).                 |
| `GCP_PROJECT_ID` | Your GCP project ID (e.g., `fifth-diode-472114-p7`).                                    |
| `GCP_REGION`     | Region for the cluster (e.g., `europe-west1`).                                          |
| `GCP_ZONE`       | Zone (e.g., `europe-west1-b`) — used by tools/compat.                                   |
| `GH_TOKEN`       | GitHub **PAT (classic)** with scopes: `repo`, `admin:public_key` (for deploy key mgmt). |

> **Why PAT?** The `github` provider creates a **deploy key** in your GitOps repo; this needs the `admin:public_key` scope.

---

## Running locally (optional)

Authenticate and set ADC (if needed):

```bash
# clean up previous ADC if broken
unset GOOGLE_APPLICATION_CREDENTIALS
rm -f ~/.config/gcloud/application_default_credentials.json

# new ADC
gcloud auth application-default login --quiet
PROJECT_ID=$(gcloud config get-value project)
gcloud auth application-default set-quota-project "$PROJECT_ID"
```

Initialize and apply:

```bash
export TF_VAR_project="$PROJECT_ID"
export TF_VAR_region="europe-west1"
export TF_VAR_zone="europe-west1-b"
export TF_VAR_cluster_name="gke-flux"

terraform init -upgrade
terraform fmt -recursive
terraform validate
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
```

Kubeconfig output (for quick kubectl):

```bash
KUBECONFIG=$(terraform output -raw kubeconfig_path) kubectl get nodes -o wide
```

Destroy locally:

```bash
terraform destroy -auto-approve
```

---

## GitHub Actions workflows

### Create GKE + Flux (CLI)

Workflow: `.github/workflows/create-gke.yaml`

* **Inputs:**

  * `apply` (bool, default: `true`) — if `false`, runs plan/validate only.
  * `bootstrap` (bool, default: `true`) — run **Flux CLI bootstrap** after apply.
* **What it does:**

  1. Auth to GCP using `GCP_SA_KEY`.
  2. `terraform init` + `apply` (creates VPC/Subnet + GKE Autopilot + kubeconfig + GH deploy key).
  3. If `bootstrap = true`: fetch kube-context and run

     ```bash
     flux bootstrap github \
       --owner=mexxo-dvp \
       --repository=gitops \
       --branch=main \
       --path=clusters/gke \
       --personal \
       --token-auth
     flux reconcile source git flux-system -n flux-system
     flux reconcile kustomization flux-system -n flux-system --with-source
     ```

> After bootstrap, Flux reads from **`mexxo-dvp/gitops` → `clusters/gke`**. Configure SOPS/KMS and app manifests **in that repo**.

### Destroy GKE

Workflow: `.github/workflows/destroy-gke.yaml`

* Runs `terraform destroy` with the same backend and variables.
* If destroy fails (locks, drift), it performs a **legacy cleanup**:

  * Detects cluster location via `gcloud`, deletes the cluster, removes legacy TF state addresses, then retries a final destroy.

---

## Variables (high level)

See `variables.tf` for full descriptions.

| Variable       | Default          | Notes                                     |
| -------------- | ---------------- | ----------------------------------------- |
| `project`      | —                | **Required** GCP project ID               |
| `region`       | `europe-west1`   | Regional Autopilot cluster                |
| `zone`         | `europe-west1-b` | For tools/compat                          |
| `cluster_name` | `gke-flux`       | Cluster name                              |
| `github_owner` | `mexxo-dvp`      | For deploy key target repo                |
| `github_repo`  | `gitops`         | Deploy key added here                     |
| `github_token` | empty            | PAT (classic) if you wire TF → GitHub ops |
| `flux_path`    | `clusters/gke`   | Used by bootstrap workflow                |

---

## Workload Identity

The cluster is created with **WI enabled** (`workload_pool = "${project}.svc.id.goog"`). Once Flux is bootstrapped, annotate in the **GitOps repo** the service accounts that need GCP access (e.g., Flux controllers to decrypt SOPS files using GCP KMS). We used annotations like:

```yaml
metadata:
  annotations:
    iam.gke.io/gcp-service-account: "flux-kustomize@<PROJECT_ID>.iam.gserviceaccount.com"
```

Make sure that GSA has the right **KMS Decrypter** role on your key, and its **Workload Identity User** bindings include the target KSA(s).

---

## Cost & lifecycle notes

* **Autopilot** bills per Pod/vCPU/memory + cluster fee; costs vary by region and usage.
* Changing `region` or IP ranges will **recreate** networking and cluster.
* `deletion_protection = false` is intentional for CI/CD automation.

---

## Troubleshooting

**Backend “bucket not found”**
Create the bucket and/or update `backend.tf` to your bucket name; ensure the CI SA has `roles/storage.objectAdmin` on it.

**`google-github-actions/auth` fails**
Double‑check `GCP_SA_KEY` is a **valid JSON** for a service account in the selected project and that APIs are enabled.

**GitHub deploy key step fails**
`GH_TOKEN` must be a PAT (classic) with scopes `repo` and `admin:public_key`, and the `github_owner/repo` must exist.

**Flux bootstrap errors**
Confirm the cluster is reachable (`kubectl cluster-info` using the emitted kubeconfig), and that your GitOps repo path exists (`clusters/gke`). If you use SOPS + GCP KMS in that repo, verify the **key project/region** and **Workload Identity** bindings are correct.

**Kubeconfig not found on local machine**
The kubeconfig path is created on the **runner**. For local runs, use `terraform output -raw kubeconfig_path` immediately after apply.

---