#!/usr/bin/env ash

export HELM_CHART_DIR=$HELM_DEPLOY_CHART
export CI_PROJECT_DIR="/source"
export HELM_DATA_HOME="/source/.cache"
export HELM_CACHE_HOME="$CI_PROJECT_DIR/.cache/helm"
export HELM_CONFIG_HOME="$CI_PROJECT_DIR/.config/helm"
export CI_REGISTRY=$(echo "${HELM_PUBLISH_URL#oci://}" | cut -d'/' -f1)

source /ci/tbc/tbc-helm.sh

# .helm-base:
install_ca_certs "$([[ -f "$CUSTOM_CA_CERTS" ]] && cat "$CUSTOM_CA_CERTS")"

export -p > /tmp/current_env.sh
log_info "---> configure_docker_auth <---"
configure_docker_auth $CI_REGISTRY $GITLAB_USER $GITLAB_TOKEN
log_info "---> add_helm_repositories <---"
add_helm_repositories

log_info "---> helm-pre-hook <---"
if [ "$PRE_HOOK" = "true" ]; then
    run_subprocess /ci/hook/helm-pre-hook.sh
else
    log_info "Действие пропущено: PRE_HOOK='$PRE_HOOK'"
fi

log_info "---> helm-lint <---"
if [ "$HELM_LINT" = "true" ]; then
    run_subprocess /ci/lint/helm-lint.sh
else
    log_info "Действие пропущено: HELM_LINT='$HELM_LINT'"
fi

log_info "---> helm-values-lint <---"
if [ "$HELM_VALUES_LINT" = "true" ]; then
    run_subprocess /ci/lint/helm-values-lint.sh
else
    log_info "Действие пропущено: HELM_VALUES_LINT='$HELM_VALUES_LINT'"
fi

log_info "---> helm-template <---"
if [ "$HELM_TEMPLATE" = "true" ]; then
    run_subprocess /ci/lint/helm-template.sh
else
    log_info "Действие пропущено: HELM_TEMPLATE='$HELM_TEMPLATE'"
fi

log_info "---> helm-score <---"
if [ "$HELM_SCORE" = "true" ]; then
    run_subprocess /ci/lint/helm-score.sh
else
    log_info "Действие пропущено: HELM_SCORE='$HELM_SCORE'"
fi

log_info "---> helm-diff <---"
if [ "$HELM_DIFF" = "true" ]; then
    run_subprocess /ci/lint/helm-diff.sh
else
    log_info "Действие пропущено: HELM_DIFF='$HELM_DIFF'"
fi

log_info "---> helm-delete <---"
if [ "$HELM_DELETE" = "true" ]; then
    run_subprocess /ci/deploy/helm-delete.sh
else
    log_info "Действие пропущено: HELM_DELETE='$HELM_DELETE'"
fi

log_info "---> helm-install <---"
if [ "$HELM_INSTALL" = "true" ]; then
    run_subprocess /ci/deploy/helm-install.sh
else
    log_info "Действие пропущено: HELM_INSTALL='$HELM_INSTALL'"
fi

log_info "---> helm-test <---"
if [ "$HELM_TEST" = "true" ]; then
    run_subprocess /ci/deploy/helm-test.sh
else
    log_info "Действие пропущено: HELM_TEST='$HELM_TEST'"
fi

log_info "---> helm-package <---"
if [ "$HELM_PACKAGE" = "true" ]; then
    run_subprocess /ci/publish/helm-package.sh
else
    log_info "Действие пропущено: HELM_PACKAGE='$HELM_PACKAGE'"
fi

log_info "---> helm-publish <---"
if [ "$HELM_PACKAGE" = "true" ] && [ "$HELM_PUBLISH" = "true" ]; then
    run_subprocess /ci/publish/helm-publish.sh
else
    log_info "Действие пропущено: HELM_PACKAGE='$HELM_PACKAGE', HELM_PUBLISH='$HELM_PUBLISH'"
fi

#log_info "---> cosign <---"
#if [ "$COSIGN" = "true" ] && [ "$HELM_PACKAGE" = "true" ] && [ "$HELM_PUBLISH" = "true" ]; then
#    run_subprocess /ci/sign/cosign.sh
#else
#    log_info "Действие пропущено: COSIGN='$COSIGN', HELM_PACKAGE='$HELM_PACKAGE', HELM_PUBLISH='$HELM_PUBLISH'"
#fi