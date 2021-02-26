#!/usr/bin/env python3
import argparse
import signal
import sys
import time

import psutil
from fanshim import FanShim

from pid_controller import PidController

parser = argparse.ArgumentParser()
parser.add_argument(
    "--target", type=float, default=50.0, help="Target temperature in degrees C"
)
parser.add_argument(
    "--rate",
    type=float,
    default=1.0,
    help="Delay, in seconds, between temperature readings",
)
parser.add_argument("--kp", type=float, default=10.0, help="Proportional gain")
parser.add_argument("--ki", type=float, default=1.0, help="Integral gain")
parser.add_argument("--kd", type=float, default=0.5, help="Derivative gain")

args = parser.parse_args()

fanshim = FanShim()
fanshim.set_hold_time(1.0)
fanshim.set_fan(False)


def clean_exit(signum, frame):
    fanshim.set_fan(False)
    fanshim.set_light(0, 0, 0)
    sys.exit(0)


def get_cpu_temp():
    t = psutil.sensors_temperatures()
    for x in ["cpu-thermal", "cpu_thermal"]:
        if x in t:
            return t[x][0].current
    print("Warning: Unable to get CPU temperature!")
    return 0


def get_cpu_freq():
    freq = psutil.cpu_freq()
    return freq


signal.signal(signal.SIGTERM, clean_exit)

try:
    controller = PidController(
        args.kp, args.ki, args.kd, args.target, get_cpu_temp(), time.time()
    )

    iteration = 0
    while True:
        state = get_cpu_temp()
        t = time.time()

        desired_ratio = controller.next(t, state)
        duty_ratio = min(100.0, max(0.0, desired_ratio))

        # TODO Export these metrics to be scraped by Prometheus
        if iteration % 10 == 0:
            print(
                "Current: {:05.02f} "
                "Target: {:05.02f} "
                "Duty ratio: {} (want {})"
                .format(state, args.target, duty_ratio, desired_ratio)
            )
        fanshim.set_fan_pwm(duty_ratio)

        iteration += 1
        time.sleep(args.rate)

except KeyboardInterrupt:
    pass
