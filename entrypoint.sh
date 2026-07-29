#!/usr/bin/env ash

source /fnc.sh
install_ca_certs "${CUSTOM_CA_CERTS}"
add_helm_repositories

if [ "$DELETE_HELM" = "true" ]; then
  set +e
  helm_delete
  set -e
fi

if [ "$INSTALL_HELM" = "true" ]; then
    helm_deploy
fi


