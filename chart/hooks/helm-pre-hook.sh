source /ci/tbc/tbc-helm.sh
log_info "helm-pre-hook.sh"

if [ -f "$HELM_CHART_DIR/Chart.yaml" ]
then
  helm ${TRACE+--debug} plugin install "${HELM_CHART_DIR}post-renderer-plugin" || true
else
  log_warn "Scip plugin install!"
fi
