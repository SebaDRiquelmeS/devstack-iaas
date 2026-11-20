TF_DIR     := terraform/rocky/devstack
INVENTORY  := ansible/rocky/inventory.yml
SECRETS    := ansible/rocky/secrets.yml
KEY        ?= $(HOME)/.ssh/id_ed25519
VAULT_ARGS ?= --ask-vault-pass
TF         := terraform -chdir=$(TF_DIR)
ANSIBLE    := ansible-playbook -i $(INVENTORY) --private-key $(KEY)

.PHONY: help init fmt check plan apply inventory preconfig demo verify deploy destroy

help: ## Muestra los comandos disponibles
	@printf '%s\n' \
	  'make init                 Inicializa Terraform' \
	  'make plan|apply           Planifica/aplica la VM Rocky' \
	  'make inventory            Genera el inventario Ansible' \
	  'make preconfig            Instala DevStack' \
	  'make demo|verify          Verifica CirrOS; verify además comprueba Horizon' \
	  'make deploy               Ejecuta init, apply, inventory, preconfig y demo' \
	  'make check                Valida Terraform, Ansible y el script de demo' \
	  'make destroy              Elimina los recursos de este laboratorio' \
	  '' \
	  'Variables: KEY=~/.ssh/id_ed25519 VAULT_ARGS=--ask-vault-pass' \
	  'Ejemplo: make preconfig KEY=~/.ssh/devstack_ed25519 VAULT_ARGS="--vault-password-file ansible/rocky/.vault_pass"'

init: ## Inicializa providers de Terraform
	$(TF) init

fmt: ## Formatea los archivos Terraform
	terraform fmt -recursive terraform

check: ## Ejecuta validaciones estáticas
	terraform fmt -check -recursive terraform
	$(TF) validate
	ansible-playbook --syntax-check -i ansible/rocky/inventory.example.yml ansible/rocky/preconfig.yml
	ansible-playbook --syntax-check -i ansible/rocky/inventory.example.yml ansible/demo.yml
	bash -n workspace/deploy-cirros.sh

plan: ## Muestra los cambios de infraestructura
	$(TF) plan

apply: ## Crea la VM Rocky y las redes
	$(TF) apply

inventory: ## Genera ansible/rocky/inventory.yml desde Terraform
	$(TF) output -raw ansible_inventory > $(INVENTORY)

preconfig: ## Instala OpenStack DevStack
	$(ANSIBLE) ansible/rocky/preconfig.yml $(VAULT_ARGS) -e @$(SECRETS)

demo: ## Crea o reutiliza iaas-cirros y valida su arranque
	$(ANSIBLE) ansible/demo.yml

verify: demo ## Verifica CirrOS y la respuesta HTTP de Horizon
	@url="$$($(TF) output -raw horizon_url)"; \
	code="$$(curl -s -o /dev/null -w '%{http_code}' "$$url")"; \
	printf 'Horizon: HTTP %s en %s\n' "$$code" "$$url"; \
	test "$$code" = '200' -o "$$code" = '302'

deploy: init apply inventory preconfig demo ## Despliegue completo

destroy: ## Destruye la infraestructura de este laboratorio
	$(TF) destroy
