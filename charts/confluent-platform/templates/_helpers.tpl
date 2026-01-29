{{/*
Expand the name of the chart.
*/}}
{{- define "confluent-platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "confluent-platform.fullname" -}}
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
{{- define "confluent-platform.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "confluent-platform.labels" -}}
helm.sh/chart: {{ include "confluent-platform.chart" . }}
{{ include "confluent-platform.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: confluent-platform
{{- end }}

{{/*
Selector labels
*/}}
{{- define "confluent-platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "confluent-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Namespace helper - use Release.Namespace
*/}}
{{- define "confluent-platform.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{/*
Schema Registry URL helper
*/}}
{{- define "confluent-platform.schemaRegistryUrl" -}}
http://schemaregistry.{{ include "confluent-platform.namespace" . }}.svc.cluster.local:8081
{{- end }}

{{/*
Kafka bootstrap endpoint helper
*/}}
{{- define "confluent-platform.kafkaBootstrap" -}}
kafka:9071
{{- end }}
