# GKE IaC (Terraform) — робочий гайд

> Це **root**‑репозиторій `gke-iac`, який створює/керує кластерами **GKE** через Terraform.
> У репозиторії **gitops** ми нічого не змінювали, окрім ключів/секретів; bootstrap Flux тут лише підвʼязує кластер до вже підготовленого GitOps‑шляху.

---

## Репозиторії

* **Модуль**: `github.com/mexxo-dvp/tf-google-gke-cluster`

  * Описує ресурси `google_container_cluster` та `google_container_node_pool`.
  * Ключові моменти:

    * `deletion_protection = false` для керованих замін/видалень.
    * Параметр `GOOGLE_LOCATION` (підтримує **регіон** або **зону**).

* **Root**: цей репозиторій (**gke-iac**)

  * Підтягує модуль, визначає вхідні змінні, `tfvars`, бекенд, та CI‑workflow для створення GKE і (опційно) Flux bootstrap.

---

## Передумови (локально / Cloud Shell)

* Активний проєкт:

```bash
gcloud config get-value project
```

* Увімкнені API:

```bash
gcloud services enable container.googleapis.com compute.googleapis.com
```

* **ADC (Application Default Credentials)** — якщо були помилки токена локально:

```bash
# прибрати поламані ADC
unset GOOGLE_APPLICATION_CREDENTIALS
rm -f ~/.config/gcloud/application_default_credentials.json

# нові ADC
gcloud auth application-default login --quiet

# привʼязати квоти до проєкту
PROJECT_ID=$(gcloud config get-value project)
gcloud auth application-default set-quota-project "$PROJECT_ID"

# sanity-check
gcloud auth application-default print-access-token | head -c 20; echo
```

---

## Структура (root `gke-iac/`)

```
gke-iac/
├─ .github/
|  └─workflows/
|   ├─create-gke.yaml
|   └─destroy-gke.yaml
├─ main.tf
├─ variables.tf
├─ vars.tfvars
├─ backend.tf
├─ outputs.tf
├─ providers.tf
├─ versions.tf
├─ .gitignore
└─ README.md
```

### `backend.tf` (GCS бекенд)

```hcl
terraform {
  backend "gcs" {
    bucket = "tf-state-<YOUR_PROJECT_ID>"
    prefix = "gke-iac/terraform-state"
  }
}
```

### `variables.tf`

```hcl
variable "GOOGLE_PROJECT"  { type = string }
variable "GOOGLE_REGION"   { type = string } # напр. "europe-west1"
variable "GOOGLE_LOCATION" { type = string } # регіон або зона, напр. "europe-west1-b"

variable "GKE_CLUSTER_NAME" { type = string, default = "main-z" }
variable "GKE_POOL_NAME"    { type = string, default = "main" }
variable "GKE_MACHINE_TYPE" { type = string, default = "g1-small" }
variable "GKE_NUM_NODES"    { type = number, default = 1 }
```

### `vars.tfvars`

```hcl
GOOGLE_PROJECT   = "<YOUR_PROJECT_ID>"
GOOGLE_REGION    = "europe-west1"
GOOGLE_LOCATION  = "europe-west1-b"
GKE_CLUSTER_NAME = "main-z"
GKE_POOL_NAME    = "main"
GKE_MACHINE_TYPE = "g1-small"
GKE_NUM_NODES    = 1
```

### `main.tf` (root, підключає модуль)

```hcl
module "gke_cluster" {
  source = "github.com/mexxo-dvp/tf-google-gke-cluster"

  GOOGLE_PROJECT   = var.GOOGLE_PROJECT
  GOOGLE_REGION    = var.GOOGLE_REGION
  GOOGLE_LOCATION  = var.GOOGLE_LOCATION   # для зонального кластера — передаємо ЗОНУ
  GKE_CLUSTER_NAME = var.GKE_CLUSTER_NAME
  GKE_POOL_NAME    = var.GKE_POOL_NAME
  GKE_MACHINE_TYPE = var.GKE_MACHINE_TYPE
  GKE_NUM_NODES    = var.GKE_NUM_NODES
}
```

### `.gitignore`

```gitignore
.terraform/
*.tfstate*
*.tfplan
crash.log
override.tf
override.tf.json
plan.json
.terraform.lock.hcl
```

---

## Модуль: ключові моменти (для довідки)

```hcl
resource "google_container_cluster" "this" {
  name     = var.GKE_CLUSTER_NAME
  location = var.GOOGLE_LOCATION       # регіон або зона

  deletion_protection       = false    # критично для керованих destroy/replace
  remove_default_node_pool  = true
  initial_node_count        = 1

  workload_identity_config {
    workload_pool = "${var.GOOGLE_PROJECT}.svc.id.goog"
  }

  node_config {
    workload_metadata_config { mode = "GKE_METADATA" }
  }
}

resource "google_container_node_pool" "this" {
  name       = var.GKE_POOL_NAME
  project    = var.GOOGLE_PROJECT
  cluster    = google_container_cluster.this.name
  location   = var.GOOGLE_LOCATION
  node_count = var.GKE_NUM_NODES

  node_config {
    machine_type = var.GKE_MACHINE_TYPE
  }
}
```

> Змінні в модулі та у root мають збігатися.

---

## GCS‑бакет під Terraform state

```bash
PROJECT_ID=$(gcloud config get-value project)
BUCKET="tf-state-${PROJECT_ID}"

# створити бакет (рекомендовано у тому ж регіоні, що й кластер)
gsutil mb -l europe-west1 "gs://${BUCKET}"

# ввімкнути версіонування
gsutil versioning set on "gs://${BUCKET}"
```

Потім пропишіть `bucket` у `backend.tf` і зробіть `terraform init` (погодьтеся на міграцію локального стейту, якщо буде запропоновано).

---

## Ініціалізація, план і аплай

```bash
terraform init -upgrade
terraform fmt -recursive
terraform validate

# (опц.) окремий workspace для сценарію
terraform workspace new zonal || terraform workspace select zonal

# план і аплай
terraform plan   -var-file=vars.tfvars -out=zonal.tfplan
terraform apply "zonal.tfplan"
```

**Очікувано**: створиться **зональний** кластер `main-z` у `europe-west1-b` з 1 нодою типу `g1-small`.

---

## Перевірка кластера

```bash
# огляд кластерів
gcloud container clusters list --format='table(name,location,status)'

# нодпули (для зонального кластера)
gcloud container node-pools list --cluster main-z --zone europe-west1-b \
  --format='table(name,initialNodeCount,locations)'

# kube‑контекст і ноди
gcloud container clusters get-credentials main-z --zone europe-west1-b
kubectl get nodes -o wide
```

Приклад (очікувано 1 нода):

```
NAME                            STATUS   ROLES   AGE   VERSION               INTERNAL-IP   EXTERNAL-IP
gke-main-z-main-xxxxxxx-xxxx    Ready    <none>  ...   v1.33.x-gke.xxxxx     10.132.x.x    34.xxx.xx.x
```

---

## Infracost (опційно)

```bash
curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh

terraform show -json zonal.tfplan > plan.json
infracost breakdown --path plan.json
# (опц.) різниця планів
infracost diff --path plan.json
```

> Орієнтовно (1 нода `g1-small`): \~ **\$92/міс** (Cluster mgmt fee \~\$73 + інстанс \~\$15 + PD \~\$4).

---

## Ремоут‑стейт: перевірка

```bash
BUCKET=$(jq -r '.backend.config.bucket'  .terraform/terraform.tfstate)
PREFIX=$(jq -r '.backend.config.prefix'  .terraform/terraform.tfstate)
WS=$(terraform workspace show)

echo "bucket=${BUCKET}"
echo "prefix=${PREFIX}"
echo "workspace=${WS}"

gsutil ls -l "gs://${BUCKET}/${PREFIX}/${WS}.tfstate"
```

---

## CI/CD: GitHub Actions у цьому репозиторії

### Обовʼязкові **Secrets** (repo **gke-iac**)

* `GCP_SA_KEY` — **JSON ключ** сервісного акаунта для CI (Terraform/gcloud).
* `GCP_PROJECT_ID` — напр. `fifth-diode-<...>`
* `GCP_REGION` — напр. `europe-west1`
* `GCP_ZONE` — напр. `europe-west1-b`
* `GH_TOKEN` — **PAT** із правами `repo` + `admin:public_key` (потрібен, якщо вмикаєте Flux bootstrap до репо **gitops**).

### Ролі для CI‑Service Account

```bash
SA_EMAIL="gha-ci@<PROJECT_ID>.iam.gserviceaccount.com"
PROJECT_ID="<PROJECT_ID>"
TF_BUCKET="tf-state-<PROJECT_ID>"

# GKE / VPC
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:${SA_EMAIL}" --role roles/container.admin

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:${SA_EMAIL}" --role roles/compute.networkAdmin

# Доступ до GCS state
gcloud storage buckets add-iam-policy-binding "gs://${TF_BUCKET}" \
  --member "serviceAccount:${SA_EMAIL}" --role roles/storage.objectAdmin
```

### Workflow: **Create GKE + Flux (CLI)**

* Файл: `.github/workflows/create-gke.yaml`
* Запуск: **Actions → Create GKE + Flux (CLI) → Run workflow**
* Інпути:

  * `apply` — `true` виконує `terraform apply` (інакше тільки `plan`).
  * `bootstrap` — `true` запускає `flux bootstrap` до репо **gitops** (ідемпотентно).

**Що робить workflow**:

1. `terraform init/plan/apply` з бекендом у GCS;
2. `gcloud container clusters get-credentials` для нового кластера;
3. (якщо `bootstrap=true`) `flux bootstrap github --owner=mexxo-dvp --repository=gitops --branch=main --path=clusters/gke --personal --token-auth`.

> **Примітка:** у репозиторії **gitops** ми нічого не змінювали, окрім ключів/секретів. Flux bootstrap тут лише підвʼяже кластер до вашого GitOps‑шляху `clusters/gke`.

### Як підключитись до кластера локально

```bash
gcloud container clusters get-credentials gke-flux \
  --region "$GCP_REGION" --project "$GCP_PROJECT_ID"

kubectl get nodes
```

### Ротація `GCP_SA_KEY` (для цього репо)

```bash
SA_EMAIL="gha-ci@<PROJECT_ID>.iam.gserviceaccount.com"
PROJECT_ID="<PROJECT_ID>"

gcloud iam service-accounts keys create gcp-sa-key.json \
  --iam-account="$SA_EMAIL" --project "$PROJECT_ID"

# Далі: Settings → Secrets and variables → Actions → New secret → GCP_SA_KEY
# Вміст — повний JSON з файлу gcp-sa-key.json

# (опц.) видалити старі ключі
gcloud iam service-accounts keys list --iam-account="$SA_EMAIL"
gcloud iam service-accounts keys delete <KEY_ID> --iam-account="$SA_EMAIL"
```

---

## Troubleshooting (gke-iac)

* **403 до GCS backend**
  Немає `roles/storage.objectAdmin` для `${SA_EMAIL}` на бакеті `gs://${TF_BUCKET}`.

* **Terraform не бачить кластер/мережу**
  Перевір `GCP_PROJECT_ID` / `GCP_REGION` / `GCP_ZONE` та увімкнені API `container`, `compute`.

* **Flux bootstrap впав на SOPS/KMS**
  Це вже зона репозиторію **gitops** (ключі KMS/Secret Manager, SOPS‑правила). У цьому репо можна тимчасово запускати з `bootstrap=false`.

---

## Прибирання витрат

```bash
# приклад: регіональний
gcloud container clusters delete main --region europe-west1

# приклад: ще один зональний
gcloud container clusters delete demo-cluster --zone europe-west3-a
```

---

## Destroy

Модуль виставляє `deletion_protection = false`, тому стандартний destroy працює:

```bash
terraform destroy -var-file=vars.tfvars
```
