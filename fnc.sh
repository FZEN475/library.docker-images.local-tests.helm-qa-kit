  set -e

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

  function install_ca_certs() {
    certs=$1
    if [[ -z "$certs" ]]
    then
      return
    fi
    if [[ -f "$certs" ]]; then

        # import in system
        if cat "$certs" >> /etc/ssl/certs/ca-certificates.crt
        then
          log_info "CA certificates imported in \\e[33;1m/etc/ssl/certs/ca-certificates.crt\\e[0m"
        fi
        if cat "$certs" >> /etc/ssl/cert.pem
        then
          log_info "CA certificates imported in \\e[33;1m/etc/ssl/cert.pem\\e[0m"
        fi

    else
        # import in system
        if echo "$certs" >> /etc/ssl/certs/ca-certificates.crt
        then
          log_info "CA certificates imported in \\e[33;1m/etc/ssl/certs/ca-certificates.crt\\e[0m"
        fi
        if echo "$certs" >> /etc/ssl/cert.pem
        then
          log_info "CA certificates imported in \\e[33;1m/etc/ssl/cert.pem\\e[0m"
        fi
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
          echo "$repo_password" | helm ${TRACE+--debug} repo add "$repo_name" "$repo_url" --username "$repo_user" --password-stdin --pass-credentials
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
    rm -f helm.env
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
    echo -e "environment_type=$environment_type\\nenvironment_name=$environment_name\\nenvironment_url=$environment_url" >> helm.env
    chmod 644 environment_url.txt helm.env
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

