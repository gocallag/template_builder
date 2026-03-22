import ovirtsdk4 as sdk
import ovirtsdk4.types as types
import logging
import sys
import argparse

# --- Config ---
CONFIG = {
    'url': '{{ env_ovirt_ovirt_url }}',
    'username': '{{ env_ovirt_ovirt_username }}',
    'password': '{{ env_ovirt_ovirt_password }}',
    'vm_name': '{{ id }}_template',
    'template_name': '{{ id }}_template',
    'insecure': True
}

# --- Logging ---
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')

def connect_to_ovirt(config):
    return sdk.Connection(
        url=config['url'],
        username=config['username'],
        password=config['password'],
        insecure=config['insecure']
    )

def find_vm(vms_service, vm_name):
    for vm in vms_service.list():
        if vm.name == vm_name:
            return vm
    return None

def create_template(connection, config):
    vms_service = connection.system_service().vms_service()
    templates_service = connection.system_service().templates_service()

    vm = find_vm(vms_service, config['vm_name'])
    if not vm:
        logging.error(f"VM '{config['vm_name']}' not found.")
        sys.exit(1)

    if vm.status != types.VmStatus.DOWN:
        logging.error(f"VM '{config['vm_name']}' must be powered off. Current status: {vm.status}")
        sys.exit(1)

    logging.info(f"Creating template '{config['template_name']}' from VM '{config['vm_name']}'...")
    templates_service.add(
        types.Template(
            name=config['template_name'],
            vm=types.Vm(id=vm.id),
            cluster=types.Cluster(id=vm.cluster.id)
        )
    )
    logging.info("Template creation successful.")

def rollback_template(connection, template_name):
    templates_service = connection.system_service().templates_service()
    template = next((t for t in templates_service.list() if t.name == template_name), None)
    if template:
        logging.warning(f"Rolling back: deleting template '{template_name}'...")
        templates_service.template_service(template.id).remove()
        logging.info("Rollback complete.")
    else:
        logging.warning(f"No template named '{template_name}' found for rollback.")

# --- Main ---
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Create oVirt template from VM')
    parser.add_argument('--url', help='oVirt API URL', dest='url')
    parser.add_argument('--username', help='oVirt username', dest='username')
    parser.add_argument('--password', help='oVirt password', dest='password')
    parser.add_argument('--vm-name', help='Source VM name', dest='vm_name')
    parser.add_argument('--template-name', help='Template name to create', dest='template_name')
    parser.add_argument('--insecure', dest='insecure', action='store_true', help='Allow insecure TLS')
    parser.add_argument('--no-insecure', dest='insecure', action='store_false', help='Disallow insecure TLS')
    parser.set_defaults(insecure=CONFIG.get('insecure', True))

    args = parser.parse_args()

    # Override CONFIG values from CLI args when provided
    if args.url:
        CONFIG['url'] = args.url
    if args.username:
        CONFIG['username'] = args.username
    if args.password:
        CONFIG['password'] = args.password
    if args.vm_name:
        CONFIG['vm_name'] = args.vm_name
    if args.template_name:
        CONFIG['template_name'] = args.template_name
    CONFIG['insecure'] = args.insecure

    conn = connect_to_ovirt(CONFIG)
    try:
        create_template(conn, CONFIG)
    except Exception as e:
        logging.error(f"Exception occurred: {e}")
        rollback_template(conn, CONFIG['template_name'])
    finally:
        conn.close()