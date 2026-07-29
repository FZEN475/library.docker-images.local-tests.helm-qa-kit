source /ci/tbc/tbc-helm.sh
mkdir -p -m 777 reports

set -a
source helm-package.env
set +a
export HELM_PUBLISH_METHOD="auto"
helm_publish $helm_package_file > reports/publish.txt