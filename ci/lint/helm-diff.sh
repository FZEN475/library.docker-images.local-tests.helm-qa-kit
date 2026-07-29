source /ci/tbc/tbc-helm.sh
mkdir -p -m 777 reports

helm_plugin_diff false

helm_diff | tee reports/diff.yaml
