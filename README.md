# helm

; REGISTRY_USER=registry_access
; REGISTRY_PASSWORD=glpat-3PO71kPEwrmpT7LaCuMhZ286MQp1OncH.01.0w10hgfcy
## CI 
```mermaid
    gitGraph
      commit id: "start"
      branch lint
      commit id: "py-ruff"
      commit id: "py-ruff-format"
      commit id: "py-isort"
      commit id: "py-black"
      commit id: "py-lint"
      commit id: "py-mypy"
      commit id: "py-basedpyright"
      commit id: "py-ty"

    checkout main
    merge lint id: "py-compile"
    branch tests
      commit id: "py-unittest"
      commit id: "py-pytest"
    branch audit
      commit id: "py-bandit"
      commit id: "py-trivy"
      commit id: "py-sbom"
    checkout main
    merge audit id: "py-package"
    branch build
    commit id: "hook-post-py-package"
      commit id: "fnc-pyinstaller"
    branch publish
      commit id: "py-publish"
      commit id: "gl-publish"
    checkout main
    merge publish id: "fnc-release"
```