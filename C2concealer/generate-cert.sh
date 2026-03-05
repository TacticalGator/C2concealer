#!/bin/bash

# Global Variables
runuser=$(whoami)
tempdir=$(pwd)

# Script Args
domain=$1
password=$2
domainStore=$3

# Local Vars
domainPkcs="${domain}.p12"

# Certbot paths — everything under /opt, nothing in /etc or /usr
CERTBOT_BASE="/opt/certbot"
CERTBOT_BIN="${CERTBOT_BASE}/bin/certbot"
CERTBOT_CONFIG="${CERTBOT_BASE}/config"
CERTBOT_WORK="${CERTBOT_BASE}/work"
CERTBOT_LOGS="${CERTBOT_BASE}/logs"

# Echo Title
clear
echo '=========================================================================='
echo " Running LetsEncrypt to build a SSL cert for ${domain}"
echo '=========================================================================='

# Environment Checks
func_check_env(){
  if [[ $(id -u) -ne 0 ]]; then
    echo
    echo ' [ERROR]: This Setup Script Requires root privileges!'
    echo '          Please run this setup script again with sudo or run as login as root.'
    echo
    exit 1
  fi
}

func_check_tools(){
  if command -v keytool &>/dev/null; then
    echo '[Sweet] java keytool is installed'
  else
    echo
    echo ' [ERROR]: keytool does not seem to be installed'
    echo
    exit 1
  fi
  if command -v openssl &>/dev/null; then
    echo '[Sweet] openssl is installed'
  else
    echo
    echo ' [ERROR]: openssl does not seem to be installed'
    echo
    exit 1
  fi
  if command -v git &>/dev/null; then
    echo '[Sweet] git is installed'
  else
    echo
    echo ' [ERROR]: git does not seem to be installed'
    echo
    exit 1
  fi
}

func_apache_check(){
  if command -v java &>/dev/null; then
    echo '[Sweet] java is already installed'
    echo
  else
    apt-get update
    apt-get install default-jre -y
    echo '[Success] java is now installed'
    echo
  fi
  if command -v apache2 &>/dev/null; then
    echo '[Sweet] Apache2 is already installed'
    systemctl start apache2
    echo
  else
    apt-get update
    apt-get install apache2 -y
    echo '[Success] Apache2 is now installed'
    echo
    systemctl restart apache2
  fi
  if [[ $(ss -tlnp | grep -c ":80 ") -ge 1 ]]; then
    echo '[Success] Apache2 is up and running!'
  else
    echo
    echo ' [ERROR]: Apache2 does not seem to be running on'
    echo '          port 80? Try manual start?'
    echo
    exit 1
  fi
  if command -v ufw &>/dev/null; then
    echo 'Looks like UFW is installed, opening ports 80 and 443'
    ufw allow 80/tcp
    ufw allow 443/tcp
    echo
  fi
}

func_install_letsencrypt(){
  # If certbot is already installed and functional, skip entirely.
  if [[ -x "${CERTBOT_BIN}" ]]; then
    echo "[Info] certbot already installed at ${CERTBOT_BIN}, skipping installation."
  else
    echo '[Starting] Installing certbot dependencies...'

    # Only install what isn't already present.
    local deps=()
    command -v python3 &>/dev/null   || deps+=(python3)
    dpkg -s python3-dev &>/dev/null  || deps+=(python3-dev)
    dpkg -s python3-venv &>/dev/null || deps+=(python3-venv)
    dpkg -s libaugeas-dev &>/dev/null || deps+=(libaugeas-dev)
    command -v gcc &>/dev/null       || deps+=(gcc)

    if [[ ${#deps[@]} -gt 0 ]]; then
      apt-get update
      apt-get install -y "${deps[@]}" \
        || { echo "[ERROR] Failed to install dependencies: ${deps[*]}"; exit 1; }
    else
      echo '[Info] All system dependencies already present.'
    fi

    echo '[Starting] Setting up certbot virtual environment...'
    python3 -m venv "${CERTBOT_BASE}" \
      || { echo "[ERROR] Failed to create venv at ${CERTBOT_BASE}"; exit 1; }

    "${CERTBOT_BASE}/bin/pip" install --upgrade pip \
      || { echo "[ERROR] Failed to upgrade pip"; exit 1; }

    echo '[Starting] Installing certbot and apache plugin...'
    "${CERTBOT_BASE}/bin/pip" install certbot certbot-apache \
      || { echo "[ERROR] Failed to install certbot"; exit 1; }

    echo '[Success] certbot is installed!'
  fi

  # Create our working directories so certbot stays out of /etc entirely.
  mkdir -p "${CERTBOT_CONFIG}" "${CERTBOT_WORK}" "${CERTBOT_LOGS}"

  echo "[Starting] Requesting Let's Encrypt cert for ${domain}..."
  "${CERTBOT_BIN}" --apache \
    -d "${domain}" \
    -n \
    --register-unsafely-without-email \
    --agree-tos \
    --config-dir "${CERTBOT_CONFIG}" \
    --work-dir "${CERTBOT_WORK}" \
    --logs-dir "${CERTBOT_LOGS}" \
    || echo "[WARNING] certbot exited with a non-zero status."

  local cert_path="${CERTBOT_CONFIG}/live/${domain}/fullchain.pem"

  if [[ -e "${cert_path}" ]]; then
    echo '[Success] letsencrypt certs are built!'
    systemctl stop apache2
    echo '[Info] Apache service stopped'
  else
    echo "[ERROR] letsencrypt certs failed to build. Check that DNS A record is properly configured for this domain"
    systemctl stop apache2
    echo '[Info] Apache service stopped'
    exit 1
  fi
}

func_build_pkcs(){
  local live_dir="${CERTBOT_CONFIG}/live/${domain}"

  cd "${live_dir}" || { echo "[ERROR] ${live_dir} not found."; exit 1; }

  echo '[Starting] Building PKCS12 .p12 cert.'
  openssl pkcs12 -export \
    -in fullchain.pem \
    -inkey privkey.pem \
    -out "${domainPkcs}" \
    -name "${domain}" \
    -passout "pass:${password}"
  echo "[Success] Built ${domainPkcs} PKCS12 cert."

  echo '[Starting] Building Java keystore via keytool.'
  keytool -importkeystore \
    -deststorepass "${password}" \
    -destkeypass "${password}" \
    -destkeystore "${domainStore}" \
    -srckeystore "${domainPkcs}" \
    -srcstoretype PKCS12 \
    -srcstorepass "${password}" \
    -alias "${domain}"
  echo "[Success] Java keystore ${domainStore} built."

  cp "${domainStore}" "${tempdir}"
  echo '[Success] Moved Java keystore to current working directory.'
}

# Main
main() {
  func_check_env
  func_check_tools
  func_apache_check
  func_install_letsencrypt
  func_build_pkcs
}

main
