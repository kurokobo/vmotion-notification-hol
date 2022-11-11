# (Experimental) Alternative helper script for Python

To modify configuration for vSphere vMotion Notifications, using [PowerShell script module](../) is recommended but this Python script can also be used on both Windows and Linux.

## Initial setup for helper script

```bash
# Install required module
pip install pyvmomi

# Download script
curl -LO https://raw.githubusercontent.com/kurokobo/vmotion-notifications-poc/main/helper/VmOpNotification.py

# Prepare environment variables
export VMWARE_HOST="vcsa.example.com"
export VMWARE_USER="vmotion@vsphere.local"
read -sp "Password: " VMWARE_PASSWORD; export VMWARE_PASSWORD

# (Optional) Ignore SSL certificate verification if required for your vCenter Server
export VMWARE_VALIDATE_CERTS="false"  # If required
```

### Per host settings

```bash
# Show current configuration for specific host
python VmOpNotification.py host <HOST_NAME>

# Modify timeout for vMotion Notifications for specific host (VmOpNotificationToApp.Timeout = <VALUE>), e.g. 600
python VmOpNotification.py host <HOST_NAME> --timeout <VALUE>
```

### Per VM settings

```bash
# Show current configuration (can NOT gather vmOpNotificationTimeout)
python VmOpNotification.py vm <VM_NAME>

# Enable vMotion Notification (vmOpNotificationToAppEnabled = true)
python VmOpNotification.py vm <VM_NAME> --enable

# Disable vMotion Notification (vmOpNotificationToAppEnabled = false)
python VmOpNotification.py vm <VM_NAME> --disable

# Modify timeout for vMotion Notification (vmOpNotificationTimeout = <VALUE>), e.g. 120
python VmOpNotification.py vm <VM_NAME> --timeout <VALUE>
```
