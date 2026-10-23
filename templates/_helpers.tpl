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
{{- else if regexMatch "^2\\.7\\.[0-9]$" .Values.shturvalReleaseVersion -}}
{{- substr 0 32 (sha256sum (printf "capvs-enc-v27-%s" .Release.Name)) -}}
{{- else -}}
{{- substr 0 32 (sha256sum (printf "capvs-enc-v1-%s" .Release.Name)) -}}
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
template: {{ $group.template | default $capvs.template | quote }}
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
cluster-autoscaler image: <systemregistry>/autoscaling/cluster-autoscaler:v<kubeVersion>
Override via images.clusterAutoscaler when needed.
*/}}
{{- define "capvs-cluster.clusterAutoscalerImage" -}}
{{- if and .Values.images .Values.images.clusterAutoscaler -}}
{{- .Values.images.clusterAutoscaler -}}
{{- else -}}
{{- printf "%s/autoscaling/cluster-autoscaler:v%s" .Values.systemregistry .Values.kubeVersion -}}
{{- end -}}
{{- end -}}

{{/*
kube-vip image for NCI (values.images.kubeVip)
*/}}
{{- define "capvs-cluster.kubeVipImage" -}}
{{- $images := .Values.images | default dict -}}
{{- required "images.kubeVip is required" $images.kubeVip -}}
{{- end -}}

{{/*
pause image for NCI (values.images.pause)
*/}}
{{- define "capvs-cluster.pauseImage" -}}
{{- $images := .Values.images | default dict -}}
{{- required "images.pause is required" $images.pause -}}
{{- end -}}
