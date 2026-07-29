
{{- define "standard.standardLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
release: {{ .Release.Name }}
heritage: "{{ .Release.Service }}"
{{- end -}}

{{- define "standard.standardSelectorLabels" -}}
app.kubernetes.io/name: "{{ .Release.Name }}"
release: "{{ .Release.Name }}"
{{- end -}}