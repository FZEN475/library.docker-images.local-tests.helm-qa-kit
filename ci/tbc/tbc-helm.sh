
# BEGSCRIPT
set -eo pipefail

function configure_docker_auth() {
  # Принимаем параметры или берем из окружения
  local registry="${1:-$CI_REGISTRY}"
  local user="${2:-$CI_REGISTRY_USER}"
  local token="${3:-$CI_JOB_TOKEN}"

  local docker_config_dir="$HOME/.docker"
  local docker_config_file="$docker_config_dir/config.json"

  # Проверка на заполнение обязательных данных
  if [[ -z "$registry" || -z "$user" || -z "$token" ]]; then
    log_error "Missing required Docker credentials:"
    [[ -z "$registry" ]] && log_error "  - Registry URL is empty"
    [[ -z "$user" ]]     && log_error "  - Registry User is empty"
    [[ -z "$token" ]]    && log_error "  - Registry Token/Password is empty"
    exit 1
  fi

  mkdir -p "$docker_config_dir"

  if [[ -f ".docker-config.json" ]]; then
    log_info "--- \\e[32m.docker-config.json\\e[0m file found: envsubst and install"
    tbc_envsubst .docker-config.json > "$docker_config_file"
  else
    log_info "--- configure \\e[32m${docker_config_file}\\e[0m for registry \\e[32m${registry}\\e[0m"

    # Кодируем credentials в base64
    local auth_base64=$(echo -n "${user}:${token}" | base64 | tr -d '\n')

    # Генерируем конфиг
    cat <<EOF > "$docker_config_file"
{
  "auths": {
    "${registry}": {
      "auth": "${auth_base64}"
    }
  }
}
EOF
  fi

  chmod 0600 "$docker_config_file"
}


# Функция для запуска скрипта в подпроцессе с сохранением среды
run_subprocess() {
    local script="$1"
    /bin/bash -c "source /tmp/current_env.sh; source $script"
}

function log_info() {
    echo -e "[\\e[1;94mINFO\\e[0m] $*"
}

function log_warn() {
    echo -e "[\\e[1;93mWARN\\e[0m] $*"
}

function log_error() {
    echo -e "[\\e[1;91mERROR\\e[0m] $*"
}

function fail() {
  log_error "$*"
  exit 1
}

function assert_defined() {
  if [[ -z "$1" ]]
  then
    log_error "$2"
    exit 1
  fi
}

function as_content() {
  file_or_content=$1
  if [[ -f "${file_or_content}" ]]; then
    cat "${file_or_content}"
  else
    echo "${file_or_content}"
  fi
}

function install_ca_certs() {
  certs=$1
  if [[ -z "$certs" ]]
  then
    return
  fi

  # import in system
  if as_content "$certs" >> /etc/ssl/certs/ca-certificates.crt
  then
    log_info "CA certificates imported in \\e[33;1m/etc/ssl/certs/ca-certificates.crt\\e[0m"
  fi
  if as_content "$certs" >> /etc/ssl/cert.pem
  then
    log_info "CA certificates imported in \\e[33;1m/etc/ssl/cert.pem\\e[0m"
  fi
}

function unscope_variables() {
  _scoped_vars=$(env | awk -F '=' "/^scoped__[a-zA-Z0-9_]+=/ {print \$1}" | sort)
  if [[ -z "$_scoped_vars" ]]; then return; fi
  log_info "Processing scoped variables..."
  for _scoped_var in $_scoped_vars
  do
    _fields=${_scoped_var//__/:}
    _condition=$(echo "$_fields" | cut -d: -f3)
    case "$_condition" in
    if) _not="";;
    ifnot) _not=1;;
    *)
      log_warn "... unrecognized condition \\e[1;91m$_condition\\e[0m in \\e[33;1m${_scoped_var}\\e[0m"
      continue
    ;;
    esac
    _target_var=$(echo "$_fields" | cut -d: -f2)
    _cond_var=$(echo "$_fields" | cut -d: -f4)
    _cond_val=$(eval echo "\$${_cond_var}")
    _test_op=$(echo "$_fields" | cut -d: -f5)
    case "$_test_op" in
    defined)
      if [[ -z "$_not" ]] && [[ -z "$_cond_val" ]]; then continue;
      elif [[ "$_not" ]] && [[ "$_cond_val" ]]; then continue;
      fi
      ;;
    equals|startswith|endswith|contains|in|equals_ic|startswith_ic|endswith_ic|contains_ic|in_ic)
      # comparison operator
      # sluggify actual value
      _cond_val=$(echo "$_cond_val" | tr '[:punct:]' '_')
      # retrieve comparison value
      _cmp_val_prefix="scoped__${_target_var}__${_condition}__${_cond_var}__${_test_op}__"
      _cmp_val=${_scoped_var#"$_cmp_val_prefix"}
      # manage 'ignore case'
      if [[ "$_test_op" =~ _ic$ ]]
      then
        # lowercase everything
        _cond_val=$(echo "$_cond_val" | tr '[:upper:]' '[:lower:]')
        _cmp_val=$(echo "$_cmp_val" | tr '[:upper:]' '[:lower:]')
      fi
      case "$_test_op" in
      equals*)
        if [[ -z "$_not" ]] && [[ "$_cond_val" != "$_cmp_val" ]]; then continue;
        elif [[ "$_not" ]] && [[ "$_cond_val" == "$_cmp_val" ]]; then continue;
        fi
        ;;
      startswith*)
        if [[ -z "$_not" ]] && [[ ! "$_cond_val" =~ ^"$_cmp_val" ]]; then continue;
        elif [[ "$_not" ]] && [[ "$_cond_val" =~ ^"$_cmp_val" ]]; then continue;
        fi
        ;;
      endswith*)
        if [[ -z "$_not" ]] && [[ ! "$_cond_val" =~ "$_cmp_val"$ ]]; then continue;
        elif [[ "$_not" ]] && [[ "$_cond_val" =~ "$_cmp_val"$ ]]; then continue;
        fi
        ;;
      contains*)
        # shellcheck disable=SC2076
        if [[ -z "$_not" ]] && [[ ! "$_cond_val" =~ "$_cmp_val" ]]; then continue;
        elif [[ "$_not" ]] && [[ "$_cond_val" =~ "$_cmp_val" ]]; then continue;
        fi
        ;;
      in*)
        if [[ -z "$_not" ]] && [[ ! __"$_cmp_val"__ =~ __"$_cond_val"__ ]]; then continue;
        elif [[ "$_not" ]] && [[ __"$_cmp_val"__ =~ __"$_cond_val"__ ]]; then continue;
        fi
        ;;
      esac
      ;;
    *)
      log_warn "... unrecognized test operator \\e[1;91m${_test_op}\\e[0m in \\e[33;1m${_scoped_var}\\e[0m"
      continue
      ;;
    esac
    # matches
    _val=$(eval echo "\$${_target_var}")
    log_info "... apply \\e[32m${_target_var}\\e[0m from \\e[32m\$${_scoped_var}\\e[0m"
    _val=$(eval echo "\$${_scoped_var}")
    export "${_target_var}"="${_val}"
  done
  log_info "... done"
}

# evaluate and export a secret
# - $1: secret variable name
function eval_secret() {
  name=$1
  value=$(eval echo "\$${name}")
  case "$value" in
  @b64@*)
    decoded=$(mktemp)
    errors=$(mktemp)
    if echo "$value" | cut -c6- | base64 -d > "${decoded}" 2> "${errors}"
    then
      # shellcheck disable=SC2086
      export ${name}="$(cat ${decoded})"
      log_info "Successfully decoded base64 secret \\e[33;1m${name}\\e[0m"
    else
      fail "Failed decoding base64 secret \\e[33;1m${name}\\e[0m:\\n$(sed 's/^/... /g' "${errors}")"
    fi
    ;;
  @hex@*)
    decoded=$(mktemp)
    errors=$(mktemp)
    if echo "$value" | cut -c6- | sed 's/\([0-9A-F]\{2\}\)/\\\\x\1/gI' | xargs printf > "${decoded}" 2> "${errors}"
    then
      # shellcheck disable=SC2086
      export ${name}="$(cat ${decoded})"
      log_info "Successfully decoded hexadecimal secret \\e[33;1m${name}\\e[0m"
    else
      fail "Failed decoding hexadecimal secret \\e[33;1m${name}\\e[0m:\\n$(sed 's/^/... /g' "${errors}")"
    fi
    ;;
  @url@*)
    url=$(echo "$value" | cut -c6-)
    if command -v curl > /dev/null
    then
      decoded=$(mktemp)
      errors=$(mktemp)
      if curl -s -S -f --connect-timeout "${TBC_SECRET_URL_TIMEOUT:-5}" -o "${decoded}" "$url" 2> "${errors}"
      then
        # shellcheck disable=SC2086
        export ${name}="$(cat ${decoded})"
        log_info "Successfully curl'd secret \\e[33;1m${name}\\e[0m"
      else
        log_warn "Failed getting secret \\e[33;1m${name}\\e[0m:\\n$(sed 's/^/... /g' "${errors}")"
      fi
    elif command -v wget > /dev/null
    then
      decoded=$(mktemp)
      errors=$(mktemp)
      if wget -T "${TBC_SECRET_URL_TIMEOUT:-5}" -O "${decoded}" "$url" 2> "${errors}"
      then
        # shellcheck disable=SC2086
        export ${name}="$(cat ${decoded})"
        log_info "Successfully wget'd secret \\e[33;1m${name}\\e[0m"
      else
        log_warn "Failed getting secret \\e[33;1m${name}\\e[0m:\\n$(sed 's/^/... /g' "${errors}")"
      fi
    else
      log_warn "Couldn't get secret \\e[33;1m${name}\\e[0m: no http client found"
    fi
    ;;
  esac
}

function eval_all_secrets() {
  # exclude scoped variables and their copies passed to container services (`<service_name>_ENV_scoped__xxx`)
  encoded_vars=$(env | awk -F '=' '$1 !~ /(^|_ENV_)scoped__/ && $2 ~ /^@(b64|hex|url)@/ {print $1}')
  for var in $encoded_vars
  do
    eval_secret "$var"
  done
}

function maybe_install_packages() {
  if command -v apt-get > /dev/null
  then
    # Debian
    if ! dpkg --status "$@" > /dev/null
    then
      apt-get update
      apt-get install --no-install-recommends --yes --quiet "$@"
    fi
  elif command -v apk > /dev/null
  then
    # Alpine
    if ! apk info --installed "$@" > /dev/null
    then
      apk add --no-cache "$@"
    fi
  else
    log_error "... didn't find any supported package manager to install $*"
    exit 1
  fi
}

function setup_kubeconfig() {
  explicit_config=${ENV_KUBE_CONFIG:-${HELM_DEFAULT_KUBE_CONFIG}}
  if [[ -f "$explicit_config" ]]
  then
    # is a path to a Kuberconfig file
    export KUBECONFIG="$CI_PROJECT_DIR/.kubeconfig"
    cp -f "$explicit_config" "$KUBECONFIG"
    log_info "--- using \\e[32mKUBECONFIG\\e[0m provided by env variables"
  elif [[ -n "$explicit_config" ]]
  then
    # is a Kuberconfig file content
    export KUBECONFIG="$CI_PROJECT_DIR/.kubeconfig"
    echo "$explicit_config" > "$KUBECONFIG"
    log_info "--- using \\e[32mKUBECONFIG\\e[0m provided by env variables"
  elif [[ -n "$KUBECONFIG" ]]
  then
    log_info "--- using \\e[32mKUBECONFIG\\e[0m provided by GitLab"
    if [[ -n "$KUBE_CONTEXT" ]]
    then
      export HELM_KUBECONTEXT="${HELM_KUBECONTEXT:-$KUBE_CONTEXT}"
      log_info "--- switch to the given \\e[32mKUBE_CONTEXT\\e[0m: ${KUBE_CONTEXT}"
    fi
  else
    log_warn "No \\e[32mKUBECONFIG\\e[0m configuration found!"
  fi
}

function add_helm_repositories() {
  if [[ -z "$HELM_REPOS" ]]
  then
    log_info "--- no additional repositories set: skip"
    return
  fi

  # Use cacheable folders
  mkdir -p "$CI_PROJECT_DIR/.config/helm/"
  mkdir -p "$CI_PROJECT_DIR/.cache/helm/repository/"

  # Install helm repositories
  for repo in $HELM_REPOS
  do
    repo_name=$(echo "$repo" | cut -d@ -f 1)
    repo_url=$(echo "$repo" | cut -d@ -f 2)
    repo_name_ssc=$(echo "$repo_name" | tr '[:lower:]' '[:upper:]' | tr '[:punct:]' '_')
    repo_user=$(eval echo "\$HELM_REPO_${repo_name_ssc}_USER")
    repo_password=$(eval echo "\$HELM_REPO_${repo_name_ssc}_PASSWORD")

    if [[ "$repo_url" =~ oci://.* ]]
    then
      if [[ "$repo_user" ]] && [[ "$repo_password" ]]
      then
        registry_host=$(echo "$repo_url" | cut -d'/' -f3)
        log_info "--- login to OCI-registry \\e[32m${repo_name}\\e[0m: \\e[33;1m${registry_host}\\e[0m"
        export HELM_EXPERIMENTAL_OCI=1
        # shellcheck disable=SC2086
        echo "$repo_password" | helm ${TRACE+--debug} registry login "$registry_host" --username "$repo_user" --password-stdin
      else
        log_warn "--- OCI-registry \\e[32m${repo_name}\\e[0m (\\e[33;1m${repo_url}\\e[0m) defined, but no credentials found (\$HELM_REPO_${repo_name_ssc}_USER/\$HELM_REPO_${repo_name_ssc}_PASSWORD)"
      fi
    else
      if [[ "$repo_user" ]] && [[ "$repo_password" ]]
      then
        log_info "--- add repository \\e[32m${repo_name}\\e[0m: \\e[33;1m${repo_url}\\e[0m (with user/password auth)"
        # shellcheck disable=SC2086
        echo "$repo_password" | helm ${TRACE+--debug} repo add "$repo_name" "$repo_url" --username "$repo_user" --password-stdin --pass-credentials --force-update
      else
        log_info "--- add repository \\e[32m${repo_name}\\e[0m: \\e[33;1m${repo_url}\\e[0m (unauthenticated)"
        # shellcheck disable=SC2086
        helm ${TRACE+--debug} repo add "$repo_name" "$repo_url"
      fi
      update_required=1
    fi
  done

  if [[ "$update_required" ]]
  then
    # shellcheck disable=SC2086
    helm ${TRACE+--debug} repo update
  fi
}

# Install helm-diff plugin (compatible Helm 3 & 4)
# usage: helm_plugin_diff [verify] [version]
# - verify: true/false (only relevant for Helm 4+)
# - version: explicit plugin version (omit or empty to install latest)
function helm_plugin_diff() {
  plugin_name="diff"
  plugin_url="https://github.com/databus23/helm-diff"
  plugin_verify="${1:-false}"
  plugin_version="${2:-}"

  # Check and install git if necessary
  if ! command -v git > /dev/null; then
    log_info "--- git is not installed, attempting installation..."
    maybe_install_packages git
  fi

  log_info "--- checking Helm plugin: \e[32m${plugin_name}\e[0m"

  plugin_helm_major="$(helm version --short 2>/dev/null | sed 's/^v//' | cut -d. -f1)"

  plugin_verify_flag=""
  # Helm version support EOL : https://helm.sh/el/blog/helm-4-released/#helm-v3-support
  if echo "$plugin_helm_major" | awk '/^[0-9]+$/ {exit 0} {exit 1}' && [ "$plugin_helm_major" -ge 4 ]; then
    plugin_verify_flag="--verify=${plugin_verify}"
    log_info "--- helm v${plugin_helm_major} detected: plugin signature verification = \e[33;1m${plugin_verify}\e[0m (--verify flag used)"
  else
    log_info "--- helm v${plugin_helm_major} detected: signature verification not supported (--verify flag ignored)"
  fi

  if helm plugin list 2>/dev/null | awk -v n="$plugin_name" 'NR>1 && $1==n {found=1} END{exit !found}'; then
    log_info "--- plugin \e[32m${plugin_name}\e[0m already installed"
    return 0
  fi

  if [ -n "$plugin_version" ]; then
    log_info "--- installing plugin \e[32m${plugin_name}\e[0m (version \e[33;1m${plugin_version}\e[0m)"
  else
    log_info "--- installing plugin \e[32m${plugin_name}\e[0m (latest)"
  fi

  plugin_errors=$(mktemp)
  if helm ${TRACE+--debug} plugin install \
    ${plugin_verify_flag:+$plugin_verify_flag} \
    ${plugin_version:+--version "$plugin_version"} \
    "$plugin_url" 2>"$plugin_errors"; then
      log_info "--- plugin \e[32m${plugin_name}\e[0m installed"
  else
      log_warn "--- failed to install plugin \e[32m${plugin_name})\e[0m:\n$(sed 's/^/... /g' "$plugin_errors")"
      return 1
  fi
}

function tbc_envsubst() {
  awk '
    BEGIN {
      count_replaced_lines = 0
      # ASCII codes
      for (i=0; i<=255; i++)
        char2code[sprintf("%c", i)] = i
    }
    # determine encoding (from env or from file extension)
    function encoding() {
      enc = ENVIRON["TBC_ENVSUBST_ENCODING"]
      if (enc != "")
        return enc
      if (match(FILENAME, /\.(json|yaml|yml)$/))
        return "jsonstr"
      return "raw"
    }
    # see: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/encodeURIComponent
    function uriencode(str) {
      len = length(str)
      enc = ""
      for (i=1; i<=len; i++) {
        c = substr(str, i, 1);
        if (index("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'\''()", c))
          enc = enc c
        else
          enc = enc "%" sprintf("%02X", char2code[c])
      }
      return enc
    }
    /# *nosubst/ {
      print $0
      next
    }
    {
      orig_line = $0
      line = $0
      count_repl_in_line = 0
      # /!\ 3rd arg (match) not supported in BusyBox awk
      while (match(line, /[$%]\{([[:alnum:]_]+)\}/)) {
        expr_start = RSTART
        expr_len = RLENGTH
        # get var name
        var = substr(line, expr_start+2, expr_len-3)
        # get var value (from env)
        val = ENVIRON[var]
        # check variable is set
        if (val == "") {
          printf("[\033[1;93mWARN\033[0m] Environment variable \033[33;1m%s\033[0m is not set or empty\n", var) > "/dev/stderr"
        } else {
          enc = encoding()
          if (enc == "jsonstr") {
            gsub(/["\\]/, "\\\\&", val)
            gsub("\n", "\\n", val)
            gsub("\r", "\\r", val)
            gsub("\t", "\\t", val)
          } else if (enc == "uricomp") {
            val = uriencode(val)
          } else if (enc == "raw") {
          } else {
            printf("[\033[1;93mWARN\033[0m] Unsupported encoding \033[33;1m%s\033[0m: ignored\n", enc) > "/dev/stderr"
          }
        }
        # replace expression in line
        line = substr(line, 1, expr_start - 1) val substr(line, expr_start + expr_len)
        count_repl_in_line++
      }
      if (count_repl_in_line) {
        if (count_replaced_lines == 0)
          printf("[\033[1;94mINFO\033[0m] Variable expansion occurred in file \033[33;1m%s\033[0m:\n", FILENAME) > "/dev/stderr"
        count_replaced_lines++
        printf("> line %s: %s\n", NR, orig_line) > "/dev/stderr"
      }
      print line
    }
  ' "$@"
}

function exec_hook() {
  if [[ ! -x "$1" ]] && ! chmod +x "$1"
  then
    log_warn "... could not make \\e[33;1m${1}\\e[0m executable: please do it (chmod +x)"
    # fallback technique
    sh "$1"
  else
    "$1"
  fi
}

# deploy application
function helm_deploy() {
  export environment_type=$ENV_TYPE
  export environment_name=${ENV_APP_NAME:-${HELM_BASE_APP_NAME}${ENV_APP_SUFFIX}}
  export kube_namespace=${ENV_NAMESPACE:-${KUBE_NAMESPACE}}
  values_files=$ENV_VALUES
  environment_url=${ENV_URL:-$HELM_ENVIRONMENT_URL}
  environment_namespace=$(echo "$HELM_ENVIRONMENT_NAMESPACE" | tr -d '[:punct:]' | tr '[:upper:]' '[:lower:]')
  export environment_namespace

  # variables expansion in $environment_url
  environment_url=$(echo "$environment_url" | TBC_ENVSUBST_ENCODING=uricomp tbc_envsubst)
  export environment_url
  # extract hostname from $environment_url
  hostname=$(echo "$environment_url" | awk -F[/:] '{print $4}')
  export hostname

  log_info "--- \\e[32mdeploy\\e[0m"
  log_info "--- \$kube_namespace: \\e[33;1m${kube_namespace}\\e[0m"
  log_info "--- \$environment_type: \\e[33;1m${environment_type}\\e[0m (Helm variable '$HELM_ENV_VALUE_NAME')"
  log_info "--- \$environment_name: \\e[33;1m${environment_name}\\e[0m (used as release name)"
  log_info "--- \$hostname: \\e[33;1m${hostname}\\e[0m (Helm variable '$HELM_HOSTNAME_VALUE_NAME')"

  # unset any upstream deployment env & artifacts
  rm -f helm.env*
  rm -f environment_url.txt

  # maybe execute pre deploy script
  prescript="$HELM_SCRIPTS_DIR/helm-pre-deploy.sh"
  if [[ -f "$prescript" ]]; then
    log_info "--- \\e[32mpre-deploy hook\\e[0m (\\e[33;1m${prescript}\\e[0m) found: execute"
    exec_hook "$prescript"
  else
    log_info "--- \\e[32mpre-deploy hook\\e[0m (\\e[33;1m${prescript}\\e[0m) not found: skip"
  fi

  helm_opts=${TRACE+--debug}

  helm_opts="$helm_opts --set ${HELM_ENV_VALUE_NAME}=$environment_type"
  helm_opts="$helm_opts --set ${HELM_HOSTNAME_VALUE_NAME}=$hostname"

  if [ -n "$HELM_COMMON_VALUES" ]; then
    log_info "--- using \\e[32mcommon values\\e[0m file: \\e[33;1m${HELM_COMMON_VALUES}\\e[0m"
    TBC_ENVSUBST_ENCODING=jsonstr tbc_envsubst "$HELM_COMMON_VALUES" > generated-values-common.yml
    helm_opts="$helm_opts --values generated-values-common.yml"
  fi

  if [ -n "$values_files" ]; then
    log_info "--- using \\e[32mvalues\\e[0m file: \\e[33;1m${values_files}\\e[0m"
    TBC_ENVSUBST_ENCODING=jsonstr tbc_envsubst "$values_files" > generated-values.yml
    helm_opts="$helm_opts --values generated-values.yml"
  fi

  if [ -f "$CI_PROJECT_DIR/.kubeconfig" ]; then
    log_info "--- using \\e[32mkubeconfig\\e[0m: \\e[33;1m$CI_PROJECT_DIR/.kubeconfig\\e[0m"
    helm_opts="$helm_opts --kubeconfig $CI_PROJECT_DIR/.kubeconfig"
  fi

  if [ -n "$kube_namespace" ]; then
    log_info "--- using \\e[32mnamespace\\e[0m: \\e[33;1m${kube_namespace}\\e[0m"
    helm_opts="$helm_opts --namespace $kube_namespace"
  fi

  _pkg=${helm_package_file:-$HELM_DEPLOY_CHART}
  if [ -z "${_pkg}" ]; then
    log_error "No Chart to deploy! Please use \\e[32m\$HELM_DEPLOY_CHART\\e[0m to deploy a chart from a repository"
    log_error "Or check the provided variables to package your own chart!"
    exit 1
  fi
  log_info "--- using \\e[32mpackage\\e[0m: \\e[33;1m${_pkg}\\e[0m"

  # Run helm diff before deploy unless disabled
  if [ "$HELM_DIFF_DISABLED" != "true" ]; then
    log_info "--- ensuring helm-diff plugin is installed"
    helm_plugin_diff false || {
      log_error "Helm diff plugin not installed, aborting deploy. Set HELM_DIFF_DISABLED=true to skip diff."
      exit 1
    }
    log_info "--- running helm diff before deploy (set HELM_DIFF_DISABLED=true to skip)"
    helm_diff || {
      log_error "Helm diff failed, aborting deploy. Set HELM_DIFF_DISABLED=true to skip diff."
      exit 1
    }
  fi

  # shellcheck disable=SC2086
  helm $helm_opts $HELM_DEPLOY_ARGS $environment_name $_pkg

  # maybe execute post deploy script
  postscript="$HELM_SCRIPTS_DIR/helm-post-deploy.sh"
  if [[ -f "$postscript" ]]; then
    log_info "--- \\e[32mpost-deploy hook\\e[0m (\\e[33;1m${postscript}\\e[0m) found: execute"
    exec_hook "$postscript"
  else
    log_info "--- \\e[32mpost-deploy hook\\e[0m (\\e[33;1m${postscript}\\e[0m) not found: skip"
  fi

  # persist environment url
  if [[ -f environment_url.txt ]]
  then
    environment_url=$(cat environment_url.txt)
    export environment_url
    log_info "--- dynamic environment url found: (\\e[33;1m$environment_url\\e[0m)"
  else
    echo "$environment_url" > environment_url.txt
  fi
  # var prefix ('_' if namespace)
  prefix="${environment_namespace:+${environment_namespace}_}"
  dotenvfile="helm.env${environment_namespace:+.${environment_namespace}}"
  {
    echo "${prefix}environment_type=${environment_type}"
    echo "${prefix}environment_name=${environment_name}"
    echo "${prefix}environment_url=${environment_url}"
    # '$environment_url' is required by GitLab (dynamic env URL)
    if [[ "$environment_namespace" ]]; then echo "environment_url=${environment_url}"; fi
  } >> "$dotenvfile"
  chmod 644 environment_url.txt "$dotenvfile"
}

# delete application (and dependencies)
function helm_delete() {
  export environment_type=$ENV_TYPE
  export environment_name=${ENV_APP_NAME:-${HELM_BASE_APP_NAME}${ENV_APP_SUFFIX}}
  export kube_namespace=${ENV_NAMESPACE:-${KUBE_NAMESPACE}}

  log_info "--- \\e[32mdelete"
  log_info "--- \$kube_namespace: \\e[33;1m${kube_namespace}\\e[0m"
  log_info "--- \$environment_type: \\e[33;1m${environment_type}\\e[0m"
  log_info "--- \$environment_name: \\e[33;1m${environment_name}\\e[0m (used as release name)"

  # maybe execute pre delete script
  prescript="$HELM_SCRIPTS_DIR/helm-pre-delete.sh"
  if [[ -f "$prescript" ]]; then
    log_info "--- \\e[32mpre-delete hook\\e[0m (\\e[33;1m${prescript}\\e[0m) found: execute"
    exec_hook "$prescript"
  else
    log_info "--- \\e[32mpre-delete hook\\e[0m (\\e[33;1m${prescript}\\e[0m) not found: skip"
  fi

  helm_opts=${TRACE+--debug}

  if [ -f "$CI_PROJECT_DIR/.kubeconfig" ]; then
    log_info "--- using \\e[32mkubeconfig\\e[0m: \\e[33;1m$CI_PROJECT_DIR/.kubeconfig\\e[0m"
    helm_opts="$helm_opts --kubeconfig $CI_PROJECT_DIR/.kubeconfig"
  fi

  if [ -n "$kube_namespace" ]; then
    log_info "--- using \\e[32mnamespace\\e[0m: \\e[33;1m${kube_namespace}\\e[0m"
    helm_opts="$helm_opts --namespace $kube_namespace"
  fi

  # shellcheck disable=SC2086
  helm $helm_opts $HELM_DELETE_ARGS $environment_name

  # maybe execute post delete script
  postscript="$HELM_SCRIPTS_DIR/helm-post-delete.sh"
  if [[ -f "$postscript" ]]; then
    log_info "--- \\e[32mpost-delete hook\\e[0m (\\e[33;1m${postscript}\\e[0m) found: execute"
    exec_hook "$postscript"
  else
    log_info "--- \\e[32mpost-delete hook\\e[0m (\\e[33;1m${postscript}\\e[0m) not found: skip"
  fi
}

# diff application
function helm_diff() {
  export environment_type=$ENV_TYPE
  export environment_name=${ENV_APP_NAME:-${HELM_BASE_APP_NAME}${ENV_APP_SUFFIX}}
  export values_files=$ENV_VALUES
  export kube_namespace=${ENV_NAMESPACE:-${KUBE_NAMESPACE}}

  log_info "--- \\e[32mdiff\\e[0m"
  log_info "--- \$kube_namespace: \\e[33;1m${kube_namespace}\\e[0m"
  log_info "--- \$environment_type: \\e[33;1m${environment_type}\\e[0m"
  log_info "--- \$environment_name: \\e[33;1m${environment_name}\\e[0m (used as release name)"

  helm_opts=${TRACE+--debug}

  # set the environment type (if value name is defined)
  if [ -n "$HELM_ENV_VALUE_NAME" ]; then
    helm_opts="$helm_opts --set ${HELM_ENV_VALUE_NAME}=${environment_type}"
  fi

  if [ -n "${HELM_COMMON_VALUES}" ]; then
    log_info "--- using \\e[32mcommon values\\e[0m file: \\e[33;1m${HELM_COMMON_VALUES}\\e[0m"
    TBC_ENVSUBST_ENCODING=jsonstr tbc_envsubst "$HELM_COMMON_VALUES" > generated-values-common.yml
    helm_opts="$helm_opts --values generated-values-common.yml"
  fi

  if [ -n "$values_files" ]; then
    log_info "--- using \\e[32mvalues\\e[0m file: \\e[33;1m${values_files}\\e[0m"
    TBC_ENVSUBST_ENCODING=jsonstr tbc_envsubst "$values_files" > generated-values.yml
    helm_opts="$helm_opts --values generated-values.yml"
  fi

  if [ -f "$CI_PROJECT_DIR/.kubeconfig" ]; then
    log_info "--- using \\e[32mkubeconfig\\e[0m: \\e[33;1m$CI_PROJECT_DIR/.kubeconfig\\e[0m"
    helm_opts="$helm_opts --kubeconfig $CI_PROJECT_DIR/.kubeconfig"
  fi

  if [ -n "$kube_namespace" ]; then
    log_info "--- using \\e[32mnamespace\\e[0m: \\e[33;1m${kube_namespace}\\e[0m"
    helm_opts="$helm_opts --namespace $kube_namespace"
  fi

  _pkg=${helm_package_file:-$HELM_DEPLOY_CHART}
  if [ -z "${_pkg}" ]; then
    log_error "No Chart to diff! Please use \\e[32m\$HELM_DEPLOY_CHART\\e[0m to diff a chart from a repository"
    log_error "Or check the provided variables to package your own chart!"
    exit 1
  fi
  log_info "--- using \\e[32mpackage\\e[0m: \\e[33;1m${_pkg}\\e[0m"

  # shellcheck disable=SC2086
  helm $helm_opts $HELM_DIFF_ARGS $environment_name $_pkg
}

# test application (and dependencies)
function helm_test() {
  export kube_namespace=${ENV_NAMESPACE:-${KUBE_NAMESPACE}}
  export environment_type=$ENV_TYPE
  export environment_name=${ENV_APP_NAME:-${HELM_BASE_APP_NAME}${ENV_APP_SUFFIX}}

  log_info "--- \\e[32mtest\\e[0m (env: ${environment_type})"
  log_info "--- \$kube_namespace: \\e[33;1m${kube_namespace}\\e[0m"
  log_info "--- \$environment_name: \\e[33;1m${environment_name}\\e[0m"
  log_info "--- \$environment_type: \\e[33;1m${environment_type}\\e[0m"

  helm_opts=${TRACE+--debug}

  if [ -f "$CI_PROJECT_DIR/.kubeconfig" ]; then
    log_info "--- using \\e[32mkubeconfig\\e[0m: \\e[33;1m$CI_PROJECT_DIR/.kubeconfig\\e[0m"
    helm_opts="$helm_opts --kubeconfig $CI_PROJECT_DIR/.kubeconfig"
  fi

  if [ -n "$kube_namespace" ]; then
    log_info "--- using \\e[32mnamespace\\e[0m: \\e[33;1m${kube_namespace}\\e[0m"
    helm_opts="$helm_opts --namespace $kube_namespace"
  fi

  # shellcheck disable=SC2086
  helm $helm_opts $HELM_TEST_ARGS $environment_name
}

function helm_package() {
  rm -f helm-package.env
  # extract version from chart
  base_version=$(yq '.version' "$HELM_CHART_DIR/Chart.yaml")
  # override version if:
  # - on tag (release)
  # - semantic-release integration is enabled & next version is defined
  if [[ "${CI_COMMIT_TAG}" ]]
  then
    base_version="${CI_COMMIT_TAG}"
    log_info "[release] use Git tag as version: \\e[33;1m${base_version}\\e[0m"
  elif [[ "${SEMREL_INFO_ON}" ]] && [[ "${HELM_SEMREL_RELEASE_DISABLED}" != "true" ]]
  then
    if [[ -z "${SEMREL_INFO_NEXT_VERSION}" ]]
    then
      log_info "[semantic-release] no new version to release: use default"
    else
      base_version="${SEMREL_INFO_NEXT_VERSION}"
      log_info "[semantic-release] use computed next version: \\e[33;1m${base_version}\\e[0m"
    fi
  fi
  chart_name=$(yq '.name' "$HELM_CHART_DIR/Chart.yaml")

  # if on non-prod branch: also append branch slug as version label
  if [[ -z "${CI_COMMIT_TAG}" ]]
  then
    prod_ref_expr=${PROD_REF#/}
    prod_ref_expr=${prod_ref_expr%/}
    if [[ ! "$CI_COMMIT_REF_NAME" =~ $prod_ref_expr ]]
    then
      version_label="-$CI_COMMIT_REF_SLUG"
    fi
  fi

  # helm package
  log_info "packaging chart with version: \\e[33;1m${base_version}${version_label}\\e[0m"


  # shellcheck disable=SC2086
  helm ${TRACE+--debug} $HELM_PACKAGE_ARGS --version ${base_version}${version_label} $HELM_CHART_DIR --destination helm_packages

  helm_package=$(ls -1 ./helm_packages/*.tgz 2>/dev/null || echo "")
  echo -e "helm_package_file=${helm_package}\\nhelm_package_version=${base_version}${version_label}\\nhelm_package_name=${chart_name}" > helm-package.env

  # publish snapshot version if enabled (but not on tag pipeline)
  if [[ "${HELM_PUBLISH_SNAPSHOT_ENABLED}" == "true" ]] && [[ -z "${CI_COMMIT_TAG}" ]]
  then
    # default value of HELM_PUBLISH_SNAPSHOT_SUFFIX is "snapshot"
    snapshot_label="${base_version}${version_label}-${HELM_PUBLISH_SNAPSHOT_SUFFIX}"

    log_info "snapshot enabled: also package and publish chart with version: \\e[33;1m${snapshot_label}\\e[0m"
    mkdir -p /tmp/helm_snapshot
    # shellcheck disable=SC2086
    helm ${TRACE+--debug} $HELM_PACKAGE_ARGS --version ${snapshot_label} $HELM_CHART_DIR --destination /tmp/helm_snapshot
    snapshot_package=$(ls -1 /tmp/helm_snapshot/*.tgz 2>/dev/null || echo "")
    helm_publish "$snapshot_package"
    echo -e "helm_snapshot_package_name=${chart_name}\\nhelm_snapshot_package_version=${snapshot_label}\\nhelm_snapshot_package_remote_url=${HELM_PUBLISH_URL}" >> helm-package.env
  fi
  chmod 644 helm-package.env
}

function helm_publish() {
  _pkg=${1}
  if [[ -z "$_pkg" ]]; then
    log_error "No package found to deploy"
    exit 1
  fi
  _pkg_name=$(basename "$_pkg")
  log_info "--- Publishing Helm package ${_pkg_name} to: ${HELM_PUBLISH_URL}..."

  # method to lowercase
  HELM_PUBLISH_METHOD=$(echo "$HELM_PUBLISH_METHOD" | tr '[:upper:]' '[:lower:]')

  # auto-detect method
  if [[ "$HELM_PUBLISH_METHOD" == "auto" ]]
  then
      log_info "--- trying to auto detect publish method..."
      pubscript="$HELM_SCRIPTS_DIR/helm-publish.sh"
      if [[ -f "$pubscript" ]]
      then
        log_info "--- ... custom publish script (\\e[33;1m${pubscript}\\e[0m) found: will use"
        HELM_PUBLISH_METHOD=custom
      elif [[ "$HELM_PUBLISH_URL" =~ oci://.* ]]
      then
        log_info "--- ... publish url looks like an OCI registry: will use helm push"
        HELM_PUBLISH_METHOD=push
      else
        log_info "--- ... publish url looks like a Chart repository: will use push method (uses cm-push plugin)"
        log_info "--- ... if auto-selected method is not suited, override with \$HELM_PUBLISH_METHOD or provide a custom publish script"
        HELM_PUBLISH_METHOD=push
      fi
  fi

  username="${HELM_PUBLISH_USER:-$CI_REGISTRY_USER}"
  password="${HELM_PUBLISH_PASSWORD:-$CI_REGISTRY_PASSWORD}"
  case "$HELM_PUBLISH_METHOD" in
  push)
    if [[ "$HELM_PUBLISH_URL" =~ oci://.* ]]
    then
      registry_host=$(echo "$HELM_PUBLISH_URL" | cut -d'/' -f3)
      # shellcheck disable=SC2086
      echo "$password" | helm ${TRACE+--debug} registry login "$registry_host" --username "$username" --password-stdin
      # enable OCI support prior to v3.8.0
      export HELM_EXPERIMENTAL_OCI=1
      # shellcheck disable=SC2086
      helm ${TRACE+--debug} push "$_pkg" "$HELM_PUBLISH_URL"
    else
      log_info "Installing cm-push plugin (version ${HELM_CM_PUSH_PLUGIN_VERSION:-latest})..."
      cm_push_plugin_verify_flag=""
      plugin_helm_major="$(helm version --short 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
      # Helm version support EOL : https://helm.sh/el/blog/helm-4-released/#helm-v3-support
      if echo "$plugin_helm_major" | awk '/^[0-9]+$/ {exit 0} {exit 1}' && [ "$plugin_helm_major" -ge 4 ]; then
        cm_push_plugin_verify_flag="--verify=false" # Disable signature verification because cm-push is not signed (https://github.com/chartmuseum/helm-push/issues/243)
        log_info "--- helm v${plugin_helm_major} detected: plugin signature verification = \e[33;1mfalse\e[0m (--verify flag used)"
      else
        log_info "--- helm v${plugin_helm_major} detected: signature verification not supported (--verify flag ignored)"
      fi

      # shellcheck disable=SC2086
      helm ${TRACE+--debug} plugin install ${cm_push_plugin_verify_flag} ${HELM_CM_PUSH_PLUGIN_VERSION:+--version "$HELM_CM_PUSH_PLUGIN_VERSION"} https://github.com/chartmuseum/helm-push || true
      # shellcheck disable=SC2086
      helm ${TRACE+--debug} cm-push --username "$username" --password "$password" "$_pkg" "$HELM_PUBLISH_URL"
    fi
    ;;
  post)
    if ! command -v curl > /dev/null
    then
      log_info "--- installing curl (required to publish Helm charts)..."
      apk add --no-cache curl
    fi
    curl --fail --request POST --form "chart=@$_pkg" --user "$username:$password" "$HELM_PUBLISH_URL"
    ;;
  put)
    wget -v --method=PUT --user="$username" --password="$password" --body-file="$_pkg" "$HELM_PUBLISH_URL/$_pkg_name" -O -
    ;;
  custom)
    pubscript="$HELM_SCRIPTS_DIR/helm-publish.sh"
    log_info "--- run custom publish script (\\e[33;1m${pubscript}\\e[0m)"
    exec_hook "$pubscript"
    ;;
  *)
    log_error "Unsupported publish method: $HELM_PUBLISH_METHOD"
    exit 1
    ;;
  esac
}

unscope_variables
eval_all_secrets

# ENDSCRIPT
