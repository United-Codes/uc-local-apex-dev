#!/usr/bin/env bash

set -e

# Function to check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to check if script is run with sudo/root privileges
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo or as root"
    exit 1
  fi
}

check_root

echo "Generating certificates..."

openssl req -x509 -out cert.crt -keyout key.key -days 9999 \
  -newkey rsa:2048 -nodes -sha256 \
  -subj '/CN=localhost' -extensions EXT -config <(
    printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth"
  )

if [ $? -ne 0 ]; then
  echo "Certificate generation failed"
  exit 1
fi

mkdir -p ./ssl/ || true

mv cert.crt ./ssl/cert.crt
mv key.key ./ssl/key.key

echo "Successfully generated certificates"
echo "  - Certificate: ./ssl/cert.crt"
echo "  - Private key: ./ssl/key.key"

chmod 644 ./ssl/key.key
chmod 644 ./ssl/cert.crt

mkdir -p ./ords-config/ssl/ || true
cp -f ./ssl/cert.crt ./ords-config/ssl/
cp -f ./ssl/key.key ./ords-config/ssl/

echo "Successfully copied certificates to ORDS config directory. Restart ORDS to apply changes."

# Detect OS and install certificate
OS=$(uname -s)
case "$OS" in
Linux*)
  echo "Detected Linux OS"
  echo "  - Installing certificate to system trust store"

  # Check for different Linux distributions
  if [ -f /etc/debian_version ]; then
    cp "./ssl/cert.crt" /usr/local/share/ca-certificates/
    update-ca-certificates
  elif [ -f /etc/redhat-release ]; then
    cp "./ssl/cert.crt" /etc/pki/ca-trust/source/anchors/
    update-ca-trust extract
  else
    echo "Unsupported Linux distribution. Please install the certificate manually."
    exit 1
  fi
  ;;
Darwin*)
  KEYCHAIN="/Library/Keychains/System.keychain"

  echo "Installing certificate for macOS..."
  # Add to system keychain
  security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "./ssl/cert.crt"

  # Set all trust settings to always trust
  security set-key-partition-list -D "Mozilla" -S "Mozilla" -k "$KEYCHAIN" "./ssl/cert.crt" 2>/dev/null

  # Verify installation
  if security find-certificate -c "$DOMAIN" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Certificate successfully installed and trusted in macOS Keychain"
    echo "Note: For Firefox, you'll need to manually import the certificate:"
    echo "1. Open Firefox"
    echo "2. Go to Preferences/Settings"
    echo "3. Search for 'certificates'"
    echo "4. Click 'View Certificates'"
    echo "5. Go to 'Authorities' tab"
    echo "6. Click 'Import' and select: ./ssl/cert.crt"
    echo "7. Check 'Trust this CA to identify websites'"
  else
    echo "Warning: Certificate installation verification failed"
  fi
  ;;
*)
  echo "Unsupported operating system: $OS"
  echo "Please install the certificate manually."
  exit 1
  ;;
esac

echo "Successfully installed certificate to system trust store"
echo "Please restart ORDS to apply changes: docker-compose restart ords"
echo "Only access ORDS via HTTPS: https://localhost:8181/ords/_/landing"
