source /ci/tbc/tbc-helm.sh
mkdir -p -m 777 reports

helm_package
cp helm-package.env reports/helm-package.env