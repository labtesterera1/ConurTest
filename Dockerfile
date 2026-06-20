# kics-scan disable=fd54f200-402c-4333-a5a4-36ef6709af2f
ARG BASE_TAG=latest
ARG REGISTRY=docker.io

FROM ${REGISTRY}/cyberark/ubuntu-ruby-builder:${BASE_TAG} AS builder

ENV CONJUR_HOME=/opt/conjur-server

WORKDIR ${CONJUR_HOME}

COPY Gemfile Gemfile.lock ./
COPY ./gems/ ./gems/

RUN bundle config set --local without 'test development' && \
    bundle config set --local deployment true && \
    bundle config set --local path /usr/local/bundle && \
    bundle config --local jobs "$(nproc --all)" && \
    bundle install --prefer-local && \
    # Remove private keys brought in by gems in their test data
    find / -name 'openid_connect-*' -type d -exec find {} -name '*.pem' -type f -delete \; && \
    find / -name 'httpclient-*' -type d -exec find {} -name '*.key' -type f -delete \; && \
    find / -name 'httpclient-*' -type d -exec find {} -name '*.pem' -type f -delete \;

# Cleanup any plugin data from bundle
RUN rm -rf .bundle/plugin

FROM ${REGISTRY}/cyberark/ubuntu-ruby-fips:${BASE_TAG}

ENV PORT=80 \
    LOG_DIR=${CONJUR_HOME}/log \
    TMP_DIR=${CONJUR_HOME}/tmp \
    SSL_CERT_DIRECTORY=/opt/conjur/etc/ssl \
    RAILS_ENV=production \
    CONJUR_HOME=/opt/conjur-server

ENV PATH="${PATH}:${CONJUR_HOME}/bin"

WORKDIR ${CONJUR_HOME}

# Ensure few required GID0-owned folders to run as a random UID (OpenShift requirement)
RUN mkdir -p $TMP_DIR \
             $LOG_DIR \
             $SSL_CERT_DIRECTORY/ca \
             $SSL_CERT_DIRECTORY/cert \
             /run/authn-local

COPY . .
COPY --from=builder ${CONJUR_HOME} ${CONJUR_HOME}
COPY --from=builder /usr/local/bundle /usr/local/bundle

EXPOSE ${PORT}

ENTRYPOINT [ "conjurctl" ]
