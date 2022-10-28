import argparse
import logging
import os
import json
import signal
import subprocess
import sys
import time


def handle_signal(signum, frame):
    sys.exit(1)


def set_logger():
    basedir = os.path.dirname(os.path.abspath(__file__))
    logfile = os.path.join(basedir, "handle_notifications.log")

    sh = logging.StreamHandler()
    sh.setLevel(logging.INFO)
    sh.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s"))

    fh = logging.FileHandler(logfile)
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(funcName)s: %(message)s"))

    logging.basicConfig(level=logging.NOTSET, handlers=[sh, fh])


def vmtoolsd(subcmd, dict):
    logger = logging.getLogger(__name__)
    args = "vm-operation-notification.{} {}".format(subcmd, json.dumps(dict))
    cmd = ["vmtoolsd", "--cmd", args]
    logger.debug("invoke command: {}".format(cmd))

    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    except Exception as e:
        raise Exception("{}".format(e))

    logger.debug("rc: {}".format(result.returncode))
    logger.debug("stdout: {}".format(result.stdout.strip()))

    return json.loads(result.stdout)


def register(name):
    args = {"appName": name, "notificationTypes": ["sla-miss"]}
    result = vmtoolsd("register", args)
    if result["result"]:
        return result["uniqueToken"]
    else:
        raise Exception("Failed to register application: {}".format(result))


def unregister(token):
    args = {"uniqueToken": token}
    result = vmtoolsd("unregister", args)
    if not result["result"]:
        raise Exception("Failed to unregister application: {}".format(result))


def check_for_event(token):
    args = {"uniqueToken": token}
    result = vmtoolsd("check-for-event", args)
    if result["result"]:
        return result
    else:
        raise Exception("Failed to check for event: {}".format(result))


def ack_event(token, oid):
    args = {"uniqueToken": token, "operationId": oid}
    result = vmtoolsd("ack-event", args)
    if result["result"]:
        return result["ackStatus"]
    else:
        raise Exception("Failed to acknowledge event: {}".format(result))


def is_notified(token):
    _event = check_for_event(token)
    if "eventType" in _event and _event["eventType"] == "start":
        return "start", _event["notificationTimeoutInSec"], _event["operationId"]
    elif "eventType" in _event and _event["eventType"] == "end":
        return "end", None, None
    else:
        return None, None, None


def invoke_command(cmd):
    logger = logging.getLogger(__name__)
    logger.debug("command for quiesce/unquiesce: {}".format(cmd))
    try:
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, shell=True)
        while True:
            stdout_line = process.stdout.readline()
            if stdout_line:
                logger.info("> {}".format(stdout_line.strip()))
            if not stdout_line and process.poll() is not None:
                break
        rc = process.poll()
    except Exception as e:
        raise Exception("{}".format(e))

    logger.debug("return code: {}".format(rc))
    return rc


def monitor(args):
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    logger = logging.getLogger(__name__)
    logger.debug("application name: {}".format(args.name))
    logger.debug("command to quiesce: {}".format(args.quiesce))
    logger.debug("command to unquiesce: {}".format(args.unquiesce))
    logger.debug("monitoring interval: {} second(s)".format(args.interval))

    try:
        logger.info("register application: {}".format(args.name))
        token = register(args.name)
        logger.info("application has been registered with issued token: {}".format(token))

        logger.info("start monitoring at {} second intervals (ctrl + c or kill to interrupt)".format(args.interval))

        while True:
            logger.info("check if application is notified")
            event_type, timeout, oid = is_notified(token)

            if event_type is None:
                pass
            elif event_type == "start":
                logger.info("application is notified that vmotion has been requested and should be quiesced in {} seconds. invoke command to quiesce".format(timeout))
                rc = invoke_command(args.quiesce)
                logger.info("command to quiesce has been completed with return code: {}".format(rc))
                logger.info("acknowledge notification")
                response = ack_event(token, oid)
                logger.info("got response: {}".format(response))
            elif event_type == "end":
                logger.info("application is notified that vmotion has been completed and should be unquiesced. invoke command to unquiesce")
                rc = invoke_command(args.unquiesce)
                logger.info("command to unquiesce has been completed with return code: {}".format(rc))

            time.sleep(args.interval)

    except Exception as e:
        raise Exception("Error: {}".format(e))

    finally:
        logger.info("interrupted")
        if "token" in locals():
            logger.info("unregister application: {}".format(args.name))
            unregister(token)
            logger.info("application has been unregistered")


def main():
    set_logger()

    parser = argparse.ArgumentParser(description="Monitor vSphere vMotion Notifications and make application quiesced/unquiesced")
    parser.add_argument("-n", "--name", action="store", required=True, help="name of your application to be registered")
    parser.add_argument("-i", "--interval", action="store", type=int, default=30, help="interval to check for notifications, in seconds. defaults to 30")
    parser.add_argument("-q", "--quiesce", metavar="COMMAND", action="store", required=True, nargs="*", help="Command to quiesce application before vmotion")
    parser.add_argument("-u", "--unquiesce", metavar="COMMAND", action="store", required=True, nargs="*", help="Command to unquiesce application after vmotion")
    parser.set_defaults(handler=monitor)

    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
