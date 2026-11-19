#!/usr/bin/env bash
set -eo pipefail
export PATH="/usr/local/bin:$PATH"

cd /opt/stack/devstack
source ./openrc admin admin

name=iaas-cirros
image=cirros-0.6.3-x86_64-disk

openstack compute service list --service nova-compute
openstack image show "$image" -f value -c id >/dev/null
# DevStack crea la red privada en el proyecto demo.
source ./openrc demo demo
network_id=$(openstack network show private -f value -c id)
server_id=$(openstack server list --name "^${name}$" -f value -c ID)
if [[ -z "$server_id" ]]; then
    server_id=$(openstack server create "$name" --flavor m1.tiny \
        --image "$image" --network "$network_id" -f value -c id)
    echo VM_CREADA
elif [[ "$server_id" == *$'\n'* ]]; then
    echo "Hay varias instancias llamadas $name." >&2
    exit 1
fi

for ((attempt = 0; attempt < 60; attempt++)); do
    status=$(openstack server show "$server_id" -f value -c status)
    case "$status" in
        ACTIVE)
            if console=$(openstack console log show "$server_id" --lines 100) &&
                [[ "$console" == *"login:"* || "$console" == *"login as "* ]]; then
                openstack server show "$server_id" -c id -c name -c status -c addresses
                echo "CirrOS presentó el inicio de sesión en la consola."
                exit 0
            fi
            ;;
        ERROR)
            openstack server show "$server_id" -c id -c status -c fault >&2
            exit 1
            ;;
    esac
    sleep 5
done

echo "La VM no presentó el inicio de sesión en cinco minutos. Último estado: $status" >&2
exit 1
