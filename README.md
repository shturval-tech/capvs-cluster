# capvs-cluster

Helm-чарт для развёртывания Kubernetes-кластера через **Cluster API** с
инфраструктурным провайдером **CAPV (Cluster API Provider vSphere)** и
Shturval `ClusterConfig`. По смыслу — аналог `capsm-cluster`, но VM поднимаются
не на bare-metal через Shturval, а на vCenter.

Чарт создаёт:

- `Namespace` под кластер
- `VSphereClusterIdentity` (cluster-scoped) + `Secret` с креденшелами vCenter
  (в namespace CAPV-контроллера, по умолчанию `shturval-capvs`)
- `VSphereCluster` + `Cluster` (Cluster API)
- `KubeadmControlPlane` + `VSphereMachineTemplate` для control-plane
- По одному `MachineDeployment` + `KubeadmConfigTemplate` +
  `VSphereMachineTemplate` на каждую worker-группу из `values.yaml`
- `MachineHealthCheck` (опционально, по флагу)
- Shturval-специфику: `ClusterConfig`, secret с базовой конфигурацией,
  secret для encryption-at-rest, внешние etcd-секреты (если используется)
- при `workerNodes.<group>.autoscaling.enabled` — Deployment
  `{release}-autoscaler` (Cluster API cluster-autoscaler) + аннотации min/max
  на соответствующем `MachineDeployment`

> **VIP API:** на control-plane в `/etc/std/nci.json` (ShturvalInit) задаётся
> static Pod **kube-vip** с `vip_address` = `clusterAPI` (как в vSphere demo).
> Без этого VIP не появляется. В `values` см. `nodeInit.kubevip.interface` (часто
> `ens192` в госте VMware). `shturval-vip-provider` в management-кластере и
> сервисы `shturval-vip` / `shturval-node-config` на стороне кластера — по
> документации вашей версии Штурвала.

## Предварительные требования

1. Управляющий кластер с установленными операторами:
   - `cluster-api` core;
   - `cluster-api-provider-vsphere` (CAPV) — CRD
     `infrastructure.cluster.x-k8s.io` (чарт использует **`v1beta1`** для
     совместимости с Штурвалом; `v1beta2` для инфраструктурных объектов не
     поддерживается);
2. В vCenter:
   - пользователь с правами на создание/клонирование VM;
   - подготовленный VM-шаблон с cloud-init, containerd и kubelet
     (см. документацию CAPV, template-image-builder);
   - datacenter / datastore / folder / resource pool / сеть.
3. При использовании внешнего etcd — сертификаты лежат в `conf/ext_etcd-*`.

### Чувствительные данные и значения по умолчанию

В репозитории в `values.yaml` заданы **плейсхолдеры** (`XXXXXXXX` для лицензии, `secret` для пароля vCenter, примеры FQDN/IP). Реальные токены и пароли передаются при установке:

- `helm upgrade --install ... -f values-local.yaml` (файл в `.gitignore`, см. примеры имён в `.gitignore`);
- или `--set licensetoken=...`, `--set capvs.password=...` и т.д.

## Быстрый старт

```bash
helm upgrade --install mycluster . \
  --set licensetoken=XXXXXXXX \
  --set systemregistry=myregistry.domain.tld \
  --set clusterAPI=10.31.145.172 \
  --set ingressVip=10.31.145.173 \
  --set ingress="apps.ip-10-31-145-173.shturval.link" \
  --set logsMgmtIngress="logs.app.ip-10-31-145-175.shturval.link" \
  --set metricsMgmtIngress="vminsert.app.ip-10-31-145-175.shturval.link" \
  --set capvs.server=vcenter.example.com \
  --set capvs.username='administrator@vsphere.local' \
  --set capvs.password='supersecret' \
  --set capvs.datacenter=/Datacenter \
  --set capvs.datastore=Datastore1 \
  --set capvs.folder=/Datacenter/vm/cluster-api \
  --set capvs.resourcePool=/Datacenter/host/Cluster/Resources \
  --set capvs.template=shturval-ubuntu2204-template
```

## Ключевые секции `values.yaml`

### `capvs` — глобальные настройки vSphere

| Ключ | Назначение |
|------|-----------|
| `identityName` | Имя `VSphereClusterIdentity`. Пусто ⇒ `Release.Name` |
| `credentialsNamespace` | Namespace, где будет создан secret с паролем vCenter (должен совпадать с namespace CAPV-контроллера) |
| `username`, `password` | Креденшелы vCenter |
| `server`, `thumbprint` | Адрес vCenter и SHA-1 отпечаток TLS |
| `datacenter`, `datastore`, `folder`, `resourcePool` | vSphere placement по умолчанию |
| `template` | Имя VM-шаблона для клонирования |
| `cloneMode` | `linkedClone` / `fullClone` |
| `powerOffMode` | `hard` / `soft` / `trySoft` |
| `storagePolicyName` | vSphere storage policy (опц.) |
| `network.devices` | Сетевые интерфейсы по умолчанию |
| `vm` | Размер VM (numCPUs, memoryMiB, diskGiB, additionalDisksGiB) |

### Per-group переопределения

`master.*` и `workerNodes.<group>.*` могут переопределить любой из ключей
`capvs.*`:

```yaml
master:
  replicas: 3
  vm:
    numCPUs: 8
    memoryMiB: 16384
    diskGiB: 120
    additionalDisksGiB:
      - 200
  network:
    devices:
      - networkName: "/Datacenter/network/Mgmt"
        dhcp4: false
        ipAddrs:
          - "10.31.145.50/24"
          - "10.31.145.51/24"
          - "10.31.145.52/24"
        gateway4: "10.31.145.1"
        nameservers: ["10.31.145.1"]

workerNodes:
  workers:
    replicas: 3
    vm:
      numCPUs: 4
      memoryMiB: 8192
      diskGiB: 100
    network:
      devices:
        - networkName: "/Datacenter/network/Workload"
          dhcp4: true
  infra:
    replicas: 3
    vm:
      numCPUs: 4
      memoryMiB: 8192
      diskGiB: 80
    taints:
      - key: mytain/infra
        effect: NoSchedule
```

### Сеть

Поддерживаются оба режима:

- **DHCP** (по умолчанию):
  ```yaml
  network:
    devices:
      - networkName: "/Datacenter/network/VM Network"
        dhcp4: true
  ```
- **Статический IP** (по одному адресу на реплику):
  ```yaml
  network:
    devices:
      - networkName: "/Datacenter/network/Mgmt"
        dhcp4: false
        ipAddrs:
          - "10.31.145.50/24"
          - "10.31.145.51/24"
          - "10.31.145.52/24"
        gateway4: "10.31.145.1"
        nameservers: ["10.31.145.1"]
        searchDomains: ["shturval.local"]
  ```

## API-версии

- `infrastructure.cluster.x-k8s.io/v1beta1` — `VSphereCluster`,
  `VSphereClusterIdentity`, `VSphereMachineTemplate` (требование Штурвала;
  `v1beta2` для этих ресурсов не поддерживается)
- `cluster.x-k8s.io/v1beta2` — `Cluster`, `MachineDeployment`,
  `MachineHealthCheck`
- `controlplane.cluster.x-k8s.io/v1beta2` — `KubeadmControlPlane`
- `bootstrap.cluster.x-k8s.io/v1beta2` — `KubeadmConfigTemplate`

`cluster.shturval.tech/v1beta1` — `ClusterConfig` (Shturval).

## Типовые сценарии

### Изменить количество реплик worker-группы

```yaml
workerNodes:
  workers:
    replicas: 5        # было 2
```

Затем `helm upgrade`. CAPV создаст новые VM в vCenter.

### Автомасштабирование группы узлов (cluster-autoscaler)

Для группы worker-узлов можно включить автомасштабирование через Cluster API
cluster-autoscaler (как в UI/backend Штурвала и в чарте `capsm-cluster`):

```yaml
workerNodes:
  workers:
    replicas: 2 # минимум и стартовое число узлов
    autoscaling:
      enabled: true
      maxMachines: 6
    vm:
      numCPUs: 4
      memoryMiB: 8192
      diskGiB: 100
```

Что происходит при `autoscaling.enabled: true`:

- на `MachineDeployment` выставляются аннотации
  `cluster.x-k8s.io/cluster-api-autoscaler-node-group-min-size` (= `replicas`) и
  `...-max-size` (= `maxMachines`);
- `spec.replicas` **не рендерится** (им владеет autoscaler) — иначе
  `helm template` / helm-drift показывают вечный drift;
- в namespace кластера создаются ServiceAccount, ClusterRoleBinding на
  `shturval-cluster-autoscaler` и Deployment `{release}-autoscaler`
  с `--enforce-node-group-min-size`.

В отличие от CAPSM, CAPV при scale up **клонирует новые VM** из template в
vCenter — нужны свободные ресурсы датастора/кластера и квота. На
management-кластере должен быть ClusterRole `shturval-cluster-autoscaler`
(ставит платформа вместе с backend). Образ autoscaler по умолчанию:
`{{ systemregistry }}/autoscaling/cluster-autoscaler:v1.36.1-325745` для `2.15.0`
(тег из профиля релиза, не из версии Kubernetes; override: `images.clusterAutoscaler`).

### Добавить новую worker-группу

```yaml
workerNodes:
  gpu:
    replicas: 2
    vm:
      numCPUs: 16
      memoryMiB: 65536
      diskGiB: 200
    labels:
      - "node-role.kubernetes.io/gpu="
    taints:
      - key: node-role.kubernetes.io/gpu
        effect: NoSchedule
```

### Включить MachineHealthCheck

```yaml
workerNodes:
  workers:
    machineHealthCheck:
      enabled: true
      checks:
        nodeStartupTimeoutSeconds: 0
        unhealthyNodeConditions:
          - status: "False"
            timeoutSeconds: 600
            type: Ready
      remediation:
        triggerIf:
          unhealthyLessThanOrEqualTo: 40%
```

### Сменить пароль vCenter

`capvs.password` — обычный string в values. Helm-апгрейд пересоздаст
secret, CAPV подхватит новый пароль автоматически (через
`VSphereClusterIdentity`).

### Не поднимается VIP для kube-apiserver (`clusterAPI`)

Проверьте по порядку:

1. **`clusterAPI` в `values.yaml`** совпадает с выданным подсетью IP и с тем,
   что ожидает `VSphereCluster.spec.controlPlaneEndpoint` / CAPI `Cluster`.
2. **`nodeInit.kubevip.interface`** — на master `ip -br a` или `ip a`: имя интерфейса
   в сторону нужной L2-сети (часто не `eth0`, а `ens192` / `ens160`). Укажите
   в values и переустановите/обновите control plane.
3. **Файл `/etc/std/nci.json`** на ноде (после bootstrap) и Pod `kube-vip` в
   `kube-system` на control-plane-ноде. Чарт кладёт nci и манифест kube-vip в
   `KubeadmControlPlane` при `useExternalKubeAPILB: false`.
4. Ожидание `std node status == synched` в `preKubeadm` — если nci неверный,
   sync может не наступить (см. логи `shturvald` / `std` на ВМ).
5. Внешний **LB** вместо VIP: `useExternalKubeAPILB: true` и тогда
   `deployKeepAlived` в `ClusterConfig` не поднимает keepalived на нодах;
   маршрутизируйте трафик на балансировщик, а `clusterAPI` = его IP/DNS.

### Ошибка: Namespace exists … invalid ownership metadata

Если `helm install` / `helm upgrade` падает с сообщением, что
`Namespace "<release-name>"` уже существует и не может быть импортирован в
релиз (нет `meta.helm.sh/*` и `app.kubernetes.io/managed-by: Helm`), значит
namespace с именем **релиза** был создан вне Helm. Чарт всегда создаёт
`Namespace` с именем `Release.Name`.

**Варианты:**

1. Удалить namespace (осторожно: удалит всё внутри) и поставить релиз снова,
   чтобы Helm создал namespace сам.

2. Вручную проставить на namespace метки/аннотации, совпадающие с ожидаемым
   релизом (см. `kubectl get ns <release> -o yaml` на рабочем кластере после
   успешного `helm install`).

## Удаление

```bash
helm uninstall mycluster
```

VM будут удалены контроллерами Cluster API и CAPV после удаления
`MachineDeployment` / `KubeadmControlPlane`.

> Secret в `capvs.credentialsNamespace` удаляется тоже (т.к. он
> создаётся этим чартом). Если вы хотите его сохранить, поменяйте
> `capvs.identityName` на внешнее имя и создайте `VSphereClusterIdentity`
> отдельно.

## Обновление чарта с 2.14 на 2.15

Чарт `2.15` ставит новый кластер Штурвала **2.15.0** (Kubernetes 1.36.5).
Уже работающий кластер 2.14 этим чартом обновляется только как Helm-релиз:
машины не пересоздаются и обновление платформы не стартует, если values
по-прежнему описывают 2.14.

1. Сначала обновите менеджмент-кластер до Штурвала 2.15 (CRD `InfrastructureProvider`, CAPI v1beta2). Потом обновляйте чарты клиентских кластеров.
2. Возьмите values, которыми кластер ставился (`helm get values <release> -n <namespace> -o yaml`), а не дефолты нового чарта.
3. Не используйте `--reuse-values` вслепую и не подставляйте голый `--reset-values`: новый чарт по умолчанию содержит `shturvalReleaseVersion: 2.15.0`, `kubeVersion: 1.36.5`, новые теги etcd, pause и kube-vip. Для обновления только чарта оставьте прежние версии.
4. Предпочтительно `helm upgrade --reset-then-reuse-values` вместе с файлом старых values, затем `helm diff upgrade` (если плагин установлен) или `helm template` / `helm upgrade --dry-run`.
5. `shturvalReleaseVersion` меняйте только вместе с `platformUpgrade: true`. Иначе при живом кластере чарт останавливает рендер: смена `spec.releaseVersion` запускает обновление платформы. `helm template` и Argo CD не видят объекты кластера (`lookup` пустой), поэтому проверку нужно сделать до apply.
6. `enabledServices` и `disabledServices` у существующего ClusterConfig чарт не переписывает: webhook запрещает их менять, списки читаются из живого объекта.
7. `InfrastructureProvider` создаётся только если CRD уже есть (`infrastructureProvider.create: auto`) и объект с тем же именем не принадлежит другому релизу. Нативные секреты и аннотации `shturval.tech/*` чарт не удаляет: они нужны менеджмент-кластеру 2.14 и миграции 2.15.
8. Поле `services.disablesservices` — явный список. Значение `all` в ClusterConfig не работает (его понимает только REST API backend и нельзя совместить с `enabledServices`). Некритичный сервис, которого нет ни в одном списке и у которого режим по умолчанию `auto`, будет установлен.

Платформенное обновление клиентского кластера 2.14 → 2.15 делайте отдельно, через shturval-update / `platformUpgrade: true`, а не как побочный эффект `helm upgrade`.
