# OpenStack DevStack en Rocky Linux 9

Laboratorio IaaS de un solo nodo. Terraform crea la VM Rocky en KVM/libvirt, cloud-init configura el acceso por SSH y Ansible instala OpenStack y despliega una instancia CirrOS.

| Carpeta | Función |
|---|---|
| `terraform/rocky/devstack/` | Prepara el pool, la imagen Rocky, el disco, cloud-init y la VM. Usa la red de gestión de libvirt y crea una segunda red tipo `netstack`. |
| `ansible/rocky/` | Prepara Rocky e instala DevStack con el inventario que produce Terraform. |
| `workspace/` | Contiene la prueba que ejecuta `ansible/demo.yml` para desplegar y verificar CirrOS. |

La estructura y el orden del despliegue siguen el [repositorio de referencia](https://gitlab.com/alejandro.mellado/devstack/-/tree/ea1f18bc8d501e56aaaad293aab8dd187a7398a5).

## Análisis inicial

| | DevStack sobre Debian 12 | miniONE sobre Ubuntu 22.04 |
|---|---|---|
| Instalación | `stack.sh` lee `local.conf` y prepara OpenStack a partir de repositorios de código y paquetes del sistema. | `minione` configura el servidor frontal y un nodo KVM mediante paquetes de OpenNebula. |
| Servicios y panel | Nova gestiona el cómputo, Neutron la red, Glance las imágenes, Keystone la identidad y Horizon el panel. Utiliza una base de datos y RabbitMQ. | El servidor frontal centraliza la gestión, Sunstone ofrece la interfaz y el nodo KVM ejecuta las VM. |
| Dependencias | Git, Python, repositorios de software y KVM accesible al sistema. | Repositorio de paquetes de OpenNebula, acceso administrativo, OpenSSH y KVM. |

Fuentes oficiales. [DevStack 2026.1](https://docs.openstack.org/devstack/2026.1/overview.html) y [miniONE](https://github.com/OpenNebula/minione).

## Adaptaciones

- `ansible/rocky/preconfig.yml` usa DNF para instalar Git, sudo, ACL, certificados, wget, hostname, complementos de DNF y Python 3.11. DevStack usa Python 3.11, la versión que su configuración de CI selecciona para Rocky 9. [Configuración de CI de DevStack](https://opendev.org/openstack/devstack/src/branch/stable/2026.1/.zuul.yaml)
- Se fija la revisión de DevStack de la rama `stable/2026.1`. Su URL de dependencias RDO para `centos9-2026.1` devuelve 404. El playbook aplica un ajuste local para usar el canal de dependencias EL9 de RDO Epoxy, que aporta paquetes para RabbitMQ y Open vSwitch. Los componentes de OpenStack se instalan desde las ramas que dicta DevStack 2026.1. [Repositorio de dependencias RDO](https://trunk.rdoproject.org/centos9-epoxy/delorean-deps.repo)
- Se comprueban la IPv4 de gestión y `/dev/kvm`. Se usa la red privada predeterminada del proyecto `demo` y Ansible Vault para proteger la contraseña. La comprobación funcional se ejecuta con `ansible/demo.yml`, por lo que se desactiva la instalación de Tempest en este laboratorio.
- Rocky usa MariaDB como servidor de base de datos. El cliente OpenStack queda en `/usr/local/bin`, que el script de prueba agrega a su ruta para ejecutarse también bajo sudo.
- El instalador de DevStack deja SELinux en modo permisivo en Rocky para que Apache sirva Horizon. Se ejecuta en un invitado dedicado y se publican SSH y Horizon únicamente en la interfaz local del anfitrión.

## Despliegue desde cero

Usa un anfitrión Linux x86_64 con QEMU/KVM (incluido `qemu-img`), libvirt, firmware UEFI para QEMU (OVMF), Terraform 1.5 o posterior y OpenSSH. Comprueba que la virtualización anidada esté habilitada y que tu usuario tenga acceso a libvirt. Los comandos están pensados para ejecutarse en el anfitrión KVM, que debe poder llegar por SSH a la VM.

```bash
git clone https://github.com/SebaDRiquelmeS/devstack-iaas.git
cd devstack-iaas
virsh -c qemu:///system list --all
virsh -c qemu:///system net-list --all
```

### 1. Terraform crea Rocky

La red libvirt `default` debe estar activa y ofrecer DHCP y salida a Internet. Puedes seleccionar otra red existente con `management_network`. Usa la clave pública que corresponda a tu cliente SSH. Si aún no tienes una, puedes crearla con `ssh-keygen -t ed25519`.

```bash
cp terraform/rocky/devstack/terraform.tfvars.example terraform/rocky/devstack/terraform.tfvars
terraform -chdir=terraform/rocky/devstack init
terraform -chdir=terraform/rocky/devstack plan
terraform -chdir=terraform/rocky/devstack apply
terraform -chdir=terraform/rocky/devstack output -raw ansible_inventory > ansible/rocky/inventory.yml
```

Si tu instalación usa los daemons modulares de libvirt y Terraform indica que falta `libvirt-sock`, habilita el socket `virtproxyd.socket` del sistema. Antes de ejecutar Ansible, comprueba la identidad SSH del invitado en su consola y conéctate una vez como `rocky` a la IP del inventario para registrar su clave de host.

La descarga de la imagen y de los repositorios de DevStack puede tardar en el primer despliegue. El módulo descarga una imagen oficial Rocky 9 GenericCloud. Si ya la verificaste y la tienes descargada, puedes indicar su ruta absoluta con `rocky_image`. La VM usa UEFI, CPU `host-passthrough` y un disco QCOW2 de 65 GiB. cloud-init adjunta la clave SSH pública para `rocky` y configura las interfaces por su MAC. En virt-manager aparece como `rockystack` en la conexión de sistema.

En el flujo de dos interfaces, `netstack` usa `172.24.4.0/24` para las IP flotantes y la interfaz de gestión conserva la salida a Internet. Si ese rango ya está en uso, configura otro IPv4 /24 con `netstack_cidr`. Elige redes que no se superpongan con la red privada de OpenStack. Establece `enable_netstack = false` para usar una sola interfaz con la configuración de red predeterminada de DevStack. El inventario generado incluye la IP de gestión y, si se habilitó, la interfaz externa de Neutron.

### 2. Ansible instala DevStack

Desde el anfitrión con Python 3.12 o posterior y pipx, instala la versión de Ansible Core con la que se verificó el laboratorio. Crea el archivo cifrado y agrega la variable `devstack_admin_password` con un valor alfanumérico de 16 a 64 caracteres.

```bash
pipx install ansible-core==2.21.6
ansible-vault create ansible/rocky/secrets.yml
ansible-playbook -i ansible/rocky/inventory.yml ansible/rocky/preconfig.yml \
  --ask-vault-pass -e @ansible/rocky/secrets.yml
```

Ansible espera SSH y cloud-init, comprueba `/dev/kvm` e instala DevStack. El registro de instalación queda en `/opt/stack/logs/stack.sh.log`. Si usas otra clave privada, agrega `--private-key RUTA` a ambos comandos `ansible-playbook`. Si tu usuario solicita contraseña para sudo, agrega `--ask-become-pass`. Para usar una VM Rocky ya existente, copia `ansible/rocky/inventory.example.yml` a `ansible/rocky/inventory.yml` y configura sus direcciones y usuario.

### 3. Verifica CirrOS y Horizon

```bash
ansible-playbook -i ansible/rocky/inventory.yml ansible/demo.yml
terraform -chdir=terraform/rocky/devstack output -raw horizon_url
```

La prueba verifica Nova, crea o reutiliza `iaas-cirros` y espera el inicio de sesión en consola. En la URL de Horizon, entra como `demo` con la contraseña configurada y abre **Proyecto → Cómputo → Instancias**.

## Evidencia del laboratorio original

En el equipo donde se hizo la práctica, [Horizon](http://127.0.0.1:8089/dashboard/) permite entrar como `demo` con la contraseña en `../devstack-iaas-lab/rocky/admin-password`. En Horizon, abre **Proyecto → Cómputo → Instancias**.

```bash
../devstack-iaas-lab/rocky/abrir-gestor.sh rocky
../devstack-iaas-lab/rocky/abrir-gestor.sh instancias
```

Ansible verificó `iaas-cirros` en estado `ACTIVE`, con IPv4 privada `10.0.0.11` y un inicio de sesión disponible en consola. La segunda ejecución reutilizó el mismo ID sin cambios.

La conexión QEMU/KVM de sesión contiene `devstack-rocky`. La conexión SSH de solo lectura al nodo muestra el dominio KVM que Nova gestiona como `iaas-cirros`. Ubuntu quedó con su estado guardado en virt-manager para liberar memoria.

[Resumen técnico de una página](resumen-tecnico.pdf) · [Evidencia de instalación y demostración](evidencia-despliegue.txt)
