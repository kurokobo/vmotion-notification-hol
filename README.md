# [WIP] Demo: vSphere vMotion Notification

Example implementation for vSphere vMotion Notification.

## Requirements

Refer documentation ([this](https://core.vmware.com/resource/vsphere-vmotion-notifications) and [this](https://docs.vmware.com/en/VMware-vSphere/8.0/vsphere-vcenter-esxi-management/GUID-0540DF43-9963-4AF9-A4DB-254414DC00DA.html#how-to-configure-a-virtual-machine-for-vsphere-vmotion-notifications-3)) for details.

- vSphere **8.0** or later
- Virtual Hardware Version **20** or later
- VMware Tools (or Open VM Tools ) **11.0** or later

## Enable vSphere vMotion Notification

This repository includes helper script to modify configuration for specific virtual machine.

```bash
# Prepare Python environment
pip install -r helper/requirements.txt

# Prepare environment variables
export VMWARE_HOST="vcsa.example.com"
export VMWARE_USER="vmotion@vsphere.local"
export VMWARE_VALIDATE_CERTS="false"  # If required
read -sp "Password: " VMWARE_PASSWORD; export VMWARE_PASSWORD

# Show current configuration (can NOT gather vmOpNotificationTimeout)
python helper/vmotion_notification.py vm <VM_NAME>

# Enable vMotion Notification (vmOpNotificationToAppEnabled = true)
python helper/vmotion_notification.py vm <VM_NAME> --enable

# Disable vMotion Notification (vmOpNotificationToAppEnabled = false)
python helper/vmotion_notification.py vm <VM_NAME> --disable

# Modify timeout for vMotion Notification (vmOpNotificationTimeout = <VALUE>)
python helper/vmotion_notification.py vm <VM_NAME> --timeout <VALUE>
```

## References

- [vSphere vMotion Notifications](https://core.vmware.com/resource/vsphere-vmotion-notifications)
- [Virtual Machine Conditions and Limitations for vSphere vMotion](https://docs.vmware.com/en/VMware-vSphere/8.0/vsphere-vcenter-esxi-management/GUID-0540DF43-9963-4AF9-A4DB-254414DC00DA.html#how-to-configure-a-virtual-machine-for-vsphere-vmotion-notifications-3)
- [vSphere Web Services API - VMware API Explorer - VMware {code}](https://developer.vmware.com/apis/1355/vsphere)
  - [Data Object - VirtualMachineConfigInfo(vim.vm.ConfigInfo)](https://vdc-repo.vmware.com/vmwb-repository/dcr-public/c476b64b-c93c-4b21-9d76-be14da0148f9/04ca12ad-59b9-4e1c-8232-fd3d4276e52c/SDK/vsphere-ws/docs/ReferenceGuide/vim.vm.ConfigInfo.html)
  - [Data Object - VirtualMachineConfigSpec(vim.vm.ConfigSpec)](https://vdc-repo.vmware.com/vmwb-repository/dcr-public/c476b64b-c93c-4b21-9d76-be14da0148f9/04ca12ad-59b9-4e1c-8232-fd3d4276e52c/SDK/vsphere-ws/docs/ReferenceGuide/vim.vm.ConfigSpec.html)
