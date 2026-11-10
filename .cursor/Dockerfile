FROM ubuntu:24.04

# Swift 6.0.3 matches .github/workflows/ci.yml (Linux core tests).
# Toolchain binaries land in /usr/bin so login shells used by install/start can find them.

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        binutils \
        ca-certificates \
        clang \
        curl \
        git \
        gnupg2 \
        libc6-dev \
        libcurl4-openssl-dev \
        libedit2 \
        libgcc-13-dev \
        libncurses-dev \
        libpython3-dev \
        libsqlite3-0 \
        libstdc++-13-dev \
        libxml2-dev \
        libz3-dev \
        pkg-config \
        tzdata \
        unzip \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# gpg exits non-zero when the 6.x release key is untrusted or expired, even if the
# signature matches. Require GOODSIG for fingerprint 52BB7E3D…981F and reject BADSIG.
ARG SWIFT_SIGNING_KEY=52BB7E3DE28A71BE22EC05FFEF80A866B47A981F
ARG SWIFT_VERSION=6.0.3

RUN set -eu; \
    SWIFT_WEBDIR="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/swift-${SWIFT_VERSION}-RELEASE"; \
    SWIFT_BIN_URL="${SWIFT_WEBDIR}/swift-${SWIFT_VERSION}-RELEASE-ubuntu24.04.tar.gz"; \
    curl -fsSL "$SWIFT_BIN_URL" -o /tmp/swift.tar.gz; \
    curl -fsSL "${SWIFT_BIN_URL}.sig" -o /tmp/swift.tar.gz.sig; \
    curl -fsSL https://swift.org/keys/release-key-swift-6.x.asc -o /tmp/swift-release.asc; \
    GNUPGHOME="$(mktemp -d)"; \
    export GNUPGHOME; \
    gpg --batch --import /tmp/swift-release.asc; \
    fp="$(gpg --batch --with-colons --fingerprint "$SWIFT_SIGNING_KEY" | awk -F: '/^fpr:/ {print $10; exit}')"; \
    test "$fp" = "$SWIFT_SIGNING_KEY"; \
    status="$(gpg --batch --status-fd 1 --verify /tmp/swift.tar.gz.sig /tmp/swift.tar.gz || true)"; \
    printf '%s\n' "$status"; \
    if printf '%s\n' "$status" | grep -Eq 'BADSIG|ERRSIG|NODATA|NO_PUBKEY'; then \
        echo "Swift toolchain signature failed" >&2; \
        exit 1; \
    fi; \
    printf '%s\n' "$status" | grep -q '^\[GNUPG:\] GOODSIG '; \
    tar -xzf /tmp/swift.tar.gz --directory / --strip-components=1; \
    chmod -R o+r /usr/lib/swift; \
    rm -rf "$GNUPGHOME" /tmp/swift.tar.gz /tmp/swift.tar.gz.sig /tmp/swift-release.asc; \
    swift --version; \
    clang --version

USER ubuntu
