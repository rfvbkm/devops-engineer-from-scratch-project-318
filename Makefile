IMAGE_NAME ?= project-devops-deploy
IMAGE_TAG ?= latest
CONTAINER_NAME ?= project-devops-deploy
APP_PORT ?= 8080
MANAGEMENT_PORT ?= 9090
SPRING_PROFILE ?= prod

ANSIBLE ?= ansible-playbook
GALAXY ?= ansible-galaxy
ROLLBACK_TAG ?=

# Пароль Vault: из .vault_pass или интерактивный запрос.
# Переопределение: make deploy VAULT_ARGS="--vault-password-file /path/to/pass"
ifndef VAULT_ARGS
  ifneq ($(wildcard .vault_pass),)
    VAULT_ARGS := --vault-password-file .vault_pass
  else
    VAULT_ARGS := --ask-vault-pass
  endif
endif

ansible-collections:
	$(GALAXY) collection install -r requirements.yml

provision: ansible-collections
	$(ANSIBLE) playbook.yml $(VAULT_ARGS)

deploy: ansible-collections
	$(ANSIBLE) deploy.yml $(VAULT_ARGS) -e app_image_tag=$(IMAGE_TAG)

rollback:
	@test -n "$(ROLLBACK_TAG)" || (echo "Укажите ROLLBACK_TAG=<git-sha|stable-tag> для отката" && exit 1)
	$(MAKE) deploy IMAGE_TAG=$(ROLLBACK_TAG)

.PHONY: ansible-collections provision deploy rollback
