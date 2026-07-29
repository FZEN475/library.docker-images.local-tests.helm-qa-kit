source /ci/tbc/tbc-helm.sh
mkdir -p -m 777 reports

if [ -f "$HELM_CHART_DIR/Chart.yaml" ]
then
  helm $HELM_DEPENDENCY_ARGS $HELM_CHART_DIR \
    2>&1 | tee reports/dependency.log
  helm ${TRACE+--debug} $HELM_LINT_ARGS $HELM_CHART_DIR \
    2>&1 | tee reports/lint.log
else
  log_error "Remote repo not linted"
fi
