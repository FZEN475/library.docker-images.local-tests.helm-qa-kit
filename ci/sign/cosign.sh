source /ci/tbc/tbc-helm.sh
mkdir -p -m 777 reports
set -euo pipefail
set -a
source helm-package.env
set +a

export COSIGN_EXPERIMENTAL=1

create_image_ref() {
  IMAGE_REF="${HELM_PUBLISH_URL#oci://}/${helm_package_name}:${helm_package_version}"
  IMAGE_DIGEST=$(oras resolve "$IMAGE_REF")
  log_info "IMAGE_DIGEST: ${IMAGE_DIGEST}"
  IMAGE_REF="${HELM_PUBLISH_URL#oci://}/${helm_package_name}@${IMAGE_DIGEST}"
}

add_attestations() {
    OLD_IFS=$IFS
    IFS=';'

    for item in ${COSIGN_ATTESTS:-}
    do
        IFS='|'
        set -- $item

        type=$1
        predicate=$2

        echo "Attesting: type=$type predicate=$predicate"

        cosign attest \
            ${COSIGN_ATTEST_ARGS:-} \
            ${COSIGN_KEY:+--key=$COSIGN_KEY} \
            --timeout 90s \
            --predicate "$predicate" \
            --type "$type" \
            "$IMAGE_REF"
    done
    if [ -n "${COSIGN_ATTESTS:-}" ]; then
        log_info "verify-attestation: ${IMAGE_REF}"
        cosign verify-attestation \
          ${COSIGN_VERIFY_ATTEST_ARGS:-} \
          ${COSIGN_KEY:+--key=$COSIGN_KEY} \
          "$IMAGE_REF" | jq . | tee reports/cosign-verify-attestation.json
    fi
    IFS=$OLD_IFS
}

create_image_ref

log_info "Подпись репозитория: ${IMAGE_REF}"

cosign sign --help
echo $COSIGN_ANNOTATIONS | xargs cosign sign \
  ${COSIGN_SIGN_ARGS:-} \
  ${COSIGN_KEY:+--key=$COSIGN_KEY} \
  "${IMAGE_REF}" | tee reports/cosign-sign.txt
log_info "verify: ${IMAGE_REF}"

cosign verify \
  ${COSIGN_VERIFY_ARGS:-} \
  ${COSIGN_KEY:+--key=$COSIGN_KEY} \
  --output-file reports/cosign-verify.json \
  "${IMAGE_REF}" | jq . | tee reports/cosign-verify.json

log_info "Добавление аттестаций:"

add_attestations

cosign tree "${IMAGE_REF}" | tee reports/cosign-tree.txt

