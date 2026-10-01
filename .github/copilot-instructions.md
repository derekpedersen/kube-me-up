# Copilot Instructions for kube-me-up

## Project purpose

This repository is a guided Kubernetes bootstrapper for getting a cluster from "fresh" to "traffic is live". The primary workflow is:

- create or reuse a Kubernetes cluster
- install ingress, cert-manager, and metrics-server
- apply a ClusterIssuer for TLS
- deploy the sample app from `johnny-5-alive/.helm`

The project is intentionally simple, script-driven, and operationally focused.

## Coding conventions

### Shell scripts

- Prefer Bash for installer and operational scripts.
- Keep scripts idempotent and safe to rerun.
- Use `set -euo pipefail` in scripts that need strict failure handling.
- Favor explicit logging helpers (`log_info`, `log_warn`, `log_error`, `log_step`) over ad hoc echo output.
- Preserve dry-run and resume-mode behavior. If a command can be skipped or printed without execution, respect that pattern.
- Avoid hidden side effects. If a change affects cluster state, make the behavior obvious and documented.

### Kubernetes and Helm

- Prefer `helm upgrade --install` patterns for idempotent changes.
- Preserve namespace and release naming conventions already used in the repo.
- Keep chart values and install flags consistent with the existing `Makefile` and `install.sh` patterns.
- When adding or changing infra, prefer the repo's current toolchain: `kubectl`, `helm`, and `make`.

### Sample app

- The sample app lives in `johnny-5-alive` and is deployed via the Helm chart in `johnny-5-alive/.helm`.
- Changes to app behavior should remain compatible with local Docker and Kubernetes deploy modes.
- Keep the app accessible via the same ingress and TLS flow described in the main README.

## Behavior expectations for AI edits

- Before suggesting destructive or cluster-altering commands, prefer safe, reversible, and idempotent patterns.
- Keep changes compatible with the guided installer flow in `install.sh` and the manual steps in `RUNBOOK.md`.
- If a feature changes installation behavior, update the user-facing documentation in README and RUNBOOK if needed.
- Respect the distinction between:
  - cluster creation
  - infrastructure installation
  - certificate issuance
  - application deployment
- Resume modes such as `--skip-cluster`, `--skip-infra`, `--skip-issuer`, and `--skip-app` should remain supported unless intentionally changed.

## Validation

- For shell and installer changes, prefer lightweight validation using `bash -n` or script execution in dry-run mode when appropriate.
- When changing Kubernetes manifests or Helm configuration, verify command semantics rather than assuming they are correct.
- Prefer commands that check cluster readiness (`kubectl get`, `kubectl get ingress`, `kubectl get clusterissuer`, etc.) over broad or noisy output.

## Documentation style

- Keep documentation concise and operational.
- Prefer command examples in Bash blocks.
- Call out prerequisites and assumptions clearly.
- If a feature affects the install flow, document it in the README and/or RUNBOOK.

## File map

- `install.sh`: guided installer and CLI flow
- `Makefile`: infra installation targets
- `cluster_issuer.yaml`: TLS issuer manifest
- `johnny-5-alive/.helm`: sample app chart
- `README.md`: project overview and quick-start flow
- `RUNBOOK.md`: manual troubleshooting and recovery steps
