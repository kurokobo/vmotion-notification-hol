<!-- omit in toc -->
# [PoC] vSphere vMotion Notifications

Example implementation for PoC purpose for vSphere vMotion Notifications.

<!-- omit in toc -->
## Table of contents

- [Requirements](#requirements)
- [Enable vSphere vMotion Notifications using helper script](#enable-vsphere-vmotion-notifications-using-helper-script)
  - [Initial setup for helper script module](#initial-setup-for-helper-script-module)
  - [Per host settings](#per-host-settings)
  - [Per VM settings](#per-vm-settings)
- [How to handle notifications in guest OS](#how-to-handle-notifications-in-guest-os)
- [Example implementation for vSphere vMotion Notifications for PoC](#example-implementation-for-vsphere-vmotion-notifications-for-poc)
  - [For Linux](#for-linux)
  - [For Windows](#for-windows)
- [References](#references)

## Requirements

Refer documentation ([this](https://core.vmware.com/resource/vsphere-vmotion-notifications) and [this](https://docs.vmware.com/en/VMware-vSphere/8.0/vsphere-vcenter-esxi-management/GUID-0540DF43-9963-4AF9-A4DB-254414DC00DA.html#how-to-configure-a-virtual-machine-for-vsphere-vmotion-notifications-3)) for details.

- vSphere **8.0** or later
- Virtual Hardware Version **20** or later
- VMware Tools (or Open VM Tools ) **11.0** or later

## Enable vSphere vMotion Notifications using helper script

To enable vSphere vMotion Notifications, **both VM and Host have to be configured**. This will be done by following three steps.

1. **Per Host**: Configure default timeout value for all hosts where VMs may run on by vMotion (`VmOpNotificationToApp.Timeout`).
1. **Per VM**: Enable vSphere vMotion Notifications per VM (`vmOpNotificationToAppEnabled`).
1. **Per VM**: Configure timeout value per VM (`vmOpNotificationTimeout`).

Currently PowerCLI and PyVmomi does not fully support modifying configuration for vSphere vMotion Notifications, so using MOB (Managed Object Browser) or SDK is preferred way. This repository includes helper script module for PowerShell to modify these configurations.

### Initial setup for helper script module

Some handy functions to modify configurations for vSphere vMotion Notifications can be used by importing [script module `VmOpNotification.psm1`](helper/VmOpNotification.psm1) on your PowerShell.

```powershell
# Download script module
$url = "https://raw.githubusercontent.com/kurokobo/vmotion-notifications-poc/main/helper/VmOpNotification.psm1"
$file = "$env:Temp\VmOpNotification.psm1"
(New-Object System.Net.WebClient).DownloadFile($url, $file)

# Import script module
Import-Module $file

# Prepare environment variables
$env:VMWARE_HOST = "vcsa.example.com"
$env:VMWARE_USER = "vmotion@vsphere.local"
$env:VMWARE_PASSWORD = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($(Read-Host "Password" -AsSecureString)))

# (Optional) Ignore SSL certificate verification if required for your vCenter Server
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
```

### Per host settings

Modifying timeout value for **all hosts** where VMs may be running on by vMotion appears to be required, since the default timeout value is displayed as `1800` but **the actual default value is `0`**, and the smaller timeout value of the host and VM will be used to make vMotion delayed.

```powershell
# Show current configuration for specific host
Get-VMHostVmOpNotification -Name <HOST_NAME>

# Modify timeout for vMotion Notifications for specific host (VmOpNotificationToApp.Timeout = <VALUE>), e.g. 600
Set-VMHostVmOpNotification -Name <HOST_NAME> -Timeout <VALUE>
```

> [!TIP]
> Appending `-Verbose` to above commandlets makes XML for requests and responses to be dumped for debugging purposes. Use with caution since your password (the value for `$env:VMWARE_PASSWORD`) will also be dumped as plain text in XML for authenticaton request.

### Per VM settings

vSphere vMotion Notifications has to be enabled per VM. If timeout value is configured for VM, the smaller timeout value of the host and VM will be used to make vMotion delayed.

```powershell
# Show current configuration
Get-VMVmOpNotification -Name <VM_NAME>

# Enable vMotion Notification (vmOpNotificationToAppEnabled = true)
Set-VMVmOpNotification -Name <VM_NAME> -Enabled "true"

# Disable vMotion Notification (vmOpNotificationToAppEnabled = false)
Set-VMVmOpNotification -Name <VM_NAME> -Enabled "false"

# Modify timeout for vMotion Notification (vmOpNotificationTimeout = <VALUE>), e.g. 120
Set-VMVmOpNotification -Name <VM_NAME> -Timeout <VALUE>
```

> [!TIP]
> Appending `-Verbose` to above commandlets makes XML for requests and responses to be dumped for debugging purposes. Use with caution since your password (the value for `$env:VMWARE_PASSWORD`) will also be dumped as plain text in XML for authenticaton request.

## How to handle notifications in guest OS

Applications can use `vmtoolsd` (command line utility that installed with VMware Tools or Open VM Tools) to handle notifications.

**_NOTE FOR WINDOWS_:** `vmtoolsd` is available as `C:\Program Files\VMware\VMware Tools\vmtoolsd.exe` and usable in the similar manner. However, due to the vagaries of escaping syntax on `powershell.exe` and `cmd.exe`, using `--cmdfile` instead of `--cmd` is recommended; just store argument for `--cmd` as a text file and pass its path through `--cmdfile`.

Initially applications have to get `uniqueToken` by registering applications.

```bash
# Register your applications for notifications
# Note that uniqueToken generated by this command is important to handle notifications and is only displayed at this time
$ vmtoolsd --cmd 'vm-operation-notification.register {"appName": "demo", "notificationTypes": ["sla-miss"]}'
{"version":"1.0.0", "result": true, "guaranteed": true, "uniqueToken": "525b5364-6caf-24a0-562c-87955647baa4", "notificationTimeoutInSec": 120 }

# List registered application
$ vmtoolsd --cmd 'vm-operation-notification.list'
{"version":"1.0.0", "result": true, "info": [     {"appName": "demo", "notificationTypes": ["sla-miss"]}] }

# Unregister your applications for notifications
$ vmtoolsd --cmd 'vm-operation-notification.unregister {"uniqueToken": "525b5364-6caf-24a0-562c-87955647baa4"}'
{"version":"1.0.0", "result": true }
```

Then applications can check if your application is notified by following command. This command should be invoked periodically.

```bash
# Check if your application is notified
$ vmtoolsd --cmd 'vm-operation-notification.check-for-event {"uniqueToken": "525b5364-6caf-24a0-562c-87955647baa4"}'
```

Applications can get following events by above command. Note that only one event appears to be able to be retrieved in a single command execution, even if multiple events are queued.

The `start` event is the notification that applications should start preparing for vMotion, and `end` event is the notification that applications can be in production again.

```bash
# If your application IS NOT notified
{"version":"1.0.0", "result": true }

# If your application IS notified; vMotion started
# Note that operationId included in the output will be used to acknowledge this notification in later step
{"version":"1.0.0", "result": true, "eventType": "start",  "opType": "host-migration", "eventGenTimeInSec": 1666730185, "notificationTimeoutInSec": 120, "destNotificationTimeoutInSec": 120, "notificationTypes": ["sla-miss"],  "operationId": 6279072692702276663 }

# If your application IS notified; vMotion finished
{"version":"1.0.0",  "result": true, "eventType": "end",  "opType": "host-migration", "opStatus": "success", "eventGenTimeInSec": 1666730200, "notificationTypes": ["sla-miss"],  "operationId": 6279072692702276663 }

# Notification that just to inform the value for timeout has been updated
{"version":"1.0.0",  "result": true, "eventType": "timeout-change",  "eventGenTimeInSec": 1666736715, "notificationTimeoutInSec": 120, "newNotificationTimeoutInSec": 60, "notificationTypes": ["sla-miss"],  "operationId": 1666736715415723 }
```

Applications should notify by `ack-event` when they are ready for vMotion. This will actually start the migration.

```bash
# Acknowledge the notification
$ vmtoolsd --cmd 'vm-operation-notification.ack-event {"operationId": 6279072692702276663, "uniqueToken": "525b5364-6caf-24a0-562c-87955647baa4"}'
{"version":"1.0.0", "result": true, "operationId": 6279072692702276663,  "ackStatus": "ack_received" }
```

After the start event, if the timeout elapses, the migration is forced to start even if `ack-event` is not invoked. Therefore note that there is no way to completely abort the migration from applications side.

## Example implementation for vSphere vMotion Notifications for PoC

This repository includes example scripts under [`examples`](examples) for PoC purpose to work with vSphere vMotion Notifications. The script will do;

- Register your application with specified name
- Monitor notifications at specified interval seconds
- On `start` event, invoke specified command to quiesce application
- On `end` event, invoke specified command to unquiesce application
- Unregister your application on exit
- Save detailed debug log as `handle_notifications.log` in the same directory as the script is

### For Linux

To run this script, use following syntax.

```bash
$ python3 handle_notifications.py \
  --name <APPLICATION_NAME> \
  --interval <INTERVAL_SECONDS> \
  --quiesce <QUIESCE_COMMAND> \
  --unquiesce <UNQUIESCE_COMMAND>

# Example: Use bash-based command to quiesce/unquiesce application.
## If your application does not require complex handling to quiesce/unquiesce,
## the commands to do that can be specified directly.
$ python3 handle_notifications.py --name demo --interval 10 \
  --quiesce "bash -c 'echo quiescing; sleep 10; echo quiesced'" \
  --unquiesce "bash -c 'echo unquiescing; sleep 10; echo unquiesced'"

# Example: Use external script to quiesce/unquiesce application.
## If your application require complex handling to quiesce/unquiesce,
## creating script to do that and calling that is good way.
## This repository includes `demo.sh` that just `echo` and `sleep`.
$ python3 handle_notifications.py --name demo --interval 10 \
  --quiesce "${PWD}/demo.sh -m quiesce" \
  --unquiesce "${PWD}/demo.sh -m unquiesce"
```

An actual example is as follows:

```bash
$ python3 handle_notifications.py --name demo --interval 10 \
>   --quiesce "${PWD}/demo.sh -m quiesce" \
>   --unquiesce "${PWD}/demo.sh -m unquiesce"
2022-10-29 07:04:03,025 [INFO] register application: demo
2022-10-29 07:04:03,035 [INFO] application has been registered with issued token: 52964f1a-6c7e-b373-b588-545b39581e1a
2022-10-29 07:04:03,035 [INFO] start monitoring at 10 second intervals (ctrl + c or kill to interrupt)
2022-10-29 07:04:03,035 [INFO] check if application is notified
...
2022-10-29 07:04:33,091 [INFO] check if application is notified
2022-10-29 07:04:33,111 [INFO] application is notified that vmotion has been requested and should be quiesced in 120 seconds. invoke command to quiesce
2022-10-29 07:04:33,116 [INFO] > Application HOGE is requested to be quiesced.
2022-10-29 07:04:33,116 [INFO] > Quiescing ... leaving target pool for load balancing ...
...
2022-10-29 07:04:39,140 [INFO] > Quiescing ... stopping service BAZ
2022-10-29 07:04:40,144 [INFO] > Application HOGE has been quiesced and ready for vMotion.
2022-10-29 07:04:40,144 [INFO] command to quiesce has been completed with return code: 0
2022-10-29 07:04:40,144 [INFO] acknowledge notification
2022-10-29 07:04:40,156 [INFO] got response: ack_received
2022-10-29 07:04:50,161 [INFO] check if application is notified
2022-10-29 07:04:50,172 [INFO] application is notified that vmotion has been completed and should be unquiesced. invoke command to unquiesce
2022-10-29 07:04:50,175 [INFO] > Application HOGE is requested to be unquiesced.
2022-10-29 07:04:50,175 [INFO] > UnQuiescing ... starting service BAZ
...
2022-10-29 07:04:56,190 [INFO] > UnQuiescing ... joining target pool for load balancing ...
2022-10-29 07:04:57,193 [INFO] > Application HOGE has been unquiesced and is in production.
2022-10-29 07:04:57,194 [INFO] command to unquiesce has been completed with return code: 0
2022-10-29 07:05:07,203 [INFO] check if application is notified
...
^C
2022-10-29 07:10:56,154 [INFO] interrupted
2022-10-29 07:10:56,154 [INFO] unregister application: demo
2022-10-29 07:10:56,164 [INFO] application has been unregistered
```

The log file `handle_notifications.log` contains detailed information. This log can be used to know how the notifications had been handled by `vmtoolsd` command, or what the token is issued.

```bash
$ cat handle_notifications.log
2022-10-29 07:04:03,024 [DEBUG] monitor: application name: demo
2022-10-29 07:04:03,025 [DEBUG] monitor: command to quiesce: ['/.../examples/demo.sh -m quiesce']
2022-10-29 07:04:03,025 [DEBUG] monitor: command to unquiesce: ['/.../examples/demo.sh -m unquiesce']
2022-10-29 07:04:03,025 [DEBUG] monitor: monitoring interval: 10 second(s)
2022-10-29 07:04:03,025 [INFO] monitor: register application: demo
2022-10-29 07:04:03,025 [DEBUG] vmtoolsd: invoke command: ['vmtoolsd', '--cmd', 'vm-operation-notification.register {"appName": "demo", "notificationTypes": ["sla-miss"]}']
2022-10-29 07:04:03,034 [DEBUG] vmtoolsd: rc: 0
2022-10-29 07:04:03,034 [DEBUG] vmtoolsd: stdout: {"version":"1.0.0", "result": true, "guaranteed": true, "uniqueToken": "52964f1a-6c7e-b373-b588-545b39581e1a", "notificationTimeoutInSec": 120 }
2022-10-29 07:04:03,035 [INFO] monitor: application has been registered with issued token: 52964f1a-6c7e-b373-b588-545b39581e1a
2022-10-29 07:04:03,035 [INFO] monitor: start monitoring at 10 second intervals (ctrl + c or kill to interrupt)
2022-10-29 07:04:03,035 [INFO] monitor: check if application is notified
2022-10-29 07:04:03,035 [DEBUG] vmtoolsd: invoke command: ['vmtoolsd', '--cmd', 'vm-operation-notification.check-for-event {"uniqueToken": "52964f1a-6c7e-b373-b588-545b39581e1a"}']
2022-10-29 07:04:03,043 [DEBUG] vmtoolsd: rc: 0
2022-10-29 07:04:03,043 [DEBUG] vmtoolsd: stdout: {"version":"1.0.0", "result": true }
...
2022-10-29 07:04:33,091 [INFO] monitor: check if application is notified
2022-10-29 07:04:33,092 [DEBUG] vmtoolsd: invoke command: ['vmtoolsd', '--cmd', 'vm-operation-notification.check-for-event {"uniqueToken": "52964f1a-6c7e-b373-b588-545b39581e1a"}']
2022-10-29 07:04:33,111 [DEBUG] vmtoolsd: rc: 0
2022-10-29 07:04:33,111 [DEBUG] vmtoolsd: stdout: {"version":"1.0.0", "result": true, "eventType": "start",  "opType": "host-migration", "eventGenTimeInSec": 1666994660, "notificationTimeoutInSec": 120, "destNotificationTimeoutInSec": 120, "notificationTypes": ["sla-miss"],  "operationId": 6279072957175440971 }
2022-10-29 07:04:33,111 [INFO] monitor: application is notified that vmotion has been requested and should be quiesced in 120 seconds. invoke command to quiesce
2022-10-29 07:04:33,111 [DEBUG] invoke_command: command for quiesce/unquiesce: ['/.../examples/demo.sh -m quiesce']
2022-10-29 07:04:33,116 [INFO] invoke_command: > Application HOGE is requested to be quiesced.
2022-10-29 07:04:33,116 [INFO] invoke_command: > Quiescing ... leaving target pool for load balancing ...
...
2022-10-29 07:04:39,140 [INFO] invoke_command: > Quiescing ... stopping service BAZ
2022-10-29 07:04:40,144 [INFO] invoke_command: > Application HOGE has been quiesced and ready for vMotion.
2022-10-29 07:04:40,144 [DEBUG] invoke_command: return code: 0
2022-10-29 07:04:40,144 [INFO] monitor: command to quiesce has been completed with return code: 0
2022-10-29 07:04:40,144 [INFO] monitor: acknowledge notification
2022-10-29 07:04:40,144 [DEBUG] vmtoolsd: invoke command: ['vmtoolsd', '--cmd', 'vm-operation-notification.ack-event {"uniqueToken": "52964f1a-6c7e-b373-b588-545b39581e1a", "operationId": 6279072957175440971}']
2022-10-29 07:04:40,156 [DEBUG] vmtoolsd: rc: 0
2022-10-29 07:04:40,156 [DEBUG] vmtoolsd: stdout: {"version":"1.0.0", "result": true, "operationId": 6279072957175440971,  "ackStatus": "ack_received" }
2022-10-29 07:04:40,156 [INFO] monitor: got response: ack_received
...
2022-10-29 07:10:56,154 [INFO] monitor: interrupted
2022-10-29 07:10:56,154 [INFO] monitor: unregister application: demo
2022-10-29 07:10:56,155 [DEBUG] vmtoolsd: invoke command: ['vmtoolsd', '--cmd', 'vm-operation-notification.unregister {"uniqueToken": "52964f1a-6c7e-b373-b588-545b39581e1a"}']
2022-10-29 07:10:56,164 [DEBUG] vmtoolsd: rc: 0
2022-10-29 07:10:56,164 [DEBUG] vmtoolsd: stdout: {"version":"1.0.0", "result": true }
2022-10-29 07:10:56,164 [INFO] monitor: application has been unregistered
```

### For Windows

Not implemented.

## References

- [vSphere vMotion Notifications](https://core.vmware.com/resource/vsphere-vmotion-notifications)
- [Virtual Machine Conditions and Limitations for vSphere vMotion](https://docs.vmware.com/en/VMware-vSphere/8.0/vsphere-vcenter-esxi-management/GUID-0540DF43-9963-4AF9-A4DB-254414DC00DA.html#how-to-configure-a-virtual-machine-for-vsphere-vmotion-notifications-3)
- [vSphere Web Services API - VMware API Explorer - VMware {code}](https://developer.vmware.com/apis/1355/vsphere)
  - [Data Object - VirtualMachineConfigInfo(vim.vm.ConfigInfo)](https://vdc-repo.vmware.com/vmwb-repository/dcr-public/c476b64b-c93c-4b21-9d76-be14da0148f9/04ca12ad-59b9-4e1c-8232-fd3d4276e52c/SDK/vsphere-ws/docs/ReferenceGuide/vim.vm.ConfigInfo.html)
  - [Data Object - VirtualMachineConfigSpec(vim.vm.ConfigSpec)](https://vdc-repo.vmware.com/vmwb-repository/dcr-public/c476b64b-c93c-4b21-9d76-be14da0148f9/04ca12ad-59b9-4e1c-8232-fd3d4276e52c/SDK/vsphere-ws/docs/ReferenceGuide/vim.vm.ConfigSpec.html)
