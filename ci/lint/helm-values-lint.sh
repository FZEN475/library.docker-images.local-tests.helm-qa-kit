source /ci/tbc/tbc-helm.sh
mkdir -p -m 777 reports

TBC_ENVSUBST_ENCODING=jsonstr tbc_envsubst "$ENV_VALUES" > generated-values.yml
yamllint -d "$HELM_YAMLLINT_CONFIG" $HELM_YAMLLINT_ARGS generated-values.yml
cat generated-values.yml | tee reports/generated-values.yml