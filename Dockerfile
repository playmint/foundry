# syntax=docker/dockerfile:1.4

FROM alpine:3.17 as build-environment

ARG TARGETARCH
WORKDIR /opt

RUN apk add clang lld curl build-base linux-headers git \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > rustup.sh \
    && chmod +x ./rustup.sh \
    && ./rustup.sh -y

RUN [[ "$TARGETARCH" = "arm64" ]] && echo "export CFLAGS=-mno-outline-atomics" >> $HOME/.profile || true

WORKDIR /opt/foundry
COPY . .

RUN --mount=type=cache,target=/root/.cargo/registry --mount=type=cache,target=/root/.cargo/git --mount=type=cache,target=/opt/foundry/target \
    source $HOME/.profile && cargo build --release \
    && mkdir out \
    && mv target/release/forge out/forge \
    && mv target/release/cast out/cast \
    && mv target/release/anvil out/anvil \
    && mv target/release/chisel out/chisel \
    && strip out/forge \
    && strip out/cast \
    && strip out/chisel \
    && strip out/anvil;

FROM alpine:3.17 as foundry-client
ARG TARGETARCH
ARG FOUNDRY_SOLC_VERSION=0.8.17

RUN apk add --no-cache linux-headers git libstdc++ libgcc wget

COPY --from=build-environment /opt/foundry/out/forge /usr/local/bin/forge
COPY --from=build-environment /opt/foundry/out/cast /usr/local/bin/cast
COPY --from=build-environment /opt/foundry/out/anvil /usr/local/bin/anvil
COPY --from=build-environment /opt/foundry/out/chisel /usr/local/bin/chisel

RUN \
	apk --no-cache --update add build-base cmake musl-dev curl-dev g++ gcc boost-dev z3-dev z3 boost-static git bash \
	&& wget https://github.com/ethereum/solidity/releases/download/v${FOUNDRY_SOLC_VERSION}/solidity_${FOUNDRY_SOLC_VERSION}.tar.gz \
	&& tar xvzf solidity_${FOUNDRY_SOLC_VERSION}.tar.gz \
	&& ( \
		cd /solidity_${FOUNDRY_SOLC_VERSION} \
		&& mkdir build \
		&& cd build \
		&& cmake -DSTRICT_Z3_VERSION=OFF .. \
		&& make -j4 solc \
		&& mkdir -p /root/.svm/${FOUNDRY_SOLC_VERSION}/ \
		&& mv solc/solc /root/.svm/${FOUNDRY_SOLC_VERSION}/solc-${FOUNDRY_SOLC_VERSION} \
	) \
	&& rm -rf /var/cache/apk/* \
	&& rm -rf solidity_*


RUN adduser -Du 1000 foundry

ENTRYPOINT ["/bin/sh", "-c"]


LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="Foundry" \
      org.label-schema.description="Foundry" \
      org.label-schema.url="https://getfoundry.sh" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/foundry-rs/foundry.git" \
      org.label-schema.vendor="Foundry-rs" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0"
