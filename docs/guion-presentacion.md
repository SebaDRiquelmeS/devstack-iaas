# Guion de presentación del laboratorio

## Objetivo y arquitectura

El laboratorio adapta DevStack de Debian 12 a **Rocky Linux 9.9** y automatiza dos niveles: Terraform crea la VM sobre KVM y Ansible instala/configura OpenStack dentro de ella.

```text
Anfitrión Linux + KVM/libvirt
├── Terraform
│   ├── Red de gestión libvirt "default" con DHCP y NAT
│   ├── Red aislada netstack (172.24.4.0/24)
│   └── VM rockystack (Rocky 9.9, UEFI, 6 vCPU, 8 GiB RAM)
└── Ansible
    ├── DevStack 2026.1: Keystone, Glance, Nova, Neutron y Horizon
    └── Verificación: iaas-cirros (CirrOS en KVM anidado)
```

## Reparto sugerido (ajustar nombres)

- **Integrante 1:** objetivo, comparación DevStack/miniONE y adaptación Debian a Rocky.
- **Integrante 2:** aprovisionamiento con Terraform, cloud-init, DHCP y redes.
- **Integrante 3:** instalación con Ansible, demostración de CirrOS y Horizon.

Si son dos integrantes, el primero cubre también la demostración.

## Secuencia sugerida (6–8 minutos)

### 1. Contexto y decisión técnica

- DevStack instala servicios OpenStack desde código y paquetes del sistema; miniONE instala OpenNebula desde paquetes y configura front-end + nodo KVM.
- Se eligió DevStack por su modelo modular de servicios y se cambió la base de Debian 12 a Rocky 9.
- Dependencias principales: Python, MariaDB, RabbitMQ, Neutron/Open vSwitch y KVM anidado.

### 2. Infraestructura como código con Terraform

Mostrar brevemente `terraform/rocky/devstack/main.tf`:

- Pool, imagen Rocky GenericCloud, disco QCOW2, UEFI y CPU host-passthrough.
- `eth0` por DHCP y `devstack-ext` para Neutron.
- Espera del lease DHCP y generación del inventario Ansible en `outputs.tf`.

Comandos de apoyo:

```bash
terraform -chdir=terraform/rocky/devstack plan
terraform -chdir=terraform/rocky/devstack output -raw horizon_url
```

Un plan sin cambios demuestra que la configuración coincide con la infraestructura real.

### 3. Configuración con Ansible

Mostrar `ansible/rocky/preconfig.yml` y explicar:

- Validación de Rocky 9, arquitectura, IPv4, `/dev/kvm` y contraseña.
- Instalación DNF y usuario `stack`.
- Revisión fija de DevStack y uso de Ansible Vault.
- Ejecución de `stack.sh` y marca de instalación para evitar reinstalar.

La demo se ejecuta con:

```bash
make demo KEY=~/.ssh/devstack_ed25519
```

### 4. Demostración funcional

Mostrar en la salida de Ansible:

1. `nova-compute` en estado `enabled/up`.
2. `VM_CREADA` solo en la primera ejecución.
3. `iaas-cirros` en estado `ACTIVE`, con IP privada y login en consola.
4. En una segunda ejecución, `changed=0`: se reutiliza la instancia.

En Horizon, abrir **Proyecto → Cómputo → Instancias** y mostrar `iaas-cirros`. La URL se obtiene con:

```bash
terraform -chdir=terraform/rocky/devstack output -raw horizon_url
```

El usuario es `demo`; la contraseña se consulta en el vault local y no se proyecta en la entrega.

### 5. Problemas encontrados y soluciones

| Problema | Causa | Solución demostrada |
|---|---|---|
| Dependencias RDO `centos9-2026.1` no disponibles | La URL devuelve 404 | Canal EL9 de RDO Epoxy fijado por Ansible. |
| Error al crear el volumen cloud-init | El provider esperaba `raw`, pero libvirt detectó `iso` | No declarar `target.format`; libvirt determina el formato. |
| La VM no obtenía DHCP | UFW bloqueaba la entrada local y el forwarding del host | `ufw allow in on virbr0` para DHCP/DNS y `ufw route allow in on virbr0` para NAT. |
| Acceso SSH inicial | La clave de host cambia al recrear la VM | Inventario generado con `StrictHostKeyChecking=accept-new`. |

### 6. Cierre

- Se automatizó la VM base y la instalación del IaaS, no solo una instalación manual.
- La comprobación es funcional e idempotente: CirrOS arranca y una segunda ejecución no genera cambios.
- La configuración queda parametrizada por `terraform.tfvars`, variables de Ansible y opciones del `Makefile`.

## Preguntas previsibles

- **¿Por qué Rocky 9?** Es una distribución RHEL-compatible distinta de Debian 12; obliga a adaptar paquetes, Python, repositorios RDO, SELinux y servicios.
- **¿Por qué Terraform y Ansible?** Terraform modela la infraestructura libvirt; Ansible aplica configuración y valida el servicio OpenStack.
- **¿Por qué DHCP?** Es la configuración nativa de la red libvirt. La IP se obtiene del lease y se propaga al inventario; no se hardcodea.
- **¿Por qué RDO Epoxy?** El canal `centos9-2026.1` no estaba publicado; EL9 Epoxy aporta las dependencias RPM necesarias, mientras OpenStack se instala desde las ramas de DevStack 2026.1.
- **¿Cómo se protege la contraseña?** Con Ansible Vault; `secrets.yml`, `.vault_pass` y `admin-password` están excluidos de la entrega.
- **¿Cómo se demuestra idempotencia?** `terraform plan` queda sin cambios y la segunda demo reutiliza la misma instancia con `changed=0`.

## Evidencias a tener visibles

- `terraform plan` sin cambios.
- `PLAY RECAP` de la instalación con `failed=0`.
- `iaas-cirros ACTIVE` y la IP privada.
- Segunda ejecución de la demo con `changed=0`.
- Horizon con la instancia visible.
- `evidencia-despliegue.txt` y `resumen-tecnico.pdf` como respaldo escrito.
