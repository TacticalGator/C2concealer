#!/usr/bin/env bash
set -e

# Install system dependencies (requires root)
if [ "$(id -u)" = "0" ]; then
  apt-get update
  apt-get -y install python3-pip python3-venv default-jre
else
  echo "[Info]: Installing system dependencies with sudo..."
  sudo apt-get update
  sudo apt-get -y install python3-pip python3-venv default-jre
fi

INSTALL_DIR="$(pwd)"

echo "[Info]: Creating virtual environment in $INSTALL_DIR/venv"

python3 -m venv "$INSTALL_DIR/venv"

echo "[Info]: Activating virtual environment"
source "$INSTALL_DIR/venv/bin/activate"

echo "[Info]: Installing Python package"
pip install --upgrade pip
pip install -e .

echo
echo "[Done]"
echo
echo "===================================================="
echo "Use as root: sudo $INSTALL_DIR/venv/bin/C2concealer --hostname your.domain.com --variant 3"
echo
sudo $INSTALL_DIR/venv/bin/C2concealer -h
echo "===================================================="
