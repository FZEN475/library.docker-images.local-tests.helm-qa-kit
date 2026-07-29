source /ci/tbc/tbc-helm.sh
mkdir -p -m 777 reports

if [[ -f "$PRE_HOOK_FILE" ]]; then
  log_info "--- \\e[32mpre-deploy hook\\e[0m (\\e[33;1m${PRE_HOOK_FILE}\\e[0m) found: execute"
  run_subprocess "$PRE_HOOK_FILE"
else
  log_info "--- \\e[32mpre-deploy hook\\e[0m (\\e[33;1m${PRE_HOOK_FILE}\\e[0m) not found: skip"
fi