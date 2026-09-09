# Kube Me Up AGENTS

This file is the canonical repo contract for agents and automation.

## Project Purpose

Kube Me Up is a script-first path from fresh cluster to live HTTPS traffic.

The Helm-based runtime flows are Kubernetes-provider agnostic for existing clusters. Cluster creation remains DOKS-first.

The primary workflow is:

1. Create or reuse a Kubernetes cluster.
2. Install ingress, cert-manager, and metrics-server.
3. Apply a ClusterIssuer for TLS.
4. Deploy the sample app from `johnny-5-alive/.helm`.

The repo is intentionally simple, script-driven, and operationally focused.

## Coding Conventions

### Shell Scripts

- Prefer Bash for installer and operational scripts.
- Keep scripts idempotent and safe to rerun.
- Use `set -euo pipefail` in scripts that need strict failure handling.
- Favor explicit logging helpers such as `log_info`, `log_warn`, `log_error`, and `log_step` over ad hoc echo output.
- Preserve dry-run and resume-mode behavior.
- Avoid hidden side effects. If a change affects cluster state, make the behavior obvious and documented.

### Kubernetes and Helm

- Prefer `helm upgrade --install` patterns for idempotent changes.
- Preserve namespace and release naming conventions already used in the repo.
- Keep chart values and install flags consistent with the existing `Makefile` and `install.sh` patterns.
- When adding or changing infra, prefer the repo's current toolchain: `kubectl`, `helm`, and `make`.

### Sample App

- The sample app lives in `johnny-5-alive` and is deployed via the Helm chart in `johnny-5-alive/.helm`.
- Changes to app behavior should remain compatible with local Docker and Kubernetes deploy modes.
- Keep the app accessible via the same ingress and TLS flow described in the main README.

## Behavior Expectations for AI Edits

- Before suggesting destructive or cluster-altering commands, prefer safe, reversible, and idempotent patterns.
- Keep changes compatible with the guided installer flow in `install.sh` and the manual steps in `RUNBOOK.md`.
- If a feature changes installation behavior, update the user-facing documentation in README and/or RUNBOOK if needed.
- Respect the distinction between cluster creation, infrastructure installation, certificate issuance, and application deployment.
- Resume modes such as `--skip-cluster`, `--skip-infra`, `--skip-issuer`, and `--skip-app` should remain supported unless intentionally changed.

## Validation

- For shell and installer changes, prefer lightweight validation using `bash -n` or script execution in dry-run mode when appropriate.
- When changing Kubernetes manifests or Helm configuration, verify command semantics rather than assuming they are correct.
- Prefer commands that check cluster readiness over broad or noisy output.

## Documentation Style

- Keep documentation concise and operational.
- Prefer command examples in Bash blocks.
- Call out prerequisites and assumptions clearly.
- If a feature affects the install flow, document it in the README and/or RUNBOOK.

## File Map

- `install.sh`: guided installer and CLI flow
- `uninstall.sh`: guided teardown flow for managed resources
- `Makefile`: infra installation and cleanup targets
- `cluster_issuer.yaml`: TLS issuer manifest
- `johnny-5-alive/.helm`: sample app chart
- `README.md`: project overview and quick-start flow
- `RUNBOOK.md`: manual troubleshooting and recovery steps
