# Deploying the Authenticator Service Alongside Conjur

This document describes how to obtain, deploy and configure the **Authenticator Service** so it can be used by Conjur

## Table of Contents
1. [Overview](#1-overview)
2. [Getting the Authenticator Service Binary](#2-getting-the-authenticator-service-binary)
3. [Security Best Practices](#3-security-best-practices)
4. [Conjur Configuration Parameters](#4-conjur-configuration-parameters)
5. [Deployment](#5-deployment)
6. [Authenticator Service configuration](#6-authenticator-service-configuration)
7. [Docker Compose Example](#7-docker-compose-example)
8. [Compatibility Matrix](#8-compatibility-matrix)
9. [Certificate Authenticator Configuration Guide](#9-certificate-authenticator-configuration-guide)

---

## 1. Overview

The **Authenticator Service** is a stateless HTTP service that Conjur uses to validate credentials (e.g., for certificate authentication).  
Users are responsible for deploying and managing the service in their own environment. 

---

## 2. Getting the Authenticator Service Binary

The authenticator binary will be included with Conjur releases and made available through GitHub releases. 
For guaranteed compatibility, always use the version of the Authenticator Service that is published in the same release
as your specific Conjur version.

---

## 3. Security Best Practices

### Network Isolation: The SaaS Authenticator should only be accessible to Conjur
- Use localhost for same-host deployments (on default HTTP allowlist)
- Use pod-local networking in Kubernetes (processes running in different containers in the same pod can communicate with each other over localhost)
- Use Docker internal networks in Docker Compose (add service name to HTTP allowlist)

### Connection Security Model:
- Trusted networks (HTTP): Use HTTP only within trusted boundaries.
- Untrusted networks (HTTPS): Use HTTPS with certificate verification.
- No bypass: HTTPS certificate verification cannot be disabled. If you need unencrypted communication, use HTTP with an explicit allowlist entry.

### Firewall 
Do not expose SaaS Authenticator ports publicly. Unnecessary exposure opens the door to potential denial of service.

---

## 4. Conjur Configuration Parameters

In order to enable and configure Conjur to use the Authenticator Service, a set of environment variables must be set.

| Parameter                                      | Purpose                                                                                                                           | Default                                           | Example                  |
|------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------|--------------------------|
| `CONJUR_FEATURE_AUTHENTICATOR_SERVICE_ENABLED` | Feature flag that enables the Authenticator Service                                                                               | true                                              | true                     |
| `CONJUR_AUTHENTICATOR_SERVICE_URL`             | URL of your authenticator service (HTTP or HTTPS)\. Must be HTTPS unless allow\-listed\.                                          | http://localhost:5681                             | http://auth-service:8080 |
| `CONJUR_AUTHENTICATOR_SERVICE_HTTP_ALLOWLIST`  | Comma\-separated list of hostnames/IPs allowed for HTTP communication with the authenticator service\. Required if using HTTP\.   | localhost,127\.0\.0\.1,::1,host\.docker\.internal | auth-service             |
| `CONJUR_AUTHENTICATOR_SERVICE_CA_CERT`         | A path to CA certificate that Conjur uses to validate the TLS certificate of the Authenticator Service\. Required if using HTTPS  | nil                                               | /path/to/ca\.pem         |


---

## 5 Deployment

Common deployment approaches include:

- As a Docker Compose service within a trusted network boundary
- As a standalone HTTP(S) service
- As a sidecar container (Kubernetes)
---

## 6. Authenticator Service configuration

The Authenticator Service binary has to be run with a configuration file provided as a command-line argument. The absolute minimum configuration has to include the `port` and `http_timeout` parameters.

The configuration file is a json file with the following structure:


```json
{
  // Enables debug mode
  "debug": true,

  // Sets the HTTP server listening port
  "port": "8080",

  // Sets the HTTP server timeout
  "http_timeout": "10s",

  // Feature flag for the legacy JWT behavior allowing missing issuer/audience values
  "allow_missing_jwt_claims": false
}
```

Assuming your config file is named `authenticator-config.json`, you can run the Authenticator Service binary as follows:

```bash
$ ./authenticator-service-binary -c /path/to/authenticator-config.json
```

## 7. Docker Compose Example

Assuming you have created a Dockerfile for the Authenticator Service, you can add it as a service in your `docker-compose.yml` and configure Conjur to communicate with it over HTTP within the Docker network:

```yaml
services:
  conjur:
    image: cyberark/conjur
    environment:
      CONJUR_FEATURE_AUTHENTICATOR_SERVICE_ENABLED: 'true'
      CONJUR_AUTHENTICATOR_SERVICE_URL: 'http://auth-service:8080'
      CONJUR_AUTHENTICATOR_SERVICE_HTTP_ALLOWLIST: 'auth-service'
  #...

  auth-service:
     build:
      context: ./auth-service
      dockerfile: Dockerfile
      # No ports exposed - only accessible via Docker network
      
```

## 8. Compatibility Matrix

The following table shows the compatibility between Conjur OSS and the Authenticator Service:

| Authenticator Service / Conjur OSS | 1.25.x |
|------------------------------------|--------|
| 1.400.0                            | ✓      |

## 9. Certificate Authenticator Configuration Guide

For detailed instructions on configuration, setup, and usage of the Certificate Authenticator, see the [Certificate Authenticator Configuration Guide](CERTIFICATE_AUTH.md).
