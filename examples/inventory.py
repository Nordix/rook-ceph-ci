#!/usr/bin/env python3

import os
import json
import sys

def get_inventory():

    image_os = os.environ.get('IMAGE_OS', 'ubuntu')

    ip_mappings = {
        'ubuntu': {
            'control-plane1': '192.168.111.100',
            'control-plane2': '192.168.111.102',
            'control-plane3': '192.168.111.103',
            'worker': '192.168.111.101'
        },
        'centos': {
            'control-plane1': '172.22.0.100',
            'control-plane2': '172.22.0.102',
            'control-plane3': '172.22.0.103',
            'worker': '172.22.0.101'
        }
    }

    selected_ips = ip_mappings.get(image_os, ip_mappings['ubuntu'])

    inventory = {
        "_meta": {
            "hostvars": {}
        },
        "kube_control_plane1": {
            "hosts": ["control-plane1"]
        },
        "kube_worker_nodes": {
            "hosts": ["worker"]
        },
        "kube_all_nodes": {
            "hosts": ["control-plane1", "control-plane2", "control-plane3", "worker"]
        }
    }

    inventory["_meta"]["hostvars"]["control-plane1"] = {
        "ansible_host": selected_ips['control-plane1'],
        "ansible_user": "metal3",
    }
    inventory["_meta"]["hostvars"]["control-plane2"] = {
        "ansible_host": selected_ips['control-plane2'],
        "ansible_user": "metal3",
    }
    inventory["_meta"]["hostvars"]["control-plane3"] = {
        "ansible_host": selected_ips['control-plane3'],
        "ansible_user": "metal3",
    }
    inventory["_meta"]["hostvars"]["worker"] = {
        "ansible_host": selected_ips['worker'],
        "ansible_user": "metal3",
    }

    # Output the inventory as JSON
    print(json.dumps(inventory, indent=4))

get_inventory()
