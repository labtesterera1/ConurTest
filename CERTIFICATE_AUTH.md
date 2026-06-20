# Configure Certificate Authentication

This guide describes how to create, configure, and use a Certificate Authenticator in Conjur Secrets Manager, including secret retrieval.

This guide is for demonstration purposes only. It does not contain security best practices such as encrypting keys, setting file system permissions, and securing sensitive data.
If you create certificates for your environment, make sure they meet your organization's security requirements.

## Before You Begin
To perform the steps in this guide, you need:
- OpenSSL
- Secrets Manager CLI

---

## Table of Contents
1. [Overview](#1-overview)
   - [TLS termination](#11-tls-termination)
   - [Trusted Proxy Configuration](#12-trusted-proxy-configuration)
   - [Authentication Flow](#13-certificate-authentication-flow)
2. [Configuration Options](#2-configuration-options)
    - [Variables](#21-variables)
    - [Host Annotations](#22-host-annotations)
    - [Host Modes](#23-host-modes)
        - [Request](#request)
        - [SPIFFE](#spiffe)
3. [Create Certificates](#3-create-certificates)
    - [Create a root CA Certificate](#31-create-a-root-ca-certificate)
        - [Create the CA private key](#311-create-the-ca-private-key)
        - [Create openSSL extension file](#312-create-openssl-extension-file)
        - [Create the certificate signing request](#313-create-the-certificate-signing-request)
        - [Create the CA certificate](#314-create-the-ca-certificate)
    - [Create a client certificate](#32-create-a-client-certificate)
        - [Create a private key](#321-create-a-private-key)
        - [Create the client signing request](#322-create-the-client-signing-request)
        - [Create the client extension file](#323-create-the-client-extension-file)
        - [Create and sign the client certificate](#324-create-and-sign-the-client-certificate)
4. [Example 1: Authenticator in Host Mode](#4-example-1-authenticator-in-host-mode)
    - [Create the Authenticator Policy](#41-create-the-authenticator-policy)
    - [Set Authenticator Variables](#42-set-authenticator-variables)
    - [Enable the Authenticator](#43-enable-the-authenticator)
    - [Configure a Workload](#44-configure-a-workload)
        - [Create the Workload Policy](#441-create-the-workload-policy)
        - [Grant Workload Access to the Authenticator](#442-grant-workload-access-to-the-authenticator)
    - [Authenticate with the Authenticator](#45-authenticate-with-the-authenticator)
    - [Retrieve a Secret](#46-retrieve-a-secret)
        - [Create a Secret (Variable)](#461-create-a-secret-variable)
        - [Set the Secret Value](#462-set-the-secret-value)
        - [Retrieve the Secret](#463-retrieve-the-secret)
    - [Troubleshooting & Tips](#47-troubleshooting--tips)
5. [Example 2: Authenticator in Spiffe Mode](#5-example-2-authenticator-in-spiffe-mode)
    - [Create the Authenticator Policy](#51-create-the-authenticator-policy)
    - [Set Authenticator Variables](#52-set-authenticator-variables)
    - [Enable the Authenticator](#53-enable-the-authenticator)
    - [Configure a Workload](#54-configure-a-workload)
        - [Create the Workload Policy](#541-create-the-workload-policy)
        - [Grant Workload Access to the Authenticator](#542-grant-workload-access-to-the-authenticator)
    - [Authenticate with the Authenticator](#55-authenticate-with-the-authenticator)
    - [Retrieve a Secret](#56-retrieve-a-secret)
        - [Create a Secret (Variable)](#561-create-a-secret-variable)
        - [Set the Secret Value](#562-set-the-secret-value)
        - [Retrieve the Secret](#563-retrieve-the-secret)
    - [Troubleshooting & Tips](#57-troubleshooting--tips)

---

## 1. Overview

The Certificate Authenticator is a Secrets Manager component that allows workloads to authenticate using X.509 client certificates. 
It validates presented certificates against a trusted CA chain and configurable restrictions, and maps authenticated certificates to Secrets Manager roles based on the request path or SPIFFE IDs.


### 1.1 TLS termination

Certificate authentication requires a **trusted TLS terminator** (such as NGINX) in front of Conjur.
The client must present its certificate as part of a **TLS handshake** with that terminator. This handshake is where
clients prove ownership of the private key associated with the certificate.

A valid deployment must ensure that:
- Clients present certificates during a TLS handshake with the TLS terminator
- The TLS terminator proxy injects the client certificate into `X-SSL-Client-Certificate` for the authentication request

### 1.2 Trusted Proxy Configuration

When using certificate authentication with a TLS terminator that forwards client
certificates via HTTP headers, Conjur must be configured to **trust only specific
proxy addresses**.

To enforce this trust boundary, Conjur supports a trusted proxy allowlist
(`TRUSTED_PROXIES` environment variable), which restricts which source IP addresses are permitted to
supply proxy-injected headers such as `X-SSL-Client-Certificate`.

A valid deployment must ensure that:
- The TLS terminator’s IP address is included in the trusted proxy allowlist
- Direct connections from workloads to Conjur are not trusted to supply proxy headers
- Requests originating from untrusted IPs cannot inject authentication metadata

Without a trusted proxy allowlist in place, Conjur cannot safely distinguish
proxy‑forwarded authentication metadata from client‑supplied headers.
In such cases, proxy‑injected headers must not be considered secure.

### 1.3 Certificate Authentication Flow

Authentication is performed by calling the certificate authenticator’s
`authenticate` endpoint. Requests are forwarded through a trusted TLS terminator,
which is responsible for establishing cryptographic trust with the client.

The authentication flow consists of the following steps:

1. The workload establishes a TLS connection to a trusted proxy (for example, NGINX)
   and presents its client certificate during the TLS handshake.
2. The proxy terminates TLS and extracts the client certificate from the handshake.
3. The proxy forwards the authentication request to Conjur and injects the extracted
   certificate into the `X-SSL-Client-Certificate` HTTP header.
4. Conjur authenticates the request by validating the certificate against the
   certificate authenticator configuration and policy.
5. If authentication is successful, Conjur returns an authentication token that the
   workload can use to retrieve secrets.

## 2. Configuration Options

The certificate authenticator is configured through a combination of authenticator‑level
variables and host‑level annotations. Together, these settings define how client
certificates are validated.

Authenticator variables control global behavior such as trusted certificate authorities,
revocation handling, and identity mapping mode. Host annotations apply additional
restrictions to individual workloads and are evaluated during authentication.

This section describes the available configuration options.


### 2.1 Variables

| Variable Name   | Required                     | Default   | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
|-----------------|------------------------------|-----------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `ca-cert`       | Yes                          |           | A chain of trusted, PEM encoded CA certificates.<br><br>The chain must contain exactly one self-signed root CA certificate. If the bundle contains more or less than one root CA, authentication will always fail.<br><br>The chain may contain additional intermediate CA certificates. If an intermediate CA in the bundle cannot trace trust to the bundle's single root CA, then it is ignored.<br><br>This variable is the only source of trusted CA certificates during the authentication process. System CA certificates are never used to establish trust.<br><br>In order for a client certificate to be authenticated, it must be signed by one of the CA certificates in the chain, and a chain of trust must be established to the single root CA. |                                                               
| `crl`           | No                           |           | A PEM encoded X.509 certificate revocation list. <br><br>The CRL must be signed by one of the CA certificates in the trusted chain, and a chain of trust must be established to the single self-signed root CA.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `crl-url`       | No                           |           | An HTTP or HTTPS URL to a remote PEM encoded X.509 certificate revocation list.<br><br>The CRL must be signed by one of the CA certificates in the trusted chain, and a chain of trust must be established to the single self-signed root CA.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `host-mode`     | No                           | `request` | Indicates how the certificate authenticator will map an X.509 certificate to a Secrets Manager role.<br><br>By default (if this variable is missing or empty) or if the variable is set to the value request , the full role identifier must be present in the authentication request path.<br><br>If this variable is set to the value spiffe , the presented credential must be a valid X.509 SVID and the role identifier will be derived form the included SPIFFE ID.                                                                                                                                                                                                                                                                                       |
| `trust-domain`  | Yes when host-mode is spiffe |           | SPIFFE IDs parsed from valid X.509 SVIDs must include a trust domain portion that matches the value of this variable exactly.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `identity-path` | Yes when host-mode is spiffe |           | Roles derived from SPIFFE IDs must be created in the policy path specified by this variable.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `san-uri`       | No                           |           | Restricts the set of valid client certificates to those that contain URI SANs that match the entries in the list.<br><br>Value is a comma-delimited list of URIs. Entries can contain wildcards, according to certain rules:<br>&nbsp;&nbsp;\- Wildcards must replace an entire segment<br>&nbsp;&nbsp;\- No recursive wildcards allowed<br>&nbsp;&nbsp;\- Scheme cannot contain wildcards<br>&nbsp;&nbsp;\- Authority part of the URI cannot contain wildcards<br>&nbsp;&nbsp;\- SPIFFE IDs cannot contain wildcards                                                                                                                                                                                                                                           |
| `san-dns`       | No                           |           | Restricts the set of valid client certificates to those that contain DNS Name SANs that match the entries in the list.<br><br>Value is a comma-delimited list of DNS Names. Entries can contain wildcards, according to certain rules:<br>&nbsp;&nbsp;\- Wildcards can appear at the beginning of a segment or replace the entire segment<br>&nbsp;&nbsp;\- No recursive wildcards allowed<br>&nbsp;&nbsp;\- Effective Top-level domain +1 cannot contain wildcards<br>&nbsp;&nbsp;\- Wildcards may replace an entire subdomain                                                                                                                                                                                                                                 |
| `san-ip`        | No                           |           | Restricts the set of valid client certificates to those that contain IP Address SANs that match the entries in the list.<br><br>Value is a comma-delimited list of IP Addresses. Entries cannot contain wildcards.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `cn`            | No                           |           | Restricts the set of valid client certificates to those that contain a Common Name that matches the entry.<br><br>Value is a single Common Name. Entry can contain wildcards, according to certain rules:<br>&nbsp;&nbsp;\- Only domain names supported e.g. api.example.com<br>&nbsp;&nbsp;\- Wildcards can appear at the beginning of a segment or replace the entire segment<br>&nbsp;&nbsp;\- No recursive wildcards allowed<br>&nbsp;&nbsp;\- Effective Top-level domain +1 cannot contain wildcards<br>&nbsp;&nbsp;\- Wildcards may replace an entire subdomain                                                                                                                                                                                           |

### 2.2 Host Annotations

When a host authenticates with Conjur via certificate authentication, it is subject to a set of restrictions. These are defined on the host as annotations and evaluated on an authentication attempt.

Annotations that do not include a service ID are global, and apply to all certificate authenticator instances. Annotations that include a service ID apply only to the specified service. If a global and specific annotation exist for the same restriction (i.e. authn-cert/san-uri and authn-cert/my-service/san-uri) then the specific annotation is used.

| Annotation                               | Description                                                                                                                                                                                                                                                  |
|------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `authn-cert/<authenticator-id>/san-uri ` | A comma-delimited list of URIs.<br><br>All URIs in the list must be present in the authenticating client certificate's URI Subject Alternative Names. If a URI included in the annotation is not present in the URI SANs, authentication fails.              |
| `authn-cert/<authenticator-id>/san-dns ` | A comma-delimited list of DNS names.<br><br>All names in the list must be present in the authenticating client certificate's DNS Name Subject Alternative Names. If a name included in the annotation is not present in the DNS SANs, authentication fails.  |
| `authn-cert/<authenticator-id>/san-ip `  | A comma-delimited list of IP addresses.<br><br>All IPs in the list must be present in the authenticating client certificate's IP Address Subject Alternative Names. If an IP included in the annotation is not present in the IP SANs, authentication fails. |
| `authn-cert/<authenticator-id>/cn `      | A string representing an X.509 Common Name.<br><br>The name in the variable must match the Common Name on the authenticating client certificate.                                                                                                             |

### 2.3 Host Modes

The certificate authenticator has two operating modes that determine how client certificates are mapped to Secrets Manager roles and how authentication requests must be structured. The mode is determined by the value of the `host-mode` variable.

#### Request

The certificate authenticator's default operating mode. This mode aligns with existing Secrets Manager authenticators by
accepting a role identifier as input. Successful authentication in this mode depends on:

The API request including a role identifier as part of the request path.
The presented client certificate having been signed by a member of the trusted CA chain.
The presented client certificate having attributes that match pre-existing configuration on the specified role.

#### SPIFFE

The Secure Production Identity Framework For Everyone (SPIFFE) Project is a set of standards for identifying and
securing communications between application services. Secrets Manager's certificate authenticator has dedicated
operating mode to natively support X.509 SPIFFE Verifiable Documents (SVIDs) and map SVIDs to Secrets Manager roles
automatically. Successful authentication in this mode depends on:

The presented SVID having been signed by a member of the trusted CA chain.
The SPIFFE ID in the presented SVID containing an expected trust domain.
The SPIFFE ID in the presented SVID containing a workload ID that maps successfully to an existing role.
The SVID having attributes that match pre-existing configuration on the derived role.
This mode can be used by setting the host-mode configuration variable to the value spiffe .

## 3. Create Certificates

### 3.1. Create a root CA Certificate

Create self-signed CA certificate that is used to configure the Secrets Manager certificate authenticator.

#### 3.1.1 Create the CA private key

To create a private key for the CA certificate run:

```bash
openssl genrsa -out rootCA.key 4096
```

#### 3.1.2. Create openSSL extension file

Create a file named `ca-ext.cnf` with the following content:

```
[v3_ca]
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
```

#### 3.1.3. Create the certificate signing request

To create the CSR, run:

```bash
openssl req -new -sha256 -key rootCA.key -out ca.csr \
  -subj "/C=US/O=MyOrg/OU=dev/CN=MyOrg Root CA"
```

#### 3.1.4. Create the CA certificate

To create the CA certificate, run:

```bash
openssl x509 -req -in ca.csr -signkey rootCA.key -sha256 -days 3650 \
  -extfile ca-ext.cnf -extensions v3_ca \
  -out rootCA.pem
```

The CA certificate is saved in the rootCA.pem file

### 3.2 Create a client certificate

Create a client certificate that is used to authenticate the workload.

#### 3.2.1 Create a private key

To create a private key for the client certificate run:

```bash
openssl genrsa -out my-workload.key 2048
```

#### 3.2.2 Create the client signing request

To create the CSR, run:

```bash
openssl req -new -sha256 -key my-workload.key -out my-workload.csr \
  -subj "/C=US/O=MyOrg/OU=Ops/CN=my-workload"
```

#### 3.2.3 Create the client extension file

Create a file named `client-ext.cnf` with the following content:

```
[v3_client]
basicConstraints = CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
subjectAltName = @alt

[alt]
URI.1 = spiffe://my-workload.dev/my-spiffe-workload
DNS.1 = my-workload.dev
```

> **Note**
>
> The subject alternative names (SANs):
> 
> - URI (line 10): spiffe://my-workload.dev/my-spiffe-workload (You can ignore it for now, will be used later in the spiffe mode example)
> - DNS (line 11): my-workload.dev
>
> These values will be embedded into the client certificate and used when your workload authenticates to Conjur.
> In the following example only DNS is specified in the workload policy, but you can choose to use any of the supported SAN types or the common name instead.

#### 3.2.4 Create and sign the client certificate

To create the client certificate, run:

```bash
openssl x509 -req -in my-workload.csr -sha256 -days 825 \
  -CA rootCA.pem -CAkey rootCA.key -CAcreateserial \
  -extfile client-ext.cnf -extensions v3_client \
  -out my-workload.pem
```

The client certificate is saved in the my-workload.pem file.

## 4. Example 1: Authenticator in Host Mode

This example demonstrates how to configure the certificate authenticator in host mode and configure a workload to
authenticate with a client certificate.

### 4.1. Create the Authenticator Policy

Create a policy file named `cert-auth.yaml` with the following content:

```yaml
- !policy
  id: conjur/authn-cert/<authenticator-id>
  body:
    - !webservice

    - !variable ca-cert
    # - !variable crl
    # - !variable crl-url

    - !group apps
    - !permit
      role: !group apps
      privilege: [ read, authenticate ]
      resource: !webservice

    - !group operators
    - !permit
      role: !group operators
      privilege: [ read, update ]
      resource: !webservice
```

> **Note**
> 
> - Replace `<authenticator-id>` with a unique name for your certificate authenticator (e.g., `my-cert-auth`).
> - The `ca-cert` variable is required. You may provide either `crl` **or** `crl-url` (not both).
> - `apps` group: workloads that can authenticate with this authenticator.
> - `operators` group: users who can manage the authenticator.

- **Load the policy file to the `root` branch:**

```bash
conjur policy load -f cert-auth.yaml -b root
```

### 4.2. Set Authenticator Variables

- **Set the `ca-cert` variable:**

```bash
conjur variable set -i conjur/authn-cert/<authenticator-id>/ca-cert -v "$(cat <rootCA.pem>)"
```

Where:

- `<authenticator-id>`: The name you used in the policy (e.g., `my-cert-auth`).
- `<rootCA.pem>`: The CA root and intermediate certificates in PEM format.

### 4.3. Enable the Authenticator

You must enable the authenticator before it can be used. Add it to the `CONJUR_AUTHENTICATORS` environment variable:

- This variable is a comma-separated list.
- You must include the authenticator's ID in the list.

CONJUR_AUTHENTICATORS=authn-jwt/my-jwt-auth,authn-cert/my-cert-auth

### 4.4. Configure a Workload

#### 4.4.1. Create the Workload Policy

Create a policy file named `cert-workload.yaml` with the following content:

```yaml
- !policy
  id: <workload-namespace>
  body:
    - !host
      id: <workload-name>
      annotations:
        authn-cert/<authenticator-id>/san-dns: <san-dns>
        # authn-cert/<authenticator-id>/san-uri: <san-uri>
        # authn-cert/<authenticator-id>/san-dns: <san-dns>
        # authn-cert/<authenticator-id>/san-ip: <san-ip>
        # authn-cert/<authenticator-id>/cn: <common-name>
```

> **Note**
>
> - Replace `<workload-namespace>` (e.g., `my-workloads`) and `<workload-name>` (e.g., `my-workload`). and <san_dns> (e.g., `my-workload.dev`).
> - At least one annotation is required for authentication.
> - The annotation key must match the authenticator ID exactly as defined in the previous step.
> - The annotation value(s) must match the corresponding field in the client certificate presented during authentication. For example, if you use the `san-dns` annotation with the value `my-workload.dev`, then the client certificate must contain a DNS SAN with the value `my-workload.dev` in order for authentication to succeed.

**Load the policy file:**

```bash
conjur policy load -f cert-workload.yaml -b root
```

#### 4.4.2. Grant Workload Access to the Authenticator

Create a grant policy file (e.g., `cert-workload-grant.yaml`):

```yaml
- !grant
  role: !group conjur/authn-cert/<authenticator-id>/apps
  member: !host <workload-namespace>/<workload-name>
```

> **Note**
>
> The grant must match the group and host names exactly as defined in previous steps.

**Load the grant policy:**

```bash
conjur policy load -f cert-workload-grant.yaml -b root
```

### 4.5. Authenticate with the Authenticator

Authentication follows the common certificate authentication flow described in [Certificate Authentication Flow](#13-certificate-authentication-flow).

In request (host) mode, the workload identity is provided explicitly in the request path.

**Endpoint format:**

```
POST <conjur-server-hostname>/authn-cert/<authenticator-id>/<account>/<host-id>/authenticate
```

Where:

- `<conjur-server-hostname>`: Hostname of the exposed Conjur server (e.g., `https://conjur:3000`)
- `<authenticator-id>`: Name of the authenticator (e.g., `my-cert-auth`)
- `<account>`: Conjur account name (e.g., `cucumber`)
- `<host-id>`: Workload host ID (e.g., `host/my-workloads/my-workload`)

**Example successful response:**

```json
{
  "protected": "eyJh...",
  "payload": "eyJp...",
  "signature": "VUA..."
}
```

### 4.6. Retrieve a Secret

This section demonstrates how to create a secret in Conjur with the CLI and retrieve it using the API and the token
obtained from the certificate authentication process.

#### 4.6.1. Create a Secret (Variable)

Create a policy file named `app-secrets.yaml` which defines a variable to hold the secret value and grants the workload
access to it:

```yaml
# Create the secret
- !policy
  id: app-secrets
  body:
    - !variable db-password

# Grant the workload access to the secret
- !permit
  role: !host <workload-namespace>/<workload-name>
  privilege: [ read, execute ]
  resource: !variable app-secrets/db-password
```

> **Note**
> 
> Replace `<workload-namespace>` (e.g., `my-workloads`) and `<workload-name>` (e.g., `my-workload`).

```bash
conjur policy load -f app-secrets.yaml -b root
```

#### 4.6.2. Set the Secret Value

```bash
conjur variable set -i app-secrets/db-password -v "super-secret-password"
```

#### 4.6.3. Retrieve the Secret

Extract the body response from the authentication request

**Example:**

```bash
TOKEN_RAW=$(curl -X POST "https://conjur:3000/authn-cert/my-cert-auth/cucumber/host%2Fmy-workloads%2Fmy-workload/authenticate")
```

Encode the token in base64:

```bash
TOKEN_B64=$(echo -n "$TOKEN_RAW" | base64 | tr -d '\n')
```

Retrieve the secret using the API and the token:

**Endpoint format:**

```
GET <conjur-server-hostname>/secrets/<account>/<kind>/<identifier><?version>
```

Where:

- `<conjur-server-hostname>`: Hostname of the exposed Conjur server(e.g., `https://conjur:3000`)
- `<kind>`: The kind of a resource (e.g., `variable`)
- `<account>`: Conjur account name (e.g., `cucumber`)
- `<identifier>`: Id of the variable (e.g., `app-secrets/db-password`)
- `version` (optional): The version of the secret to retrieve (e.g., `?version=1`)

**Example:**

```bash
curl -H "Authorization: Token token=\"${TOKEN_B64}\"" https://conjur:3000/secrets/cucumber/variable/app-secrets/db-password
```

### 4.7. Troubleshooting & Tips

- Use consistent names for `<authenticator-id>` and `<workload-name>` across all steps.
- Only one of `crl` or `crl-url` should be set for the authenticator.
- Always URL-encode the certificate before sending it in the header.
- If you receive a 401 Unauthorized error, check that the authenticator is enabled and the workload is properly granted
  access.

## 5. Example 2: Authenticator in Spiffe Mode

This example demonstrates how to configure the certificate authenticator in spiffe mode and configure a workload to
authenticate with a client certificate based on a spiffe SAN URI.

### 5.1. Create the Authenticator Policy

Create a policy file named `cert-auth-spiffe.yaml` with the following content:

```yaml
- !policy
  id: authn-cert/<authenticator-id>
  body:
    - !webservice

    - !variable ca-cert
    # - !variable crl
    # - !variable crl-url
    - !variable host-mode
    - !variable trust-domain
    - !variable identity-path
    - !variable san-uri

    - !group apps
    - !permit
      role: !group apps
      privilege: [ read, authenticate ]
      resource: !webservice

    - !group operators
    - !permit
      role: !group operators
      privilege: [ read, update ]
      resource: !webservice
```

> **Note**
> 
> Replace `<authenticator-id>` with a unique name for your certificate authenticator (e.g., `my-spiffe-auth`).

- **Load the policy file to the `root` branch:**

```bash
conjur policy load -f cert-auth-spiffe.yaml -b root
```

### 5.2. Set Authenticator Variables

- **Set the `ca-cert` variable:**

```bash
conjur variable set -i conjur/authn-cert/<authenticator-id>/ca-cert -v "$(cat <rootCA.pem>)"
```

Where:

- `<authenticator-id>`: The name you used in the policy (e.g., `my-spiffe-auth`).
- `<rootCA.pem>`: The CA root and intermediate certificates in PEM format.

### 5.3. Enable the Authenticator

You must enable the authenticator before it can be used. Add it to the `CONJUR_AUTHENTICATORS` environment variable:

- This variable is a comma-separated list.
- You must include the authenticator's ID in the list.
- Assuming you have the authenticator from the previous example enabled as well, the environment variable would look
  like this:

CONJUR_AUTHENTICATORS=authn-jwt/my-jwt-auth,authn-cert/my-cert-auth,authn-cert/my-spiffe-auth

### 5.4. Configure a Workload

#### 5.4.1. Create the Workload Policy

Create a policy file named `cert-workload-spiffe.yaml` with the following content:

```yaml
- !policy
  id: <workload-namespace>
  body:
    - !host
      id: <workload-name>
```

> **Note**
>
> Replace `<workload-namespace>` (e.g., `my-workloads`) and `<workload-name>` (e.g., `my-spiffe-workload).

**Load the policy file:**

```bash
conjur policy load -f cert-workload-spiffe.yaml -b root
```

#### 5.4.2. Grant Workload Access to the Authenticator

Create a grant policy file (e.g., `cert-workload-grant-spiffe.yaml`):

```yaml
- !grant
  role: !group conjur/authn-cert/<authenticator-id>/apps
  member: !host <workload-namespace>/<workload-name>
```

> **Note**
>
> The grant must match the group and host names exactly as defined in previous steps. (for example: <workload-namespace> = `my-workloads/spiffe`, <workload-name> = `my-spiffe-workload`, <authenticator-id> =`my-spiffe-auth`)

**Load the grant policy:**

```bash
conjur policy load -f cert-workload-grant-spiffe.yaml -b root
```

### 5.5. Authenticate with the Authenticator

Authentication follows the common certificate authentication flow described in [Certificate Authentication Flow](#13-certificate-authentication-flow).

In SPIFFE mode, the workload identity is derived from the SPIFFE ID specified in the client's certificate’s SAN URI.

**Endpoint format (SPIFFE mode):**

```
POST <conjur-server-hostname>/authn-cert/<authenticator-id>/<account>/authenticate
```
Where:

- `<conjur-server-hostname>`: Hostname of the exposed Conjur server (e.g., `https://conjur:3000`)
- `<authenticator-id>`: Name of the authenticator (e.g., `my-spiffe-auth`)
- `<account>`: Conjur account name (e.g., `cucumber`)

**Send the authentication request:**

```bash
curl -X POST "https://conjur:3000/authn-cert/my-cert-auth/cucumber/authenticate"
```

**Example successful response:**

```json
{
  "protected": "eyJh...",
  "payload": "eyJp...",
  "signature": "VUA..."
}
```

### 5.6. Retrieve a Secret

This section demonstrates how to create a secret in Conjur with the CLI and retrieve it using the API and the token
obtained from the certificate authentication process.

#### 5.6.1. Create a Secret (Variable)

Create a policy file named `app-secrets-spiffe.yaml` which defines a variable to hold the secret value and grants the
workload access to it:

```yaml
# Create the secret
- !policy
  id: app-secrets
  body:
    - !variable db-password

# Grant the workload access to the secret
- !permit
  role: !host <workload-namespace>/<workload-name>
  privilege: [ read, execute ]
  resource: !variable app-secrets/db-password
```

> **Note**
>
> Replace `<workload-namespace>` (e.g., `my-workloads/spiffe`) and `<workload-name>` (e.g., `my-spiffe-workload`).

```bash
conjur policy load -f app-secrets-spiffe.yaml -b root
```

#### 5.6.2. Set the Secret Value

```bash
conjur variable set -i app-secrets/db-password -v "super-secret-password"
```

#### 5.6.3. Retrieve the Secret

Extract the body response from the authentication request

**Example:**

```bash
TOKEN_RAW=$(curl -X POST "https://conjur:3000/authn-cert/my-cert-auth/cucumber/authenticate")
```

Encode the token in base64:

```bash
TOKEN_B64=$(echo -n "$TOKEN_RAW" | base64 | tr -d '\n')
```

Retrieve the secret using the API and the token:

**Endpoint format:**

```
GET <conjur-server-hostname>/secrets/<account>/<kind>/<identifier><?version>
```

Where:

- `<conjur-server-hostname>`: Hostname of the exposed Conjur server (e.g., `https://conjur:3000`)
- `<kind>`: The kind of a resource (e.g., `variable`)
- `<account>`: Conjur account name (e.g., `cucumber`)
- `<identifier>`: Id of the variable (e.g., `app-secrets/db-password`)
- `version` (optional): The version of the secret to retrieve (e.g., `?version=1`)

**Example:**

```bash
curl -H "Authorization: Token token=\"${TOKEN_B64}\"" https://conjur:3000/secrets/cucumber/variable/app-secrets/db-password
```

### 5.7. Troubleshooting & Tips

- Use consistent names for `<authenticator-id>` and `<workload-name>` across all steps.
- Only one of `crl` or `crl-url` should be set for the authenticator.
- Always URL-encode the certificate before sending it in the header.
- If you receive a 401 Unauthorized error, check that the authenticator is enabled and the workload is properly granted
  access.
- In spiffe mode, make sure the SAN URI in the client certificate is formatted correctly and matches the authenticator's trust domain and identity path configuration.
