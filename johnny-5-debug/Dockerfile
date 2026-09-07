FROM alpine:3.20

RUN apk add --no-cache \
  bash \
  bind-tools \
  busybox-extras \
  ca-certificates \
  curl \
  iproute2 \
  iputils \
  jq \
  netcat-openbsd \
  openssl \
  tcpdump \
  wget

ARG TARGETARCH
ARG KUBECTL_VERSION=v1.31.0
ARG HELM_VERSION=v3.16.1
ARG YQ_VERSION=v4.44.3

RUN set -eu; \
  arch="${TARGETARCH:-amd64}"; \
  case "$arch" in \
    amd64) bin_arch="amd64" ;; \
    arm64) bin_arch="arm64" ;; \
    *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
  esac; \
  curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${bin_arch}/kubectl"; \
  chmod +x /usr/local/bin/kubectl; \
  curl -fsSL -o /tmp/helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-linux-${bin_arch}.tar.gz"; \
  tar -xzf /tmp/helm.tar.gz -C /tmp; \
  mv "/tmp/linux-${bin_arch}/helm" /usr/local/bin/helm; \
  chmod +x /usr/local/bin/helm; \
  curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${bin_arch}"; \
  chmod +x /usr/local/bin/yq; \
  rm -rf /tmp/helm.tar.gz "/tmp/linux-${bin_arch}"

WORKDIR /work
CMD ["sh", "-c", "sleep infinity"]
