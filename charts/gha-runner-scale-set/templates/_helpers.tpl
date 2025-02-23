{{/*
Expand the name of the chart.
*/}}
{{- define "gha-runner-scale-set.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "gha-runner-scale-set.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "gha-runner-scale-set.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "gha-runner-scale-set.labels" -}}
helm.sh/chart: {{ include "gha-runner-scale-set.chart" . }}
{{ include "gha-runner-scale-set.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "gha-runner-scale-set.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gha-runner-scale-set.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "gha-runner-scale-set.githubsecret" -}}
  {{- if kindIs "string" .Values.githubConfigSecret }}
    {{- if not (empty .Values.githubConfigSecret) }}
{{- .Values.githubConfigSecret }}
    {{- else}}
{{- fail "Values.githubConfigSecret is required for setting auth with GitHub server." }}
    {{- end }}
  {{- else }}
{{- include "gha-runner-scale-set.fullname" . }}-github-secret
  {{- end }}
{{- end }}

{{- define "gha-runner-scale-set.noPermissionServiceAccountName" -}}
{{- include "gha-runner-scale-set.fullname" . }}-no-permission-service-account
{{- end }}

{{- define "gha-runner-scale-set.kubeModeRoleName" -}}
{{- include "gha-runner-scale-set.fullname" . }}-kube-mode-role
{{- end }}

{{- define "gha-runner-scale-set.kubeModeServiceAccountName" -}}
{{- include "gha-runner-scale-set.fullname" . }}-kube-mode-service-account
{{- end }}

{{- define "gha-runner-scale-set.dind-init-container" -}}
{{- range $i, $val := .Values.template.spec.containers }}
  {{- if eq $val.name "runner" }}
image: {{ $val.image }}
command: ["cp"]
args: ["-r", "-v", "/home/runner/externals/.", "/home/runner/tmpDir/"]
volumeMounts:
  - name: dind-externals
    mountPath: /home/runner/tmpDir
  {{- end }}
{{- end }}
{{- end }}

{{- define "gha-runner-scale-set.dind-container" -}}
image: docker:dind
securityContext:
  privileged: true
volumeMounts:
  - name: work
    mountPath: /home/runner/_work
  - name: dind-cert
    mountPath: /certs/client
  - name: dind-externals
    mountPath: /home/runner/externals
{{- end }}

{{- define "gha-runner-scale-set.dind-volume" -}}
- name: dind-cert
  emptyDir: {}
- name: dind-externals
  emptyDir: {}
{{- end }}

{{- define "gha-runner-scale-set.tls-volume" -}}
- name: github-server-tls-cert
  configMap:
    name: {{ .certificateFrom.configMapKeyRef.name }}
    items:
      - key: {{ .certificateFrom.configMapKeyRef.key }}
        path: {{ .certificateFrom.configMapKeyRef.key }}
{{- end }}

{{- define "gha-runner-scale-set.dind-work-volume" -}}
{{- $createWorkVolume := 1 }}
  {{- range $i, $volume := .Values.template.spec.volumes }}
    {{- if eq $volume.name "work" }}
      {{- $createWorkVolume = 0 }}
- {{ $volume | toYaml | nindent 2 }}
    {{- end }}
  {{- end }}
  {{- if eq $createWorkVolume 1 }}
- name: work
  emptyDir: {}
  {{- end }}
{{- end }}

{{- define "gha-runner-scale-set.kubernetes-mode-work-volume" -}}
{{- $createWorkVolume := 1 }}
  {{- range $i, $volume := .Values.template.spec.volumes }}
    {{- if eq $volume.name "work" }}
      {{- $createWorkVolume = 0 }}
- {{ $volume | toYaml | nindent 2 }}
    {{- end }}
  {{- end }}
  {{- if eq $createWorkVolume 1 }}
- name: work
  ephemeral:
    volumeClaimTemplate:
      spec:
        {{- .Values.containerMode.kubernetesModeWorkVolumeClaim | toYaml | nindent 8 }}
  {{- end }}
{{- end }}

{{- define "gha-runner-scale-set.non-work-volumes" -}}
  {{- range $i, $volume := .Values.template.spec.volumes }}
    {{- if ne $volume.name "work" }}
- {{ $volume | toYaml | nindent 2 }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "gha-runner-scale-set.non-runner-containers" -}}
  {{- range $i, $container := .Values.template.spec.containers }}
    {{- if ne $container.name "runner" }}
- {{ $container | toYaml | nindent 2 }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "gha-runner-scale-set.non-runner-non-dind-containers" -}}
  {{- range $i, $container := .Values.template.spec.containers }}
    {{- if and (ne $container.name "runner") (ne $container.name "dind") }}
- {{ $container | toYaml | nindent 2 }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "gha-runner-scale-set.dind-runner-container" -}}
{{- $tlsConfig := (default (dict) .Values.githubServerTLS) }}
{{- range $i, $container := .Values.template.spec.containers }}
  {{- if eq $container.name "runner" }}
    {{- range $key, $val := $container }}
      {{- if and (ne $key "env") (ne $key "volumeMounts") (ne $key "name") }}
{{ $key }}: {{ $val | toYaml | nindent 2 }}
      {{- end }}
    {{- end }}
    {{- $setDockerHost := 1 }}
    {{- $setDockerTlsVerify := 1 }}
    {{- $setDockerCertPath := 1 }}
    {{- $setRunnerWaitDocker := 1 }}
    {{- $setNodeExtraCaCerts := 0 }}
    {{- $setRunnerUpdateCaCerts := 0 }}
    {{- if $tlsConfig.runnerMountPath }}
      {{- $setNodeExtraCaCerts = 1 }}
      {{- $setRunnerUpdateCaCerts = 1 }}
    {{- end }}
env:
    {{- with $container.env }}
      {{- range $i, $env := . }}
        {{- if eq $env.name "DOCKER_HOST" }}
          {{- $setDockerHost = 0 }}
        {{- end }}
        {{- if eq $env.name "DOCKER_TLS_VERIFY" }}
          {{- $setDockerTlsVerify = 0 }}
        {{- end }}
        {{- if eq $env.name "DOCKER_CERT_PATH" }}
          {{- $setDockerCertPath = 0 }}
        {{- end }}
        {{- if eq $env.name "RUNNER_WAIT_FOR_DOCKER_IN_SECONDS" }}
          {{- $setRunnerWaitDocker = 0 }}
        {{- end }}
        {{- if eq $env.name "NODE_EXTRA_CA_CERTS" }}
          {{- $setNodeExtraCaCerts = 0 }}
        {{- end }}
        {{- if eq $env.name "RUNNER_UPDATE_CA_CERTS" }}
          {{- $setRunnerUpdateCaCerts = 0 }}
        {{- end }}
  - {{ $env | toYaml | nindent 4 }}
      {{- end }}
    {{- end }}
    {{- if $setDockerHost }}
  - name: DOCKER_HOST
    value: tcp://localhost:2376
    {{- end }}
    {{- if $setDockerTlsVerify }}
  - name: DOCKER_TLS_VERIFY
    value: "1"
    {{- end }}
    {{- if $setDockerCertPath }}
  - name: DOCKER_CERT_PATH
    value: /certs/client
    {{- end }}
    {{- if $setRunnerWaitDocker }}
  - name: RUNNER_WAIT_FOR_DOCKER_IN_SECONDS
    value: "120"
    {{- end }}
    {{- if $setNodeExtraCaCerts }}
  - name: NODE_EXTRA_CA_CERTS
    value: {{ clean (print $tlsConfig.runnerMountPath "/" $tlsConfig.certificateFrom.configMapKeyRef.key) }}
    {{- end }}
    {{- if $setRunnerUpdateCaCerts }}
  - name: RUNNER_UPDATE_CA_CERTS
    value: "1"
    {{- end }}
    {{- $mountWork := 1 }}
    {{- $mountDindCert := 1 }}
    {{- $mountGitHubServerTLS := 0 }}
    {{- if $tlsConfig.runnerMountPath }}
      {{- $mountGitHubServerTLS = 1 }}
    {{- end }}
volumeMounts:
    {{- with $container.volumeMounts }}
      {{- range $i, $volMount := . }}
        {{- if eq $volMount.name "work" }}
          {{- $mountWork = 0 }}
        {{- end }}
        {{- if eq $volMount.name "dind-cert" }}
          {{- $mountDindCert = 0 }}
        {{- end }}
        {{- if eq $volMount.name "github-server-tls-cert" }}
          {{- $mountGitHubServerTLS = 0 }}
        {{- end }}
  - {{ $volMount | toYaml | nindent 4 }}
      {{- end }}
    {{- end }}
    {{- if $mountWork }}
  - name: work
    mountPath: /home/runner/_work
    {{- end }}
    {{- if $mountDindCert }}
  - name: dind-cert
    mountPath: /certs/client
    readOnly: true
    {{- end }}
    {{- if $mountGitHubServerTLS }}
  - name: github-server-tls-cert
    mountPath: {{ clean (print $tlsConfig.runnerMountPath "/" $tlsConfig.certificateFrom.configMapKeyRef.key) }}
    subPath: {{ $tlsConfig.certificateFrom.configMapKeyRef.key }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "gha-runner-scale-set.kubernetes-mode-runner-container" -}}
{{- $tlsConfig := (default (dict) .Values.githubServerTLS) }}
{{- range $i, $container := .Values.template.spec.containers }}
  {{- if eq $container.name "runner" }}
    {{- range $key, $val := $container }}
      {{- if and (ne $key "env") (ne $key "volumeMounts") (ne $key "name") }}
{{ $key }}: {{ $val | toYaml | nindent 2 }}
      {{- end }}
    {{- end }}
    {{- $setContainerHooks := 1 }}
    {{- $setPodName := 1 }}
    {{- $setRequireJobContainer := 1 }}
    {{- $setNodeExtraCaCerts := 0 }}
    {{- $setRunnerUpdateCaCerts := 0 }}
    {{- if $tlsConfig.runnerMountPath }}
      {{- $setNodeExtraCaCerts = 1 }}
      {{- $setRunnerUpdateCaCerts = 1 }}
    {{- end }}
env:
    {{- with $container.env }}
      {{- range $i, $env := . }}
        {{- if eq $env.name "ACTIONS_RUNNER_CONTAINER_HOOKS" }}
          {{- $setContainerHooks = 0 }}
        {{- end }}
        {{- if eq $env.name "ACTIONS_RUNNER_POD_NAME" }}
          {{- $setPodName = 0 }}
        {{- end }}
        {{- if eq $env.name "ACTIONS_RUNNER_REQUIRE_JOB_CONTAINER" }}
          {{- $setRequireJobContainer = 0 }}
        {{- end }}
        {{- if eq $env.name "NODE_EXTRA_CA_CERTS" }}
          {{- $setNodeExtraCaCerts = 0 }}
        {{- end }}
        {{- if eq $env.name "RUNNER_UPDATE_CA_CERTS" }}
          {{- $setRunnerUpdateCaCerts = 0 }}
        {{- end }}
  - {{ $env | toYaml | nindent 4 }}
      {{- end }}
    {{- end }}
    {{- if $setContainerHooks }}
  - name: ACTIONS_RUNNER_CONTAINER_HOOKS
    value: /home/runner/k8s/index.js
    {{- end }}
    {{- if $setPodName }}
  - name: ACTIONS_RUNNER_POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
    {{- end }}
    {{- if $setRequireJobContainer }}
  - name: ACTIONS_RUNNER_REQUIRE_JOB_CONTAINER
    value: "true"
    {{- end }}
    {{- if $setNodeExtraCaCerts }}
  - name: NODE_EXTRA_CA_CERTS
    value: {{ clean (print $tlsConfig.runnerMountPath "/" $tlsConfig.certificateFrom.configMapKeyRef.key) }}
    {{- end }}
    {{- if $setRunnerUpdateCaCerts }}
  - name: RUNNER_UPDATE_CA_CERTS
    value: "1"
    {{- end }}
    {{- $mountWork := 1 }}
    {{- $mountGitHubServerTLS := 0 }}
    {{- if $tlsConfig.runnerMountPath }}
      {{- $mountGitHubServerTLS = 1 }}
    {{- end }}
volumeMounts:
    {{- with $container.volumeMounts }}
      {{- range $i, $volMount := . }}
        {{- if eq $volMount.name "work" }}
          {{- $mountWork = 0 }}
        {{- end }}
        {{- if eq $volMount.name "github-server-tls-cert" }}
          {{- $mountGitHubServerTLS = 0 }}
        {{- end }}
  - {{ $volMount | toYaml | nindent 4 }}
      {{- end }}
    {{- end }}
    {{- if $mountWork }}
  - name: work
    mountPath: /home/runner/_work
    {{- end }}
    {{- if $mountGitHubServerTLS }}
  - name: github-server-tls-cert
    mountPath: {{ clean (print $tlsConfig.runnerMountPath "/" $tlsConfig.certificateFrom.configMapKeyRef.key) }}
    subPath: {{ $tlsConfig.certificateFrom.configMapKeyRef.key }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "gha-runner-scale-set.default-mode-runner-containers" -}}
{{- $tlsConfig := (default (dict) .Values.githubServerTLS) }}
{{- range $i, $container := .Values.template.spec.containers }}
{{- if ne $container.name "runner" }}
- {{ $container | toYaml | nindent 2 }}
{{- else }}
- name: {{ $container.name }}
  {{- range $key, $val := $container }}
    {{- if and (ne $key "env") (ne $key "volumeMounts") (ne $key "name") }}
  {{ $key }}: {{ $val | toYaml | nindent 4 }}
    {{- end }}
  {{- end }}
  {{- $setNodeExtraCaCerts := 0 }}
  {{- $setRunnerUpdateCaCerts := 0 }}
  {{- if $tlsConfig.runnerMountPath }}
    {{- $setNodeExtraCaCerts = 1 }}
    {{- $setRunnerUpdateCaCerts = 1 }}
  {{- end }}
  env:
    {{- with $container.env }}
      {{- range $i, $env := . }}
        {{- if eq $env.name "NODE_EXTRA_CA_CERTS" }}
          {{- $setNodeExtraCaCerts = 0 }}
        {{- end }}
        {{- if eq $env.name "RUNNER_UPDATE_CA_CERTS" }}
          {{- $setRunnerUpdateCaCerts = 0 }}
        {{- end }}
    - {{ $env | toYaml | nindent 6 }}
      {{- end }}
    {{- end }}
    {{- if $setNodeExtraCaCerts }}
    - name: NODE_EXTRA_CA_CERTS
      value: {{ clean (print $tlsConfig.runnerMountPath "/" $tlsConfig.certificateFrom.configMapKeyRef.key) }}
    {{- end }}
    {{- if $setRunnerUpdateCaCerts }}
    - name: RUNNER_UPDATE_CA_CERTS
      value: "1"
    {{- end }}
    {{- $mountGitHubServerTLS := 0 }}
    {{- if $tlsConfig.runnerMountPath }}
      {{- $mountGitHubServerTLS = 1 }}
    {{- end }}
  volumeMounts:
    {{- with $container.volumeMounts }}
      {{- range $i, $volMount := . }}
        {{- if eq $volMount.name "github-server-tls-cert" }}
          {{- $mountGitHubServerTLS = 0 }}
        {{- end }}
    - {{ $volMount | toYaml | nindent 6 }}
      {{- end }}
    {{- end }}
    {{- if $mountGitHubServerTLS }}
    - name: github-server-tls-cert
      mountPath: {{ clean (print $tlsConfig.runnerMountPath "/" $tlsConfig.certificateFrom.configMapKeyRef.key) }}
      subPath: {{ $tlsConfig.certificateFrom.configMapKeyRef.key }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{- define "gha-runner-scale-set.managerRoleName" -}}
{{- include "gha-runner-scale-set.fullname" . }}-manager-role
{{- end }}

{{- define "gha-runner-scale-set.managerRoleBinding" -}}
{{- include "gha-runner-scale-set.fullname" . }}-manager-role-binding
{{- end }}

{{- define "gha-runner-scale-set.managerServiceAccountName" -}}
{{- $searchControllerDeployment := 1 }}
{{- if .Values.controllerServiceAccount }}
  {{- if .Values.controllerServiceAccount.name }}
    {{- $searchControllerDeployment = 0 }}
{{- .Values.controllerServiceAccount.name }}
  {{- end }}
{{- end }}
{{- if eq $searchControllerDeployment 1 }}
  {{- $multiNamespacesCounter := 0 }}
  {{- $singleNamespaceCounter := 0 }}
  {{- $controllerDeployment := dict }}
  {{- $singleNamespaceControllerDeployments := dict }}
  {{- $managerServiceAccountName := "" }}
  {{- range $index, $deployment := (lookup "apps/v1" "Deployment" "" "").items }}
    {{- if kindIs "map" $deployment.metadata.labels }}
      {{- if eq (get $deployment.metadata.labels "app.kubernetes.io/part-of") "gha-runner-scale-set-controller" }}
        {{- if hasKey $deployment.metadata.labels "actions.github.com/controller-watch-single-namespace" }}
          {{- $singleNamespaceCounter = add $singleNamespaceCounter 1 }}
          {{- $_ := set $singleNamespaceControllerDeployments (get $deployment.metadata.labels "actions.github.com/controller-watch-single-namespace") $deployment}}
        {{- else }}
          {{- $multiNamespacesCounter = add $multiNamespacesCounter 1 }}
          {{- $controllerDeployment = $deployment }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if and (eq $multiNamespacesCounter 0) (eq $singleNamespaceCounter 0) }}
    {{- fail "No gha-runner-scale-set-controller deployment found using label (app.kubernetes.io/part-of=gha-runner-scale-set-controller). Consider setting controllerServiceAccount.name in values.yaml to be explicit if you think the discovery is wrong." }}
  {{- end }}
  {{- if and (gt $multiNamespacesCounter 0) (gt $singleNamespaceCounter 0) }}
    {{- fail "Found both gha-runner-scale-set-controller installed with flags.watchSingleNamespace set and unset in cluster, this is not supported. Consider setting controllerServiceAccount.name in values.yaml to be explicit if you think the discovery is wrong." }}
  {{- end }}
  {{- if gt $multiNamespacesCounter 1 }}
    {{- fail "More than one gha-runner-scale-set-controller deployment found using label (app.kubernetes.io/part-of=gha-runner-scale-set-controller). Consider setting controllerServiceAccount.name in values.yaml to be explicit if you think the discovery is wrong." }}
  {{- end }}
  {{- if eq $multiNamespacesCounter 1 }}
    {{- with $controllerDeployment.metadata }}
      {{- $managerServiceAccountName = (get $controllerDeployment.metadata.labels "actions.github.com/controller-service-account-name") }}
    {{- end }}
  {{- else if gt $singleNamespaceCounter 0 }}
    {{- if hasKey $singleNamespaceControllerDeployments .Release.Namespace }}
      {{- $controllerDeployment = get $singleNamespaceControllerDeployments .Release.Namespace }}
      {{- with $controllerDeployment.metadata }}
        {{- $managerServiceAccountName = (get $controllerDeployment.metadata.labels "actions.github.com/controller-service-account-name") }}
      {{- end }}
    {{- else }}
      {{- fail "No gha-runner-scale-set-controller deployment that watch this namespace found using label (actions.github.com/controller-watch-single-namespace). Consider setting controllerServiceAccount.name in values.yaml to be explicit if you think the discovery is wrong." }}
    {{- end }}
  {{- end }}
  {{- if eq $managerServiceAccountName "" }}
    {{- fail "No service account name found for gha-runner-scale-set-controller deployment using label (actions.github.com/controller-service-account-name), consider setting controllerServiceAccount.name in values.yaml to be explicit if you think the discovery is wrong." }}
  {{- end }}
{{- $managerServiceAccountName }}
{{- end }}
{{- end }}

{{- define "gha-runner-scale-set.managerServiceAccountNamespace" -}}
{{- $searchControllerDeployment := 1 }}
{{- if .Values.controllerServiceAccount }}
  {{- if .Values.controllerServiceAccount.namespace }}
    {{- $searchControllerDeployment = 0 }}
{{- .Values.controllerServiceAccount.namespace }}
  {{- end }}
{{- end }}
{{- if eq $searchControllerDeployment 1 }}
  {{- $multiNamespacesCounter := 0 }}
  {{- $singleNamespaceCounter := 0 }}
  {{- $controllerDeployment := dict }}
  {{- $singleNamespaceControllerDeployments := dict }}
  {{- $managerServiceAccountNamespace := "" }}
  {{- range $index, $deployment := (lookup "apps/v1" "Deployment" "" "").items }}
    {{- if kindIs "map" $deployment.metadata.labels }}
      {{- if eq (get $deployment.metadata.labels "app.kubernetes.io/part-of") "gha-runner-scale-set-controller" }}
        {{- if hasKey $deployment.metadata.labels "actions.github.com/controller-watch-single-namespace" }}
          {{- $singleNamespaceCounter = add $singleNamespaceCounter 1 }}
          {{- $_ := set $singleNamespaceControllerDeployments (get $deployment.metadata.labels "actions.github.com/controller-watch-single-namespace") $deployment}}
        {{- else }}
          {{- $multiNamespacesCounter = add $multiNamespacesCounter 1 }}
          {{- $controllerDeployment = $deployment }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if and (eq $multiNamespacesCounter 0) (eq $singleNamespaceCounter 0) }}
    {{- fail "No gha-runner-scale-set-controller deployment found using label (app.kubernetes.io/part-of=gha-runner-scale-set-controller). Consider setting controllerServiceAccount.name in values.yaml to be explicit if you think the discovery is wrong." }}
  {{- end }}
  {{- if and (gt $multiNamespacesCounter 0) (gt $singleNamespaceCounter 0) }}
    {{- fail "Found both gha-runner-scale-set-controller installed with flags.watchSingleNamespace set and unset in cluster, this is not supported. Consider setting controllerServiceAccount.name in values.yaml to be explicit if you think the discovery is wrong." }}
  {{- end }}
  {{- if gt $multiNamespacesCounter 1 }}
    {{- fail "More than one gha-runner-scale-set-controller deployment found using label (app.kubernetes.io/part-of=gha-runner-scale-set-controller). Consider setting controllerServiceAccount.name in values.yaml to be explicit if you think the discovery is wrong." }}
  {{- end }}
  {{- if eq $multiNamespacesCounter 1 }}
    {{- with $controllerDeployment.metadata }}
      {{- $managerServiceAccountNamespace = (get $controllerDeployment.metadata.labels "actions.github.com/controller-service-account-namespace") }}
    {{- end }}
  {{- else if gt $singleNamespaceCounter 0 }}
    {{- if hasKey $singleNamespaceControllerDeployments .Release.Namespace }}
      {{- $controllerDeployment = get $singleNamespaceControllerDeployments .Release.Namespace }}
      {{- with $controllerDeployment.metadata }}
        {{- $managerServiceAccountNamespace = (get $controllerDeployment.metadata.labels "actions.github.com/controller-service-account-namespace") }}
      {{- end }}
    {{- else }}
      {{- fail "No gha-runner-scale-set-controller deployment that watch this namespace found using label (actions.github.com/controller-watch-single-namespace). Consider setting controllerServiceAccount.name in values.yaml to be explicit if you think the discovery is wrong." }}
    {{- end }}
  {{- end }}
  {{- if eq $managerServiceAccountNamespace "" }}
    {{- fail "No service account namespace found for gha-runner-scale-set-controller deployment using label (actions.github.com/controller-service-account-namespace), consider setting controllerServiceAccount.name in values.yaml to be explicit if you think the discovery is wrong." }}
  {{- end }}
{{- $managerServiceAccountNamespace }}
{{- end }}
{{- end }}
