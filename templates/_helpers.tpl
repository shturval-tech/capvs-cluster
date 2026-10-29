{{/*
Expand the name of the chart.
*/}}
{{- define "capvs-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "capvs-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "capvs-cluster.labels" -}}
helm.sh/chart: {{ include "capvs-cluster.chart" . }}
{{ include "capvs-cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "capvs-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "capvs-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ClusterConfig file (base64)
*/}}
{{- define "capvs-cluster.clusterConfig" -}}
{{- tpl (.Files.Get .Values.clusterConfigFile) . | b64enc | quote }}
{{- end }}

{{/*
Default system container registry name in NCI (platform bootstrap).
Not user-configurable — always r.shturval.tech as in platform bootstrap.
*/}}
{{- define "capvs-cluster.defaultSystemRepo" -}}
r.shturval.tech
{{- end }}

{{/*
Материал ключа для encryption-at-rest (совпадает с Secret *-encryption-configuration).
*/}}
{{- define "capvs-cluster.encryptionKeyMaterial" -}}
{{- $secretName := printf "%s-%s" .Release.Name "encryption-configuration" -}}
{{- $existing := lookup "v1" "Secret" .Release.Name $secretName -}}
{{- if $existing -}}
{{- if regexMatch "^2\\.7\\.[0-9]$" .Values.shturvalReleaseVersion -}}
{{- index $existing.data "secret" | b64dec | b64dec -}}
{{- else -}}
{{- index $existing.data "secret" | b64dec -}}
{{- end -}}
{{- else -}}
{{- if .Values.etcd.encryptionSeed -}}
{{- if regexMatch "^2\\.7\\.[0-9]$" .Values.shturvalReleaseVersion -}}
{{- substr 0 32 (sha256sum (printf "capvs-enc-v27-%s:%s" (toString .Values.etcd.encryptionSeed) .Release.Name)) -}}
{{- else -}}
{{- substr 0 32 (sha256sum (printf "capvs-enc-v1-%s:%s" (toString .Values.etcd.encryptionSeed) .Release.Name)) -}}
{{- end -}}
{{- else -}}
{{- $cc := lookup "cluster.shturval.tech/v1beta1" "ClusterConfig" .Release.Name .Release.Name -}}
{{- if and $cc $cc.spec -}}
{{- /* Апгрейд существующего кластера: ключ не меняем. */ -}}
{{- if regexMatch "^2\\.7\\.[0-9]$" .Values.shturvalReleaseVersion -}}
{{- substr 0 32 (sha256sum (printf "capvs-enc-v27-%s" .Release.Name)) -}}
{{- else -}}
{{- substr 0 32 (sha256sum (printf "capvs-enc-v1-%s" .Release.Name)) -}}
{{- end -}}
{{- else -}}
{{- fail (printf "новый кластер %s: задайте etcd.encryptionSeed в values (случайная строка, например `openssl rand -base64 32`). Без seed шифрование etcd не будет безопасным." .Release.Name) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Значение data.secret (строка для поля Opaque Secret): base64 от материала, для 2.7 — двойная обёртка как в исходном чарте
*/}}
{{- define "capvs-cluster.encryptionSecretDataValue" -}}
{{- $K := include "capvs-cluster.encryptionKeyMaterial" . -}}
{{- if regexMatch "^2\\.7\\.[0-9]$" .Values.shturvalReleaseVersion -}}
{{- $K | b64enc | b64enc -}}
{{- else -}}
{{- $K | b64enc -}}
{{- end -}}
{{- end -}}

{{/*
EncryptionConfiguration YAML for NCI / kubeadm bootstrap (secure=true).
Uses the same key material as Secret *-encryption-configuration.
*/}}
{{- define "capvs-cluster.encryptionConfigurationYaml" -}}
---
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
    - secrets
    providers:
    - aescbc:
        keys:
          - name: key1
            secret: {{ include "capvs-cluster.encryptionKeyMaterial" . | b64enc }}
    - identity: {}
{{- end -}}

{{/*
Audit policy from chart template (values.auditPolicy.template).
*/}}
{{- define "capvs-cluster.auditPolicyYaml" -}}
---
{{ tpl (.Files.Get .Values.auditPolicy.template) . }}
{{- end -}}

{{/*
kube-vip static pod — readable template in conf/kube-vip.yaml
*/}}
{{- define "capvs-cluster.kubeVipYaml" -}}
{{- tpl (.Files.Get "conf/kube-vip.yaml") . -}}
{{- end -}}

{{/*
Generate nci.json (ShturvalInit) as base64-encoded JSON.
Usage: include "capvs-cluster.nci.json.b64" (dict "ctx" . "controlplane" true)
Source: conf/nci.yaml (override via values.nciFile).
*/}}
{{- define "capvs-cluster.nci.json.b64" -}}
{{- $ctx := .ctx -}}
{{- $nciFile := $ctx.Values.nciFile | default "conf/nci.yaml" -}}
{{- $nciCtx := dict
  "Values"       $ctx.Values
  "Files"        $ctx.Files
  "Release"      $ctx.Release
  "Chart"        $ctx.Chart
  "controlplane" .controlplane
-}}
{{- tpl ($ctx.Files.Get $nciFile) $nciCtx | fromYaml | toJson | b64enc -}}
{{- end }}

{{/*
External ETCD CA certificate
*/}}
{{- define "capvs-cluster.etcd.caCrt" -}}
{{- if .Values.etcd.external.caCrt }}
{{- .Files.Get .Values.etcd.external.caCrt | b64enc | quote }}
{{- end }}
{{- end }}

{{/*
External ETCD client certificate
*/}}
{{- define "capvs-cluster.etcd.apiCrt" -}}
{{- if .Values.etcd.external.apiCrt }}
{{- .Files.Get .Values.etcd.external.apiCrt | b64enc | quote }}
{{- end }}
{{- end }}

{{/*
External ETCD client key
*/}}
{{- define "capvs-cluster.etcd.apiKey" -}}
{{- if .Values.etcd.external.apiKey }}
{{- .Files.Get .Values.etcd.external.apiKey | b64enc | quote }}
{{- end }}
{{- end }}

{{/*
Adler-32 based numeric cluster id, used in ClusterConfig monitoring section
*/}}
{{- define "capvs-cluster.monitoringid" -}}
{{ adler32sum .Release.Name | int }}
{{- end }}

{{/*
Filename for a kubeadm patch in kubeadmPatches.directory.
*/}}
{{- define "capvs-cluster.kubeadmPatchFilename" -}}
{{- $name := .name -}}
{{- $patch := .patch | default dict -}}
{{- if $patch.filename -}}
{{- $patch.filename -}}
{{- else if eq $name "kubeapi" -}}
kube-apiserver.yaml
{{- else -}}
{{- printf "%s.yaml" $name -}}
{{- end -}}
{{- end -}}

{{- define "capvs-cluster.kubeadmPatchesEffective" -}}
{{- $kp := dict -}}
{{- range $k, $v := (.Values.kubeadmPatches | default dict) }}
{{- $_ := set $kp $k $v -}}
{{- end }}
{{- range $k, $v := (.Values.patch | default dict) }}
{{- if not (hasKey $kp $k) }}
{{- $_ := set $kp $k $v -}}
{{- end }}
{{- end }}
{{- $dir := index $kp "directory" | default "" -}}
{{- if not $dir }}
{{- $has := false -}}
{{- range $k, $v := $kp }}
{{- if and (kindIs "map" $v) $v.patchTemplate }}
{{- $has = true -}}
{{- end }}
{{- end }}
{{- if $has }}
{{- $_ := set $kp "directory" "/etc/kubernetes/manifests-pathes" -}}
{{- end }}
{{- end }}
{{- toYaml $kp -}}
{{- end -}}

{{- define "capvs-cluster.vipInterface" -}}
{{- $ni := .Values.nodeInit | default dict -}}
{{- $kv := $ni.kubevip | default dict -}}
{{- if $kv.interface -}}
{{- $kv.interface -}}
{{- else -}}
{{- $sv := .Values.shturval | default dict -}}
{{- $sv.vipInterface | default "eth0" -}}
{{- end -}}
{{- end -}}

{{- define "capvs-cluster.patchResources" -}}
{{- $kp := .root.Values.kubeadmPatches | default dict -}}
{{- $legacy := .root.Values.patch | default dict -}}
{{- $p := dict -}}
{{- if hasKey $kp .name -}}
{{- $p = index $kp .name | default dict -}}
{{- else if hasKey $legacy .name -}}
{{- $p = index $legacy .name | default dict -}}
{{- end -}}
{{- toYaml $p.resources -}}
{{- end -}}

{{- define "capvs-cluster.patch.kube-apiserver" -}}
{{- $kp := include "capvs-cluster.kubeadmPatchesEffective" . | fromYaml -}}
{{- $p := index $kp "kubeapi" | default dict -}}
{{- if $p.patchTemplate }}
{{- tpl (.Files.Get $p.patchTemplate) . | b64enc | quote }}
{{- end }}
{{- end }}

{{- define "capvs-cluster.patch.etcd" -}}
{{- $kp := include "capvs-cluster.kubeadmPatchesEffective" . | fromYaml -}}
{{- $p := index $kp "etcd" | default dict -}}
{{- if $p.patchTemplate }}
{{- tpl (.Files.Get $p.patchTemplate) . | b64enc | quote }}
{{- end }}
{{- end }}

{{/*
VSphereClusterIdentity имя (per-release по умолчанию = Release.Name)
*/}}
{{- define "capvs-cluster.capvs.identityName" -}}
{{- default .Release.Name .Values.capvs.identityName }}
{{- end }}

{{/*
Имя секрета с vCenter-креденшелами (в credentialsNamespace)
*/}}
{{- define "capvs-cluster.capvs.credentialsSecretName" -}}
{{- printf "%s-capvs-provider-secret" (include "capvs-cluster.capvs.identityName" .) }}
{{- end }}

{{/*
Формирует VSphereMachineTemplate .spec.template.spec для группы узлов.
Мерджит per-group переопределения с глобальными capvs-настройками.

Использование:
{{- include "capvs-cluster.vspheremachine.spec" (dict "group" .Values.master "root" .) | nindent 6 }}
*/}}
{{- define "capvs-cluster.vspheremachine.spec" -}}
{{- $group := .group | default dict -}}
{{- $root := .root -}}
{{- $capvs := $root.Values.capvs -}}
{{- $vm := merge (dict) ($group.vm | default dict) ($capvs.vm | default dict) -}}
{{- $network := $group.network | default $capvs.network -}}
cloneMode: {{ $group.cloneMode | default $capvs.cloneMode | quote }}
datacenter: {{ $group.datacenter | default $capvs.datacenter | quote }}
datastore: {{ $group.datastore | default $capvs.datastore | quote }}
diskGiB: {{ $vm.diskGiB }}
folder: {{ $group.folder | default $capvs.folder | quote }}
memoryMiB: {{ $vm.memoryMiB }}
network:
  devices:
{{ toYaml ($network.devices | default list) | indent 4 }}
numCPUs: {{ $vm.numCPUs }}
os: {{ $group.os | default $capvs.os | default "Linux" | quote }}
powerOffMode: {{ $group.powerOffMode | default $capvs.powerOffMode | quote }}
resourcePool: {{ $group.resourcePool | default $capvs.resourcePool | quote }}
server: {{ $group.server | default $capvs.server | quote }}
template: {{ $group.template | default (required (printf "capvs.template is required: укажите шаблон VM для группы %s или capvs.template" (default "group" $group.name)) $capvs.template) | quote }}
{{- with ($group.storagePolicyName | default $capvs.storagePolicyName) }}
storagePolicyName: {{ . | quote }}
{{- end }}
{{- with ($group.thumbprint | default $capvs.thumbprint) }}
thumbprint: {{ . | quote }}
{{- end }}
{{- $additionalDisks := $vm.additionalDisksGiB | default list }}
{{- if $additionalDisks }}
additionalDisksGiB:
{{ toYaml $additionalDisks | indent 2 }}
{{- end }}
{{- end }}

{{/*
Базовые apiserver extraArgs для Kubeadm.
Audit/encryption args only when secure=true.
*/}}
{{- define "capvs-cluster.apiserver" -}}
extraArgs:
{{- if .Values.secure }}
- name: audit-log-maxage
  value: "30"
- name: audit-log-maxbackup
  value: "10"
- name: audit-log-maxsize
  value: "100"
- name: audit-log-mode
  value: batch
- name: audit-log-path
  value: /var/log/kube-api-audit/audit.log
- name: audit-policy-file
  value: "{{ .Values.auditPolicy.location }}"
- name: encryption-provider-config
  value: /etc/kubernetes/secrets_encryption.yaml
{{- end }}
- name: authorization-mode
  value: Node,RBAC
- name: default-not-ready-toleration-seconds
  value: "30"
- name: default-unreachable-toleration-seconds
  value: "30"
- name: kubelet-certificate-authority
  value: /etc/kubernetes/pki/ca.crt
- name: profiling
  value: "false"
- name: request-timeout
  value: 60s
- name: tls-min-version
  value: VersionTLS13
{{- end }}

{{/*
controllerManager defaults
*/}}
{{- define "capvs-cluster.controllerManager" -}}
controllerManager:
  extraArgs:
  - name: bind-address
    value: 0.0.0.0
  - name: node-monitor-grace-period
    value: 20s
  - name: node-monitor-period
    value: 2s
  - name: profiling
    value: "false"
  - name: terminated-pod-gc-threshold
    value: "10"
  - name: tls-min-version
    value: VersionTLS13
{{- end }}

{{/*
scheduler defaults
*/}}
{{- define "capvs-cluster.scheduler" -}}
scheduler:
  extraArgs:
  - name: bind-address
    value: 0.0.0.0
  - name: profiling
    value: "false"
{{- end }}

{{/*
kubelet defaults (used in /etc/kubelet.yaml injection)
*/}}
{{- define "capvs-cluster.kubelet" -}}
serverTLSBootstrap: true
protectKernelDefaults: true
{{- end }}

{{/*
True if any workerNodes group has autoscaling.enabled.
*/}}
{{- define "capvs-cluster.autoscalingEnabled" -}}
{{- $enabled := false -}}
{{- range $k, $v := .Values.workerNodes -}}
{{- if and $v.autoscaling $v.autoscaling.enabled -}}
{{- $enabled = true -}}
{{- end -}}
{{- end -}}
{{- $enabled -}}
{{- end -}}

{{/*
Resolve scale params for a worker MachineDeployment group.
Input: dict "root" $ "name" <groupKey> "group" <groupValues>
Output (YAML): enabled, minSize, maxMachines (if enabled), replicas

При autoscaling.enabled чарт не выставляет MachineDeployment.spec.replicas
(см. machinedeployment.yaml) — иначе helm template / helm-drift всегда
показывают drift относительно живого значения, которым владеет cluster-autoscaler.
replicas из values при этом остаётся min-size;
фактический размер группы догоняет autoscaler (--enforce-node-group-min-size).
*/}}
{{- define "capvs-cluster.workerGroupScale" -}}
{{- $name := .name -}}
{{- $group := .group -}}
{{- $autoscaling := $group.autoscaling | default dict -}}
{{- $enabled := $autoscaling.enabled | default false -}}
{{- $minSize := $group.replicas -}}
{{- $replicas := $group.replicas -}}
{{- if $enabled -}}
{{- $_ := required (printf "workerNodes.%s.replicas is required when autoscaling.enabled" $name) $group.replicas -}}
{{- $_ := required (printf "workerNodes.%s.autoscaling.maxMachines is required when autoscaling.enabled" $name) $autoscaling.maxMachines -}}
{{- if gt (int $minSize) (int $autoscaling.maxMachines) -}}
{{- fail (printf "workerNodes.%s.replicas (%v) must be <= autoscaling.maxMachines (%v)" $name $minSize $autoscaling.maxMachines) -}}
{{- end -}}
{{- end -}}
enabled: {{ $enabled }}
minSize: {{ $minSize }}
{{- if $enabled }}
maxMachines: {{ $autoscaling.maxMachines }}
{{- end }}
replicas: {{ $replicas }}
{{- end -}}

{{/*
cluster-autoscaler image.
Тег из профиля релиза, не из kubeVersion: 2.15.0 — v1.36.1-325745, 2.14.x — v1.35.1.
Реестр — systemregistry. Полный образ переопределяется images.clusterAutoscaler.
*/}}
{{- define "capvs-cluster.clusterAutoscalerImage" -}}
{{- if and .Values.images .Values.images.clusterAutoscaler -}}
{{- .Values.images.clusterAutoscaler -}}
{{- else -}}
{{- $p := include "capvs-cluster.releaseProfile" . | fromYaml -}}
{{- $tag := $p.clusterAutoscalerTag | default (printf "v%s" (include "capvs-cluster.effectiveKubeVersion" .)) -}}
{{- printf "%s/autoscaling/cluster-autoscaler:%s" .Values.systemregistry $tag -}}
{{- end -}}
{{- end -}}

{{/*
kube-vip image for NCI.
images.kubeVip, иначе conf/releases, иначе nodeInit.kubevip.image.
*/}}
{{- define "capvs-cluster.kubeVipImage" -}}
{{- $images := .Values.images | default dict -}}
{{- if $images.kubeVip -}}
{{- $images.kubeVip -}}
{{- else -}}
{{- $p := include "capvs-cluster.releaseProfile" . | fromYaml -}}
{{- if $p.kubeVipImage -}}
{{- $p.kubeVipImage -}}
{{- else -}}
{{- $ni := .Values.nodeInit | default dict -}}
{{- $kv := $ni.kubevip | default dict -}}
{{- required "images.kubeVip (или профиль релиза, или nodeInit.kubevip.image) is required" $kv.image -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
pause image for NCI.
images.pause, иначе conf/releases, иначе nodeInit.pauseImage.
*/}}
{{- define "capvs-cluster.pauseImage" -}}
{{- $images := .Values.images | default dict -}}
{{- if $images.pause -}}
{{- $images.pause -}}
{{- else -}}
{{- $p := include "capvs-cluster.releaseProfile" . | fromYaml -}}
{{- if $p.pauseImage -}}
{{- $p.pauseImage -}}
{{- else -}}
{{- $ni := .Values.nodeInit | default dict -}}
{{- required "images.pause (или профиль релиза, или nodeInit.pauseImage) is required" $ni.pauseImage -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Профиль релиза: conf/releases/<shturvalReleaseVersion>.yaml.
Явные values важнее. Профиль нужен для полей, которых не было в 2.14 (CoreDNS),
и как запасной источник, если kubeVersion пустой.
*/}}
{{- define "capvs-cluster.releaseProfile" -}}
{{- $ver := .Values.shturvalReleaseVersion | default "2.15.0" -}}
{{- $path := printf "conf/releases/%s.yaml" $ver -}}
{{- $raw := .Files.Get $path -}}
{{- if not $raw -}}
{{- fail (printf "нет профиля релиза %s (%s). Ожидаются 2.14.0, 2.14.1 или 2.15.0" $ver $path) -}}
{{- end -}}
{{- $raw -}}
{{- end -}}

{{- define "capvs-cluster.effectiveKubeVersion" -}}
{{- if .Values.kubeVersion -}}
{{- .Values.kubeVersion -}}
{{- else -}}
{{- (include "capvs-cluster.releaseProfile" . | fromYaml).kubeVersion -}}
{{- end -}}
{{- end -}}

{{/*
Тег CoreDNS. Пустая строка для 2.14.x — блок dns в KubeadmControlPlane не пишется.
Переопределение: images.coreDNS.
*/}}
{{- define "capvs-cluster.coreDNSTag" -}}
{{- if and .Values.images (index .Values.images "coreDNS") -}}
{{- index .Values.images "coreDNS" -}}
{{- else -}}
{{- $p := include "capvs-cluster.releaseProfile" . | fromYaml -}}
{{- $p.coreDNSImageTag | default "" -}}
{{- end -}}
{{- end -}}

{{/*
Тег etcd. Явный etcd.local.imageTag важнее профиля релиза.
*/}}
{{- define "capvs-cluster.etcdImageTag" -}}
{{- $local := .Values.etcd.local | default dict -}}
{{- if $local.imageTag -}}
{{- $local.imageTag -}}
{{- else -}}
{{- $p := include "capvs-cluster.releaseProfile" . | fromYaml -}}
{{- required "etcd.local.imageTag (или etcdImageTag в профиле релиза) is required" $p.etcdImageTag -}}
{{- end -}}
{{- end -}}

{{/*
Списки сервисов.
Если ClusterConfig уже есть — берём списки из него (webhook запрещает правку).
Иначе values и, для controllerType=gateway, та же нормализация, что ApplyIngressControllerServiceLists.
*/}}
{{- define "capvs-cluster.serviceLists" -}}
{{- $enabled := .Values.services.enabledservices | default (list) -}}
{{- $disabled := .Values.services.disablesservices | default (list) -}}
{{- $cc := lookup "cluster.shturval.tech/v1beta1" "ClusterConfig" .Release.Name .Release.Name -}}
{{- if and $cc $cc.spec $cc.spec.systemServicesConfig -}}
{{- $ssc := $cc.spec.systemServicesConfig -}}
{{- if hasKey $ssc "enabledServices" -}}
{{- $enabled = $ssc.enabledServices | default (list) -}}
{{- end -}}
{{- if hasKey $ssc "disabledServices" -}}
{{- $disabled = $ssc.disabledServices | default (list) -}}
{{- end -}}
{{- else -}}
{{- $gateway := eq (.Values.ingressControllerType | default "nginx") "gateway" -}}
{{- $install := "shturval-ingress-controller" -}}
{{- $remove := "shturval-gateway-api-crds" -}}
{{- if $gateway -}}
{{- $install = "shturval-gateway-api-crds" -}}
{{- $remove = "shturval-ingress-controller" -}}
{{- end -}}
{{- $newEnabled := list -}}
{{- $hasInstall := false -}}
{{- range $enabled -}}
{{- if ne . $remove -}}
{{- $newEnabled = append $newEnabled . -}}
{{- if eq . $install }}{{- $hasInstall = true }}{{- end -}}
{{- end -}}
{{- end -}}
{{- if not $hasInstall -}}
{{- $newEnabled = append $newEnabled $install -}}
{{- end -}}
{{- $enabled = $newEnabled -}}
{{- $newDisabled := list -}}
{{- $hasRemove := false -}}
{{- range $disabled -}}
{{- if ne . $install -}}
{{- $newDisabled = append $newDisabled . -}}
{{- if eq . $remove }}{{- $hasRemove = true }}{{- end -}}
{{- end -}}
{{- end -}}
{{- if and $gateway (not $hasRemove) -}}
{{- $newDisabled = append $newDisabled $remove -}}
{{- end -}}
{{- $disabled = $newDisabled -}}
{{- end -}}
enabled:
{{ toYaml $enabled | nindent 2 }}
disabled:
{{ toYaml $disabled | nindent 2 }}
{{- end -}}

{{- define "capvs-cluster.validateIngressCerts" -}}
{{- $n := 0 -}}
{{- if .Values.ingressCert }}{{- $n = add $n 1 }}{{- end -}}
{{- if .Values.caCert }}{{- $n = add $n 1 }}{{- end -}}
{{- if .Values.acme }}
{{- if or .Values.acme.serverURL .Values.acme.rootCA .Values.acme.rootCABundle .Values.acme.email }}
{{- $n = add $n 1 }}
{{- end }}
{{- end -}}
{{- if .Values.vault }}
{{- if or .Values.vault.server .Values.vault.path .Values.vault.token .Values.vault.caBundle .Values.vault.rootCA }}
{{- $n = add $n 1 }}
{{- end }}
{{- end -}}
{{- if gt (int $n) 1 -}}
{{- fail "укажите только один способ сертификата ingress: ingressCert, caCert, acme или vault" -}}
{{- end -}}
{{- $ct := .Values.ingressControllerType | default "nginx" -}}
{{- if not (or (eq $ct "nginx") (eq $ct "gateway")) -}}
{{- fail "ingressControllerType должен быть nginx или gateway" -}}
{{- end -}}
{{- if and .Values.update .Values.update.strategy -}}
{{- if not (or (eq .Values.update.strategy "InPlace") (eq .Values.update.strategy "RollingUpdate")) -}}
{{- fail "update.strategy должен быть InPlace или RollingUpdate" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "capvs-cluster.assertCompatibleUpgrade" -}}
{{- $cc := lookup "cluster.shturval.tech/v1beta1" "ClusterConfig" .Release.Name .Release.Name -}}
{{- if and $cc $cc.spec $cc.spec.releaseVersion -}}
{{- $live := $cc.spec.releaseVersion | toString -}}
{{- $want := .Values.shturvalReleaseVersion | toString -}}
{{- if and $live (ne $live $want) (not .Values.platformUpgrade) -}}
{{- fail (printf "ClusterConfig %s уже имеет spec.releaseVersion=%s, в values указано %s. Смена версии запускает обновление платформы. Чтобы обновить только чарт, оставьте shturvalReleaseVersion=%s. Чтобы обновить платформу, задайте platformUpgrade=true. При helm template и в Argo CD lookup пустой, проверка не срабатывает — сверяйте values с живым ClusterConfig до apply." .Release.Name $live $want $live) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "capvs-cluster.preflight" -}}
{{- include "capvs-cluster.validateIngressCerts" . -}}
{{- include "capvs-cluster.assertCompatibleUpgrade" . -}}
{{- end -}}

{{/*
Хост vCenter без схемы и порта — ключ карты vcenter в values shturval-capvs-csi.
*/}}
{{- define "capvs-cluster.vcenterHost" -}}
{{- $host := .Values.capvs.server | toString -}}
{{- if contains "://" $host -}}
{{- $host = index (splitList "://" $host) 1 -}}
{{- end -}}
{{- index (splitList ":" $host) 0 -}}
{{- end -}}

{{- define "capvs-cluster.csiSecretName" -}}
vsphere-csi-ssc
{{- end -}}

{{- define "capvs-cluster.csiConfigYaml" -}}
global:
  config:
    global:
      insecure-flag: true
      cluster-id: {{ .Release.Name | quote }}
    storageclass:
      donotcheckdatastores: true
      expansion: true
      datastoreurl: {{ .Values.capvs.datastoreURL | default "" | quote }}
    vcenter:
      {{ include "capvs-cluster.vcenterHost" . | quote }}:
        server: {{ .Values.capvs.server | quote }}
        user: {{ .Values.capvs.username | quote }}
        password: {{ .Values.capvs.password | quote }}
        datacenters:
          - {{ .Values.capvs.datacenter | quote }}
{{- end -}}

{{- define "capvs-cluster.csiSecretWanted" -}}
{{- $root := . -}}
{{- $name := include "capvs-cluster.csiSecretName" $root -}}
{{- $on := false -}}
{{- if $root.Values.csi -}}
{{- range $root.Values.csi -}}
{{- if eq .serviceConfigName "shturval-capvs-csi" -}}
{{- if not .providerSecretRef -}}
{{- $on = true -}}
{{- else if and (eq .providerSecretRef.name $name) (or (not .providerSecretRef.namespace) (eq .providerSecretRef.namespace $root.Release.Name)) -}}
{{- $on = true -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- else if $root.Values.capvs.enableCSI -}}
{{- $on = true -}}
{{- end -}}
{{- if $on }}true{{ end -}}
{{- end -}}
