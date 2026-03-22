import requests
from requests.packages.urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)
from datetime import datetime
from ovirtsdk4 import Connection, types, NotFoundError
from ovirtsdk4.types import Disk, DiskFormat, StorageDomain, ImageTransfer, Template, Vm, DiskAttachment, Cluster, OperatingSystem, Cpu, CpuTopology, BootDevice, Boot, Bios, BiosType, Display, DisplayType, VmPlacementPolicy, Usb, Nic, VnicProfile, HighAvailability, NicInterface, VmAffinity, DiskInterface
sleep = __import__('time').sleep

# Connect to oVirt
connection = Connection(
    url='{{ env_ovirt_ovirt_url }}',
    username='{{ env_ovirt_ovirt_username }}',
    password='{{ env_ovirt_ovirt_password }}',
    insecure=True
)

try:
    # Get storage domain
    storage_domains_service = connection.system_service().storage_domains_service()
    storage_domain = storage_domains_service.list(search='name={{ env_ovirt_ovirt_storage_domain }}')[0]
    storage_domain_service = storage_domains_service.storage_domain_service(storage_domain.id)


    

    build_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    version_string = f"build ({build_time})"
    tempvm_name = f"{{ id }}_tmpvm"
    template_name=f"{{ id }}_template"

    # Check if the template exists
    templates_service = connection.system_service().templates_service()
    existing_template = templates_service.list(search=f"name={template_name}")
    print(f"Checking for existing template '{template_name}'")

    if  existing_template:
        print(f"Deleting existing template '{template_name}'...")

        ts = templates_service.template_service(existing_template[0].id)
        ts.remove()

        print(f"Waiting for template '{template_name}' to be fully deleted...")
        try:
            for _ in range(30):  # Loop for a while until we get a 404 or timeout
                _ = ts.get()
                sleep(20)
            else:
                raise SystemExit("Timed out waiting for template deletion to complete.")
        except NotFoundError:  
            pass  # Template no longer exists

        print(f"Template '{template_name}' deleted successfully.")

    # Check if the temporary VM exists
    print(f"Checking for existing VM '{tempvm_name}'...")
    vms_service = connection.system_service().vms_service()
    existing_vm = vms_service.list(search=f"name={tempvm_name}")


    if  existing_vm:
        print(f"Deleting existing VM '{tempvm_name}'...")
        vm = existing_vm[0]
        vm_id = vm.id

        # Delete the template
        vm_service = vms_service.vm_service(vm_id)
        vm_service.remove()

        print(f"Waiting for VM '{tempvm_name}' to be fully deleted...")
        try:
            for _ in range(30):  # Loop for a while until we get a 404 or timeout
                _ = vm_service.get()
                sleep(20)
            else:
                raise SystemExit("Timed out waiting for template deletion to complete.")
        except NotFoundError:  
            pass  # VM no longer exists

        print(f"VM '{tempvm_name}' deleted successfully.")
    # Create new disk
    provisioned_bytes = int({{ os.config.disks[0] }}) * 1024**3
    print(f"Creating new disk '{{ id }}_disk' (size: {provisioned_bytes} bytes)...")
    disk_service = connection.system_service().disks_service()
    new_disk = disk_service.add(
        Disk(
            name='{{ id }}_disk',
            format=DiskFormat.COW,
            provisioned_size=provisioned_bytes,
            storage_domains=[StorageDomain(id=storage_domain.id)],
        )
    )

    # Wait for new disk to be ready
    for _ in range(30):
        created_disk = disk_service.disk_service(new_disk.id).get()
        print(f"Waiting for disk '{{ id }}_disk' to be ready...", end='', flush=True)
        print(getattr(created_disk, 'status', None))
        if created_disk and getattr(created_disk, 'status', None) not in ('locked', 'maintenance'):
            break
        sleep(10)
    else:
        raise SystemExit("Timed out waiting for new disk to be ready")
    sleep(20)  # Extra wait to ensure disk is fully ready

    # Start image transfer
    print(f"Transferring disk '{{ id }}_disk")
    image_transfers_service = connection.system_service().image_transfers_service()
    transfer = image_transfers_service.add(ImageTransfer(disk=Disk(id=new_disk.id)))

    # Wait for transfer URL to be available
    print(f"Wait for transfer URL for disk '{{ id }}_disk'...")
    transfer_service = image_transfers_service.image_transfer_service(transfer.id)
    for _ in range(30):
        tr = transfer_service.get()
        upload_url = getattr(tr, 'transfer_url', None)
        if upload_url:
            break
        sleep(10)
    else:
        raise SystemExit("Timed out waiting for image transfer URL")
    print(f"\nTransfer URL obtained: {upload_url}")
    # sleep(20)  # Extra wait to ensure URL is fully ready

    print("Uploading image to:", upload_url)
    with open('{{ build_imagedir }}/{{ build_id }}.x86_64.qcow2', 'rb') as image_file:
        resp = requests.put(upload_url, data=image_file, headers={
            'Content-Type': 'application/octet-stream'
        }, verify=False)
        resp.raise_for_status()

    # Finalize transfer and wait briefly
    print(f"Finalizing upload for disk '{{ build_id }}_disk'...")
    transfer_service.finalize()
    for _ in range(20):
        tr = transfer_service.get()
        print(f"Waiting for transfer to finalize...", flush=True)
        if tr.phase == types.ImageTransferPhase.FINISHED_SUCCESS :
            break
        sleep(10)

    print(f"Upload and finalize completed for '{{ build_id }}_disk'")
    # sleep(20)  # Extra wait to ensure everything is settled


    # Create or update the template

    print(f"Creating new VM '{ tempvm_name }' before turning it into a template...")
    vms_service = connection.system_service().vms_service()
    clusters_service = connection.system_service().clusters_service()
    cluster = clusters_service.list(search='name={{ env_ovirt_ovirt_cluster }}')[0]

    # Create a new VM with explicit configuration
    new_vm = vms_service.add(
        Vm(
            name=tempvm_name,
            cluster=Cluster(id=cluster.id),
            description="Temporary VM for template creation",
            memory=4 * 1024**3,  # 4 GB memory
            cpu=Cpu(
                topology=CpuTopology(
                    cores=2,  # 2 CPU cores
                    sockets=1
                )
            ),
            os=OperatingSystem(
                # type='rhel_8x64',  # Example OS type
                boot=Boot(devices=[BootDevice.HD, BootDevice.CDROM])  # Correctly specify boot devices using Boot
            ),
            bios=Bios(
                type=BiosType.Q35_SEA_BIOS  # Use the BiosType enumeration for the BIOS type
            ),
            high_availability=HighAvailability(
                enabled=False  # Set to True to enable high availability
            ),
            stateless=False,  # Ensure VM is not stateless
            delete_protected=False,  # Allow deletion of the VM
            nics=[
                Nic(
                    name='nic1',
                    vnic_profile=VnicProfile(
                        name='ovirtmgmt'  # Replace with the correct network profile name
                    ),
                    interface=NicInterface.VIRTIO  # Use the NicInterface enumeration
                )
            ],
            display=Display(
                type=DisplayType.VNC,  # Use VNC as the display type
                monitors=1  # Number of monitors
            ),
            placement_policy=VmPlacementPolicy(
                affinity=VmAffinity.MIGRATABLE  # Use the VmAffinity enumeration
            ),
            usb=Usb(
                enabled=True  # Enable USB redirection
            ),
            template=Template(
                name='Blank'  # Use the 'Blank' template for a new VM
            )
        )
    )
    print(f"VM '{tempvm_name}' created successfully.")

    # Attach the new disk to the VM
    vm_service = vms_service.vm_service(new_vm.id)
    disk_attachments_service = vm_service.disk_attachments_service()
    disk_attachments_service.add(
        DiskAttachment(
            disk=Disk(id=new_disk.id),
            bootable=True,
            active=True,
            interface=DiskInterface.VIRTIO  # Specify the disk interface type
        )
    )
    print(f"Disk '{{ build_id }}_disk' attached to VM '{tempvm_name}'.")

    # Turn the VM into a template
    print(f"Creating new template '{template_name}...")
    new_template = templates_service.add(
        Template(
            name=f"{template_name}",
            vm=Vm(id=new_vm.id),
            description=version_string
        )
    )
    print(f"Template '{template_name}' created successfully.")

    # Wait for the template creation to complete
    template_service = templates_service.template_service(new_template.id)
    print(f"Waiting for template '{template_name}' to be fully created...")
    for _ in range(30):  # Wait for up to 30 iterations (e.g., 1800 seconds)
        template = template_service.get()
        print(f"Template status: {getattr(template, 'status', None)}")
        if template.status == types.TemplateStatus.OK :
            break
        sleep(60)
    else:
        raise SystemExit("Timed out waiting for template creation to complete.")

    # Remove the temporary VM
    print(f"Removing temporary VM '{tempvm_name}'...")
    vm_service.remove()
    print(f"Waiting for temporary VM '{tempvm_name} to be fully deleted...")
    try:
        for _ in range(30):  # Wait for up to 30 iterations (e.g., 1800 seconds)
            vm = vm_service.get()
            sleep(60)
        else:
            raise SystemExit("Timed out waiting for temporary VM deletion to complete.")
    except NotFoundError:  
        pass  # Template no longer exists
    print(f"Temporary VM '{tempvm_name}' deleted successfully.")


finally:
    connection.close()