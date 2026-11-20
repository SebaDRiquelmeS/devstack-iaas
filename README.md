# OpenStack DevStack en Rocky Linux 9

Laboratorio IaaS de un solo nodo, adaptado del video DevStack sobre Debian 12 a **Rocky Linux 9.9**. Terraform crea la VM Rocky en KVM/libvirt, cloud-init configura SSH y DHCP, y Ansible instala OpenStack y verifica una instancia CirrOS.

## Contenido

| Ruta | Función |
|---|---|
| `terraform/rocky/devstack/` | Crea pool, imagen Rocky, disco, cloud-init, redes y VM. Espera el lease DHCP y genera el inventario de Ansible. |
| `ansible/rocky/` | Instala DevStack 2026.1 con validaciones y contraseña protegida con Vault. |
| `ansible/demo.yml` | Ejecuta la prueba funcional dentro de OpenStack. |
| `workspace/deploy-cirros.sh` | Crea o reutiliza `iaas-cirros` y espera el login en consola. |
| `Makefile` | Unifica despliegue, verificación y validaciones. |
| `docs/guion-presentacion.md` | Guion sugerido para exponer en grupo. |

La estructura sigue el [repositorio de referencia](https://gitlab.com/alejandro.mellado/devstack/-/tree/ea1f18bc8d501e56aaaad293aab8dd187a7398a5).

## Análisis inicial

| | DevStack sobre Debian 12 | miniONE sobre Ubuntu 22.04 |
|---|---|---|
| Instalación | `stack.sh` lee `local.conf` y prepara OpenStack desde repositorios de código y paquetes del sistema. | `minione` instala paquetes de OpenNebula y configura el front-end y un nodo KVM. |
| Servicios y panel | Nova (cómputo), Neutron (red), Glance (imágenes), Keystone (identidad) y Horizon (panel). Usa MariaDB y RabbitMQ. | El front-end centraliza la gestión, Sunstone ofrece la interfaz y el nodo KVM ejecuta las VM. |
| Dependencias | Git, Python, repositorios, base de datos, cola de mensajes y KVM. | Repositorio OpenNebula, OpenSSH, KVM y acceso administrativo. |
| Adaptación elegida | Debian 12 a Rocky Linux 9.9; no forma parte de la entrega otra distribución de DevStack. | Se mantiene solo como comparación técnica del video de referencia. |

Fuentes: [DevStack 2026.1](https://docs.openstack.org/devstack/2026.1/overview.html) y [miniONE](https://github.com/OpenNebula/minione).

## Adaptaciones y problemas resueltos

- **Paquetes y Python:** `ansible/rocky/preconfig.yml` usa DNF para instalar Git, sudo, ACL, certificados, wget, hostname, complementos de DNF y Python 3.11, la versión seleccionada por la CI de DevStack para Rocky 9.
- **Dependencias RDO:** se fija DevStack en `stable/2026.1`. La URL RDO `centos9-2026.1` devuelve 404, por lo que el playbook utiliza el canal EL9 de RDO Epoxy para RabbitMQ y Open vSwitch. Los servicios OpenStack se instalan desde las ramas indicadas por DevStack.
- **SELinux y firewall del invitado:** el propio DevStack deja SELinux en `permissive` para Apache/Horizon y desactiva firewalld. Se usa un invitado dedicado.
- **Base de datos y cliente:** Rocky usa MariaDB; el cliente OpenStack queda en `/usr/local/bin`, ruta que la demo agrega explícitamente.
- **ISO de cloud-init:** con `dmacvicar/libvirt` 0.9.9 no se fija `target.format` del volumen cloud-init: libvirt detecta `iso` y el provider abortaba si se declaraba `raw`.
- **DHCP y UFW:** `eth0` se configura por DHCP mediante MAC y Terraform espera el lease. En hosts con UFW se permiten tanto la entrada local como el reenvío: la primera habilita DHCP/DNS y la segunda la salida NAT.
- **Reproducibilidad:** el inventario acepta la nueva clave de host, el `instance-id` de cloud-init cambia solo cuando cambia su contenido y la demo es idempotente. La contraseña usa Ansible Vault y Tempest se omite porque la verificación se realiza con `ansible/demo.yml`.

## Requisitos

Anfitrión Linux x86_64 con QEMU/KVM (`qemu-img`), libvirt, OVMF, Terraform 1.5 o posterior, Ansible Core 2.21 y OpenSSH. Se requiere virtualización anidada, acceso del usuario a `qemu:///system`, 6 vCPU y 8 GiB de RAM disponibles para la VM y unos 20 GiB libres en el pool.

Si el anfitrión utiliza UFW, habilita DHCP/DNS local y salida NAT para la red `default` de libvirt:

```bash
sudo ufw allow in on virbr0
sudo ufw route allow in on virbr0
sudo ufw reload
```

Si la red de gestión usa otro bridge, sustituye `virbr0` por su nombre.

## Despliegue desde cero

```bash
git clone https://github.com/SebaDRiquelmeS/devstack-iaas.git
cd devstack-iaas
cp terraform/rocky/devstack/terraform.tfvars.example terraform/rocky/devstack/terraform.tfvars
```

Edita `terraform.tfvars` si cambia tu clave pública o la red `default`. Después crea el secreto de DevStack (16 a 64 caracteres alfanuméricos):

```bash
ansible-vault create ansible/rocky/secrets.yml
# Agrega: devstack_admin_password: TU_PASSWORD_ALFANUMERICO
```

Despliega y verifica:

```bash
make init
make apply
make inventory
make preconfig
make demo
make verify
```

`make deploy` encadena el despliegue completo. Por defecto, Ansible solicita la contraseña de Vault y usa `~/.ssh/id_ed25519`. Para usar otra clave o un archivo local de Vault:

```bash
make preconfig KEY=~/.ssh/devstack_ed25519 \
  VAULT_ARGS="--vault-password-file ansible/rocky/.vault_pass"
make demo KEY=~/.ssh/devstack_ed25519
```

Los archivos `terraform.tfvars`, `inventory.yml`, `secrets.yml`, `.vault_pass` y `admin-password` están ignorados por git y no forman parte del paquete de entrega.

### Variables principales de Terraform

| Variable | Valor del ejemplo | Uso |
|---|---|---|
| `hostname` | `rockystack` | Nombre de la VM y del nodo. |
| `management_network` | `default` | Red libvirt existente con DHCP y salida a Internet. |
| `memory_mb`, `cpu`, `disk_size_gib` | `8192`, `6`, `45` | Recursos del nodo DevStack. |
| `enable_netstack` | `true` | Crea la segunda interfaz `devstack-ext`. |
| `netstack_cidr` | `172.24.4.0/24` | Rango aislado para las IP flotantes. |
| `rocky_image` | URL GenericCloud oficial | Imagen base Rocky 9. |
| `ssh_public_key_path` | `~/.ssh/id_ed25519.pub` | Clave pública autorizada para `rocky`. |

## Verificación y acceso

La demo consulta Nova, comprueba la imagen CirrOS, crea o reutiliza la instancia y espera el login de consola. Horizon está disponible en la URL generada por Terraform:

```bash
terraform -chdir=terraform/rocky/devstack output -raw horizon_url
```

Resultados del despliegue verificado con DHCP:

| Recurso | Valor |
|---|---|
| IP de gestión asignada por DHCP | `192.168.122.134` |
| SSH de este equipo | `ssh -i ~/.ssh/devstack_ed25519 rocky@192.168.122.134` |
| Horizon | [http://192.168.122.134/dashboard/](http://192.168.122.134/dashboard/) |
| Usuario Horizon | `demo` |
| Contraseña | `devstack_admin_password` en el vault; copia local opcional en `ansible/rocky/admin-password` |

- Terraform: `7 added`; un plan posterior no muestra cambios.
- Ansible: instalación `ok=19`, `changed=9`, `failed=0`.
- `iaas-cirros`: `ACTIVE`, IPv4 privada `10.0.0.21` y login en consola.
- Segunda demo: mismo ID de instancia y `changed=0`.
- Horizon: `302` hacia el formulario de login y token válido para `demo`.

## Material de entrega

- [Resumen técnico de una página](resumen-tecnico.pdf)
- [Evidencia de instalación y demostración](evidencia-despliegue.txt)
- [Guion de presentación grupal](docs/guion-presentacion.md)
- Validaciones: `make check`
