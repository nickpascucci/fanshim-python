#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
POSITIONAL_ARGS=()
PYTHON="python3"
PIP="pip3"
PSUTIL_MIN_VERSION="5.6.7"

ON_THRESHOLD_SET=false
OFF_THRESHOLD_SET=false

SERVICE_PATH=/etc/systemd/system/pimoroni-fanshim.service

USAGE="sudo ./install-service.sh --venv <python_virtual_environment>"

# Convert Python path to absolute for systemd
PYTHON=`type -P $PYTHON`

while [[ $# -gt 0 ]]; do
	K="$1"
	case $K in
	--venv)
		VENV="$(realpath ${2%/})/bin"
		PYTHON="$VENV/python3"
		PIP="$VENV/pip3"
		shift
		shift
		;;
	*)
		if [[ $1 == -* ]]; then
			printf "Unrecognised option: $1\n";
			printf "Usage: $USAGE\n";
			exit 1
		fi
		POSITIONAL_ARGS+=("$1")
		shift
	esac
done

if ! ( type -P "$PYTHON" > /dev/null ) ; then
	if [ "$PYTHON" == "python3" ]; then
		printf "Fan SHIM controller requires Python 3\n"
		printf "You should run: 'sudo apt install python3'\n"
	else
		printf "Cannot find virtual environment.\n"
		printf "Set to base of virtual environment i.e. <venv>/bin/python3.\n"
	fi
	exit 1
fi

if ! ( type -P "$PIP" > /dev/null ) ; then
	printf "Fan SHIM controller requires Python 3 pip\n"
	if [ "$PIP" == "pip3" ]; then
		printf "You should run: 'sudo apt install python3-pip'\n"
	else
		printf "Ensure that your virtual environment has pip3 installed.\n"
	fi
	exit 1
fi

set -- "${POSITIONAL_ARGS[@]}"

EXTRA_ARGS=""

read -r -d '' UNIT_FILE << EOF
[Unit]
Description=Fan Shim Service
After=multi-user.target

[Service]
Type=simple
WorkingDirectory=$(pwd)
ExecStart=$PYTHON $(pwd)/pid.py $EXTRA_ARGS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

printf "Checking for rpi.gpio >= 0.7.0 (for Pi 4 support)\n"
$PYTHON - <<EOF
import RPi.GPIO as GPIO
from pkg_resources import parse_version
import sys
if parse_version(GPIO.VERSION) < parse_version('0.7.0'):
    sys.exit(1)
EOF

if [ $? -ne 0 ]; then
	printf "Installing rpi.gpio\n"
	$PIP install --upgrade "rpi.gpio>=0.7.0"
else
	printf "rpi.gpio >= 0.7.0 already installed\n"
fi

printf "Checking for Fan SHIM\n"
$PYTHON - > /dev/null 2>&1 <<EOF
import fanshim
EOF

if [ $? -ne 0 ]; then
	printf "Installing Fan SHIM\n"
	$PIP install fanshim
else
	printf "Fan SHIM already installed\n"
fi

printf "Checking for psutil >= $PSUTIL_MIN_VERSION\n"
$PYTHON - > /dev/null 2>&1 <<EOF
import sys
import psutil
from pkg_resources import parse_version
sys.exit(not parse_version(psutil.__version__) >= parse_version('$PSUTIL_MIN_VERSION'))
EOF

if [ $? -ne 0 ]; then
	printf "Installing psutil\n"
	$PIP install --ignore-installed psutil
else
	printf "psutil >= $PSUTIL_MIN_VERSION already installed\n"
fi

printf "\nInstalling service to: $SERVICE_PATH\n"
echo "$UNIT_FILE" > $SERVICE_PATH
systemctl daemon-reload
systemctl enable --no-pager pimoroni-fanshim.service
systemctl restart --no-pager pimoroni-fanshim.service
systemctl status --no-pager pimoroni-fanshim.service
