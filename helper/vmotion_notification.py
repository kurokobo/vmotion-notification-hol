import argparse
import atexit
import os
import sys
import ssl

from pyVim.connect import Disconnect, SmartConnect
from pyVim.task import WaitForTask
from pyVmomi import vim
from pyVmomi.VmomiSupport import CreateDataType, F_OPTIONAL, vmodlTypes

# Dirty monkey patch for pyVmomi to force to allow modifying vmOpNotificationTimeout.
# This should be removed when pyVmomi supports 8.0.
CreateDataType(
    "vim.vm.ConfigSpec",
    "VirtualMachineConfigSpec",
    "vmodl.DynamicData",
    "vim.version.version1",
    [
        ("vmOpNotificationToAppEnabled", "boolean", "vim.version.v7_0_3_0", F_OPTIONAL),
        ("vmOpNotificationTimeout", "long", "vim.version.v7_0_3_0", F_OPTIONAL),
    ],
)


def get_obj_by_name(conn, root, vim_type, value):
    objs = []
    container = conn.content.viewManager.CreateContainerView(root, vim_type, True)
    for obj in container.view:
        if obj.name == value:
            objs.append(obj)
    container.Destroy()
    return objs


def get_vm_by_name(conn, vm):
    try:
        vms = get_obj_by_name(conn, conn.content.rootFolder, [vim.VirtualMachine], vm)
        if len(vms) != 1:
            raise Exception
        return vms[0]
    except Exception:
        raise Exception("Error: vm {} not found".format(vm))


def get_host_by_name(conn, host):
    try:
        hosts = get_obj_by_name(conn, conn.content.rootFolder, [vim.HostSystem], host)
        if len(hosts) != 1:
            raise Exception
        return hosts[0]
    except Exception:
        raise Exception("Error: host {} not found".format(host))


def get_client():
    vmware_host = os.getenv("VMWARE_HOST")
    vmware_user = os.getenv("VMWARE_USER")
    vmware_password = os.getenv("VMWARE_PASSWORD")
    vmware_validate_certs = os.getenv("VMWARE_VALIDATE_CERTS", "true").lower() == "true"

    if None in [vmware_host, vmware_user, vmware_password]:
        print("Error: environment variables VMWARE_HOST, VMWARE_USER, and VMWARE_PASSWORD are required", file=sys.stderr)
        sys.exit(1)

    if vmware_validate_certs:
        context = None
    else:
        context = ssl._create_unverified_context()

    try:
        si = SmartConnect(host=vmware_host, user=vmware_user, pwd=vmware_password, sslContext=context)
    except Exception as e:
        raise Exception("Error: cannot connect vmware host: {}".format(e))

    atexit.register(Disconnect, si)
    return si


def handle_vm_mode(args):
    conn = get_client()
    vm = get_vm_by_name(conn, args.vm)
    if not args.enable and not args.disable and args.timeout is None:
        print("vmOpNotificationToAppEnabled: {}".format(vm.config.vmOpNotificationToAppEnabled))
        # print("vmOpNotificationTimeout: {}".format(vm.config.vmOpNotificationTimeout))

    else:
        spec = {}
        if args.enable:
            spec["vmOpNotificationToAppEnabled"] = True
        if args.disable:
            spec["vmOpNotificationToAppEnabled"] = False
        if args.timeout:
            spec["vmOpNotificationTimeout"] = args.timeout
        config_spec = vim.vm.ConfigSpec(**spec)
        try:
            WaitForTask(vm.Reconfigure(config_spec))
        except Exception as e:
            raise Exception("Error: failed to modify vm: {}".format(e))


def handle_host_mode(args):
    conn = get_client()
    host = get_host_by_name(conn, args.host)
    manager = host.configManager.advancedOption
    if args.timeout is None:
        try:
            option = manager.QueryOptions(name="VmOpNotificationToApp.Timeout")
            if len(option) == 1:
                print("VmOpNotificationToApp.Timeout: {}".format(option[0].value))
        except Exception as e:
            raise Exception("Error: failed to modify host: {}".format(e))
    else:
        long = vmodlTypes["long"]
        option = vim.option.OptionValue(key="VmOpNotificationToApp.Timeout", value=long(args.timeout))
        try:
            manager.UpdateOptions(changedValue=[option])
        except Exception as e:
            raise Exception("Error: failed to modify host: {}".format(e))


def main():
    parser = argparse.ArgumentParser(description="Display or modify configuration for vSphere vMotion Notification.")
    subparsers = parser.add_subparsers(required=True, title="mode")

    parser_vm = subparsers.add_parser("vm", help="display or modify configuration for specific vm")
    parser_vm.add_argument("vm", metavar="VM", action="store", help="name of vm that configuration will be displayed or modified")
    parser_vm_action = parser_vm.add_mutually_exclusive_group()
    parser_vm_action.add_argument("-e", "--enable", action="store_true", help="enable notification for vm")
    parser_vm_action.add_argument("-d", "--disable", action="store_true", help="disable notification for vm")
    parser_vm.add_argument("-t", "--timeout", action="store", type=int, help="timeout in seconds for notification for vm")
    parser_vm.set_defaults(handler=handle_vm_mode)

    parser_host = subparsers.add_parser("host", help="display or modify configuration for specific host")
    parser_host.add_argument("host", metavar="HOST", action="store", help="name of host that configuration will be displayed or modified")
    parser_host.add_argument("-t", "--timeout", action="store", type=int, help="timeout in seconds for notification for host")
    parser_host.set_defaults(handler=handle_host_mode)

    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
