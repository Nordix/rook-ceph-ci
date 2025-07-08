#!/usr/bin/env python3

import os
import json
import sys

def get_inventory():

    image_os = os.environ.get('IMAGE_OS', 'ubuntu')

    ip_mappings = {
        'ubuntu': {
            'control-plane': '192.168.111.100',
            'worker': '192.168.111.101'
        },
        'centos': {
            'control-plane': '172.22.0.100',
            'worker': '172.22.0.101'
        }
    }

    selected_ips = ip_mappings.get(image_os, ip_mappings['ubuntu'])

    inventory = {
        "_meta": {
            "hostvars": {}
        },
        "kube_control_plane": {
            "hosts": ["control-plane"]
        },
        "kube_worker_nodes": {
            "hosts": ["worker"]
        },
        "kube_all_nodes": {
            "hosts": ["control-plane", "worker"]
        }
    }

    inventory["_meta"]["hostvars"]["control-plane"] = {
        "ansible_host": selected_ips['control-plane'],
        "ansible_user": "metal3",
    }
    inventory["_meta"]["hostvars"]["worker"] = {
        "ansible_host": selected_ips['worker'],
        "ansible_user": "metal3",
    }

    # Output the inventory as JSON
    print(json.dumps(inventory, indent=4))

get_inventory()
