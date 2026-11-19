# OpenStack DevStack en Rocky Linux 9

Laboratorio IaaS de un solo nodo con KVM. Ansible prepara Rocky Linux, instala OpenStack y crea una VM CirrOS para comprobar Nova, Glance y Neutron. Horizon permite consultar la instancia desde el navegador.

El proyecto sigue la estructura por distribución en `ansible/rocky/` y la separación de pruebas en `workspace/` del [repositorio de referencia](https://gitlab.com/alejandro.mellado/devstack/-/tree/ea1f18bc8d501e56aaaad293aab8dd187a7398a5).

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

## Despliegue

1. Prepara un nodo dedicado Rocky Linux 9 amd64 con IPv4 estable, acceso SSH con sudo, salida a Internet y `/dev/kvm`. Si el nodo es una VM, habilita virtualización anidada. El nodo de esta práctica usa 6 vCPU, 8 GiB de RAM y un disco virtual de 65 GiB.
2. Desde un controlador Linux con Python 3.12 o posterior, instala Ansible Core. El laboratorio se verificó con Ansible Core 2.21.6. A continuación copia el inventario y crea el archivo cifrado. Configura `ansible_host` para SSH y `devstack_host_ip` con la dirección IPv4 dentro del nodo. En el archivo cifrado, pon `devstack_admin_password` con un valor alfanumérico de 16 a 64 caracteres.

   ```bash
   pipx install ansible-core==2.21.6
   cp ansible/rocky/inventory.example.yml ansible/rocky/inventory.yml
   ansible-vault create ansible/rocky/secrets.yml
   ```

   Comprueba el acceso al nodo con `ssh rocky@IP_DEL_NODO` antes de ejecutar Ansible. Ajusta `ansible_user` si usas otra cuenta con sudo.

3. Instala la plataforma y levanta CirrOS. Agrega `--ask-become-pass` si sudo solicita contraseña.

   ```bash
   ansible-playbook -i ansible/rocky/inventory.yml ansible/rocky/preconfig.yml \
     --ask-vault-pass -e @ansible/rocky/secrets.yml
   ansible-playbook -i ansible/rocky/inventory.yml ansible/demo.yml
   ```

La instalación guarda su registro en `/opt/stack/logs/stack.sh.log`. Ansible marca el nodo como instalado una vez que `stack.sh` finaliza con éxito. La prueba consulta Nova, crea o reutiliza `iaas-cirros` y espera el inicio de sesión en la consola.

En una instalación nueva, abre `http://IP_DEL_NODO/dashboard/` desde una red con acceso al nodo e ingresa como `demo` con la contraseña que configuraste.

## Evidencia del laboratorio original

En el equipo donde se hizo la práctica, [Horizon](http://127.0.0.1:8089/dashboard/) permite entrar como `demo` con la contraseña en `../devstack-iaas-lab/rocky/admin-password`. En Horizon, abre **Proyecto → Cómputo → Instancias**.

```bash
../devstack-iaas-lab/rocky/abrir-gestor.sh rocky
../devstack-iaas-lab/rocky/abrir-gestor.sh instancias
```

Ansible verificó `iaas-cirros` en estado `ACTIVE`, con IPv4 privada `10.0.0.11` y un inicio de sesión disponible en consola. La segunda ejecución reutilizó el mismo ID sin cambios.

La conexión QEMU/KVM de sesión contiene `devstack-rocky`. La conexión SSH de solo lectura al nodo muestra el dominio KVM que Nova gestiona como `iaas-cirros`. Ubuntu quedó con su estado guardado en virt-manager para liberar memoria.

[Resumen técnico de una página](resumen-tecnico.pdf) · [Evidencia de instalación y demostración](evidencia-despliegue.txt)
