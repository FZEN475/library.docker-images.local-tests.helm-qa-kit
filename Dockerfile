FROM docker.io/alpine/helm:4@sha256:b97ba4f9b27fe7af16ee3d37e6815783c9d4a51289b6240a9024ec471611ae9b AS helm

ARG HELM_CHART_DIR="./chart"
ARG KUBE_SCORE_VERSION="1.20.0"
ARG ORAS_VERSION="1.2.0"

ENV HELM_CHART_DIR=$HELM_CHART_DIR \
    HELM_DEPENDENCY_ARGS="dependency update" \
    HELM_LINT_ARGS="lint --strict" \
    HELM_YAMLLINT_CONFIG="{extends: relaxed, rules: {line-length: {max: 160}}}" \
    HELM_YAMLLINT_ARGS="-f colored --strict" \
    KUBE_SCORE_VERSION=$KUBE_SCORE_VERSION \
    HELM_DIFF_ARGS="diff upgrade --allow-unreleased" \
    HELM_SCRIPTS_DIR="./chart/hooks/" \
    HELM_DELETE_ARGS="uninstall" \
    HELM_DEPLOY_ARGS="upgrade --install --rollback-on-failure --wait=hookOnly --timeout 15m0s" \
    HELM_TEST_ARGS="test"

SHELL ["/bin/ash", "-o", "pipefail", "-c"]

RUN set -eux; \
    apk update; \
    apk upgrade --no-cache; \
    apk add --no-cache \
      curl=8.21.0-r0 \
      yamllint=1.38.0-r0 \
      tar=1.35-r5 \
      cosign=3.0.6-r1 \
      jq=1.8.1-r0; \
    \
    curl -fsSL "https://github.com/zegl/kube-score/releases/download/v${KUBE_SCORE_VERSION}/kube-score_${KUBE_SCORE_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin kube-score; \
    chmod +x /usr/local/bin/kube-score; \
    \
    curl -fsSL "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin oras; \
    chmod +x /usr/local/bin/oras

COPY ci/ /ci

RUN chmod +x /ci/tbc-entrypoint.sh

WORKDIR /source

HEALTHCHECK --interval=10s --timeout=2s --retries=3 \
  CMD which helm kube-score oras cosign curl || exit 1

ENTRYPOINT ["/ci/tbc-entrypoint.sh"]