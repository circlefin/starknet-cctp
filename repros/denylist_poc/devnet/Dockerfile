# Build Starknet devnet from source (official repo)
ARG DEVNET_VERSION=v0.6.1

FROM rust:1.89-alpine3.21 AS builder
ARG DEVNET_VERSION

RUN apk update && \
    apk add --no-cache pkgconfig make musl-dev openssl-dev perl git

RUN git clone --depth 1 --branch ${DEVNET_VERSION} https://github.com/0xSpaceShard/starknet-devnet.git /src
WORKDIR /src
RUN cargo build --bin starknet-devnet --release

FROM alpine:3.21
RUN apk add --no-cache tini ca-certificates
COPY --from=builder /src/target/release/starknet-devnet /usr/local/bin/starknet-devnet

EXPOSE 5050

ENTRYPOINT ["tini","--","starknet-devnet"]
CMD ["--host","0.0.0.0","--seed","0","--port","5050"]
