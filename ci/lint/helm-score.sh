source /ci/tbc/tbc-helm.sh
mkdir -p -m 777 reports

if [ -f "$HELM_CHART_DIR/Chart.yaml" ]
then
  helm_package=$HELM_CHART_DIR
elif [ ! -z "${HELM_DEPLOY_CHART}" ]
then
  helm_package=$HELM_DEPLOY_CHART
else
  log_error "You need at least one Chart.yaml or external deploy chart reference"
  exit 1
fi

TBC_ENVSUBST_ENCODING=jsonstr tbc_envsubst "${HELM_COMMON_VALUES:-/dev/null}" > generated-values-common.yml
TBC_ENVSUBST_ENCODING=jsonstr tbc_envsubst "$ENV_VALUES" > generated-values-env.yml
helm template ${HELM_TEMPLATE_ARGS} $helm_package \
  ${HELM_K8S_VERSION:+--kube-version "$HELM_K8S_VERSION"} \
  --values generated-values-common.yml \
  --values generated-values-env.yml \
  | kube-score score \
    ${HELM_K8S_VERSION:+--kubernetes-version "$HELM_K8S_VERSION"} ${HELM_KUBE_SCORE_ARGS} - \
    | tee reports/kube-score.json

