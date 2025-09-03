# GKE IaC (Terraform) — робочий гайд
Репозиторії

Модуль: tf-google-gke-cluster (GitHub: github.com/mexxo-dvp/tf-google-gke-cluster)
В ньому описані ресурси google_container_cluster та google_container_node_pool.
Ключові фікси:

deletion_protection = false для можливості керованих замін/видалень.

Параметр GOOGLE_LOCATION (підтримує регіон або зону).

Root: gke-iac (цей репозиторій)
Підтягує модуль вище, визначає вхідні змінні, tfvars, бекенд і робочі кроки.

Передумови

Працюємо в Google Cloud Shell (вже є gcloud, terraform).

## Активний проєкт:

```bash
gcloud config get-value project
```
Увімкнені API:
```bash
gcloud services enable container.googleapis.com compute.googleapis.com
```
## Аутентифікація (ADC) — якщо були помилки токена
```bash
# прибрати поламані ADC
unset GOOGLE_APPLICATION_CREDENTIALS
rm -f ~/.config/gcloud/application_default_credentials.json

# нові ADC
gcloud auth application-default login --quiet

# прив’язати квоти до проєкту
PROJECT_ID=$(gcloud config get-value project)
gcloud auth application-default set-quota-project "$PROJECT_ID"

# sanity-check
gcloud auth application-default print-access-token | head -c 20; echo
```

## Структура root-репо (gke-iac/)
```text
gke-iac/
├─ main.tf
├─ variables.tf
├─ vars.tfvars
├─ backend.tf
├─ .gitignore
└─ README.md  ← цей файл
```
backend.tf (GCS бекенд)
```hcl
terraform {
  backend "gcs" {
    bucket = "tf-state-<YOUR_PROJECT_ID>"
    prefix = "gke-iac/terraform-state"
  }
}
```
variables.tf
```hcl
variable "GOOGLE_PROJECT"  { type = string }
variable "GOOGLE_REGION"   { type = string } # напр. "europe-west1"
variable "GOOGLE_LOCATION" { type = string } # регіон або зона, напр. "europe-west1-b"

variable "GKE_CLUSTER_NAME" { type = string, default = "main-z" }
variable "GKE_POOL_NAME"    { type = string, default = "main" }
variable "GKE_MACHINE_TYPE" { type = string, default = "g1-small" }
variable "GKE_NUM_NODES"    { type = number, default = 1 }
```
vars.tfvars
```hcl
GOOGLE_PROJECT  = "type-your-pattern-name"
GOOGLE_REGION   = "europe-west1"
GOOGLE_LOCATION = "europe-west1-b"
GKE_CLUSTER_NAME = "main-z"
GKE_POOL_NAME    = "main"
GKE_MACHINE_TYPE = "g1-small"
GKE_NUM_NODES    = 1
```
main.tf (root, підключає модуль)
```hcl
module "gke_cluster" {
  source = "github.com/mexxo-dvp/tf-google-gke-cluster"

  GOOGLE_PROJECT   = var.GOOGLE_PROJECT
  GOOGLE_REGION    = var.GOOGLE_REGION
  GOOGLE_LOCATION  = var.GOOGLE_LOCATION   # тут передаємо ЗОНУ для зонального кластера
  GKE_CLUSTER_NAME = var.GKE_CLUSTER_NAME
  GKE_POOL_NAME    = var.GKE_POOL_NAME
  GKE_MACHINE_TYPE = var.GKE_MACHINE_TYPE
  GKE_NUM_NODES    = var.GKE_NUM_NODES
}
```
.gitignore
```pgsql
.terraform/
*.tfstate*
*.tfplan
crash.log
override.tf
override.tf.json
plan.json
.terraform.lock.hcl
```
## Модуль (tf-google-gke-cluster/) — ключові моменти

У ресурсі кластера обов’язково:
```hcl
resource "google_container_cluster" "this" {
  name     = var.GKE_CLUSTER_NAME
  location = var.GOOGLE_LOCATION    # підтримує регіон або зону
  deletion_protection = false       # критично, щоби Terraform міг знищити/замінити
  remove_default_node_pool = true
  initial_node_count       = 1

  workload_identity_config {
    workload_pool = "${var.GOOGLE_PROJECT}.svc.id.goog"
  }

  node_config {
    workload_metadata_config { mode = "GKE_METADATA" }
  }
}
```
Нодпул:
```hcl
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
Варіанти variables.tf у модулі мають збігатися з root.

## Створення GCS-бакета під state
```bash
PROJECT_ID=$(gcloud config get-value project)
BUCKET="tf-state-${PROJECT_ID}"

# cтворити бакет у тому ж регіоні, що й кластер (рекомендація)
gsutil mb -l europe-west1 "gs://${BUCKET}"

# (рекомендовано) ввімкнути версіонування
gsutil versioning set on "gs://${BUCKET}"
```
У backend.tf вписати цей bucket.

## Ініціалізація, план і аплай

Якщо вперше підключаєте GCS-бекенд — Terraform запитає про міграцію локального стейту в GCS.
```bash
cd ~/gke-iac

terraform init -upgrade
terraform fmt -recursive
terraform validate

# (опційно) створити workspace для зонального сценарію
terraform workspace new zonal || terraform workspace select zonal

# план і аплай
terraform plan -var-file=vars.tfvars -out=zonal.tfplan
terraform apply "zonal.tfplan"
```
Очікуваний результат: створиться зональний кластер main-z у europe-west1-b з 1 нодою типу g1-small.

## Перевірка кластера
```bash
# огляд
gcloud container clusters list --format='table(name,location,status)'

# нодпули (саме ЗОНАЛЬНОГО кластера)
gcloud container node-pools list --cluster main-z --zone europe-west1-b \
  --format='table(name,initialNodeCount,locations)'

# контекст і ноди
gcloud container clusters get-credentials main-z --zone europe-west1-b
kubectl get nodes -o wide
```
Приклад (очікувано 1 нода):
```css
NAME                            STATUS   ROLES   AGE   VERSION               INTERNAL-IP   EXTERNAL-IP   ...
gke-main-z-main-xxxxxxx-xxxx    Ready    <none>  ...   v1.33.x-gke.xxxxx     10.132.x.x    34.xxx.xx.x
```
## Infracost
```bash
curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh
```
Оцінка:
```bash
terraform show -json zonal.tfplan > plan.json
infracost breakdown --path plan.json

# (опційно) різниця планів
infracost diff --path plan.json
```
Результат з нашого сетапу (1 нода, g1-small): ~$92/міс
(Cluster mgmt fee ~$73 + інстанс ~$15 + PD ~$4)

## Ремоут-стейт: перевірка
Terraform зберігає стейт у бакеті, наприклад:
```perl
gs://tf-state-<PROJECT_ID>/gke-iac/terraform-state/zonal.tfstate
```

Перевірка:
```bash
# витягнути bucket/prefix/workspace з локальної мети
BUCKET=$(jq -r '.backend.config.bucket' .terraform/terraform.tfstate)
PREFIX=$(jq -r '.backend.config.prefix' .terraform/terraform.tfstate)
WS=$(terraform workspace show)

echo "bucket=${BUCKET}"
echo "prefix=${PREFIX}"
echo "workspace=${WS}"

# подивитись об’єкт
gsutil ls -l "gs://${BUCKET}/${PREFIX}/${WS}.tfstate"
```
## Прибирання зайвих витрат
```bash
# приклад: регіональний
gcloud container clusters delete main --region europe-west1

# приклад: ще один зональний
gcloud container clusters delete demo-cluster --zone europe-west3-a
```
## Destroy (коли треба знести все)

Наш модуль ставить deletion_protection = false, тому:
```bash
terraform destroy -var-file=vars.tfvars
```