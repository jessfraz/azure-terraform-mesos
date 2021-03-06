SHELL := /bin/bash

null :=
space := ${null} ${null}
${space} := ${space} # ${ } is a space.
comma := ,
define newline
\n
endef

# if this session isn't interactive, then we don't want to allocate a
# TTY, which would fail, but if it is interactive, we do want to attach
# so that the user can send e.g. ^C through.
INTERACTIVE := $(shell [ -t 0 ] && echo 1 || echo 0)
ifeq ($(INTERACTIVE), 1)
	DOCKER_FLAGS += -t
endif

check_defined = \
				$(strip $(foreach 1,$1, \
				$(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = \
				  $(if $(value $1),, \
				  $(error Undefined $1$(if $2, ($2))$(if $(value @), \
				  required by target `$@')))

CLIENT_ID := ${AZURE_CLIENT_ID}
CLIENT_SECRET := ${AZURE_CLIENT_SECRET}
TENANT_ID := ${AZURE_TENANT_ID}
SUBSCRIPTION_ID := ${AZURE_SUBSCRIPTION_ID}

PREFIX := jessfraz
LOCATION := westus2

MASTER_COUNT := 5
AGENT_COUNT := 18

TMPDIR:=$(CURDIR)/_tmp

.PHONY: ips
ips:
	$(foreach NUM,$(shell [[ $(MASTER_COUNT) == 0 ]] || seq 5 1 $$(( $(MASTER_COUNT) + 4))),$(call get_master_ips,$(NUM)))
	@echo "Master IPs: $(MASTER_IPS)"
	$(foreach NUM,$(shell [[ $(MASTER_COUNT) == 0 ]] || seq 5 1 $$(( $(MASTER_COUNT) + 4))),$(call get_zookeeper_config_ips,$(NUM),$(shell expr $(NUM) - 4)))

# Define the function to populate the MASTER_IPS variable with the
# corresponding IPs of the master private_ips.
# This assumes you are using three different regions and your terraform files
# set the cidr ranges to 10.0.0.0/16 10.1.0.0/16 and 10.2.0.0/16
# # @param number	  Number of the master.
define get_master_ips
$(eval MASTER_IPS := $(MASTER_IPS) 10.0.0.$(NUM) 10.1.0.$(NUM) 10.2.0.$(NUM))
endef

define get_zookeeper_config_ips
$(eval ZOOKEEPER_CONFIG_IPS := $(ZOOKEEPER_CONFIG_IPS) server.$(2)=10.0.0.$(1):2888:3888)
endef

.PHONY: test
test: shellcheck ## Runs all the tests.

.PHONY: shellcheck
shellcheck: ## Run shellcheck on all scripts in the repository.
	docker run --rm -i $(DOCKER_FLAGS) \
		--name configs-shellcheck \
		-v $(CURDIR):/usr/src:ro \
		--workdir /usr/src \
		r.j3ss.co/shellcheck ./test.sh

TERRAFORM_FLAGS = -var "client_id=$(CLIENT_ID)"  \
		-var "client_secret=$(CLIENT_SECRET)"  \
		-var "tenant_id=$(TENANT_ID)"  \
		-var "subscription_id=$(SUBSCRIPTION_ID)"  \
		-var "prefix=$(PREFIX)" \
		-var "location=$(LOCATION)" \
		-var "master_count=$(MASTER_COUNT)" \
		-var "agent_count="$(AGENT_COUNT)

MESOS_TERRAFORM_FLAGS = -v "cloud_config_master=../_tmp/mesos/cloud-config-master.yml" \
	-v "cloud_config_bastion=../_tmp/mesos/cloud-config-bastion.yml" \
	-v "cloud_config_agent=../_tmp/mesos/cloud-config-agent.yml"

TERRAFORM_DIR=$(CURDIR)/terraform

MESOS_TMPDIR=$(TMPDIR)/mesos
.PHONY: mesos-config
mesos-config: clean ips $(MESOS_TMPDIR) $(MESOS_TMPDIR)/cloud-config-master.yml $(MESOS_TMPDIR)/cloud-config-agent.yml $(MESOS_TMPDIR)/cloud-config-bastion.yml

$(MESOS_TMPDIR):
	mkdir -p $(MESOS_TMPDIR)

$(MESOS_TMPDIR)/cloud-config-master.yml:
	sed "s#ZOOKEEPER_MASTER_IPS#$(subst ${space},:2181${comma},$(MASTER_IPS)):2181#g" $(CURDIR)/mesos/cloud-config-master.yml > $@
	sed -i "s#ZOOKEEPER_CONFIG_MASTER_IPS#$(subst ${space},${newline}    ,$(ZOOKEEPER_CONFIG_IPS))#g" $@

$(MESOS_TMPDIR)/cloud-config-agent.yml:
	sed "s#ZOOKEEPER_MASTER_IPS#$(subst ${space},:2181${comma},$(MASTER_IPS)):2181#g" $(CURDIR)/mesos/cloud-config-agent.yml > $@

$(MESOS_TMPDIR)/cloud-config-bastion.yml:
	sed "s#ZOOKEEPER_MASTER_IPS#$(subst ${space},:2181${comma},$(MASTER_IPS)):2181#g" $(CURDIR)/mesos/cloud-config-bastion.yml > $@

.PHONY: mesos-init
mesos-init:
	@:$(call check_defined, CLIENT_ID, Azure Client ID)
	@:$(call check_defined, CLIENT_SECRET, Azure Client Secret)
	@:$(call check_defined, TENANT_ID, Azure Tenant ID)
	@:$(call check_defined, SUBSCRIPTION_ID, Azure Subscription ID)
	cd $(TERRAFORM_DIR) && terraform init \
		-var "orchestrator=mesos" \
		$(MESOS_TERRAFORM_FLAGS) \
		$(TERRAFORM_FLAGS)

.PHONY: mesos-apply
mesos-apply: mesos-init mesos-config ## Run terraform apply for mesos.
	cd $(TERRAFORM_DIR) && terraform apply \
		-var "orchestrator=mesos" \
		$(MESOS_TERRAFORM_FLAGS) \
		$(TERRAFORM_FLAGS)

.PHONY: mesos-destroy
mesos-destroy: mesos-init ## Run terraform destroy for mesos.
	cd $(TERRAFORM_DIR) && terraform destroy \
		-var "orchestrator=mesos" \
		$(MESOS_TERRAFORM_FLAGS) \
		$(TERRAFORM_FLAGS)

.PHONY: nomad-init
nomad-init:
	@:$(call check_defined, CLIENT_ID, Azure Client ID)
	@:$(call check_defined, CLIENT_SECRET, Azure Client Secret)
	@:$(call check_defined, TENANT_ID, Azure Tenant ID)
	@:$(call check_defined, SUBSCRIPTION_ID, Azure Subscription ID)
	cd $(TERRAFORM_DIR) && terraform init \
		-var "orchestrator=nomad" \
		$(TERRAFORM_FLAGS)

.PHONY: nomad-apply
nomad-apply: nomad-init nomad-config certs-config ## Run terraform apply for nomad.
	cd $(TERRAFORM_DIR) && terraform apply \
		-var "orchestrator=nomad" \
		$(TERRAFORM_FLAGS)

.PHONY: nomad-destroy
nomad-destroy: nomad-init ## Run terraform destroy for nomad.
	cd $(TERRAFORM_DIR) && terraform destroy \
		-var "orchestrator=nomad" \
		$(TERRAFORM_FLAGS)

NOMAD_TMPDIR=$(TMPDIR)/nomad
CONSUL_GOSSIP_ENCRYPTION_SECRET=$(shell docker run --rm r.j3ss.co/consul keygen)
NOMAD_GOSSIP_ENCRYPTION_SECRET=$(shell docker run --rm r.j3ss.co/nomad operator keygen)
.PHONY: nomad-config
nomad-config: clean ips $(NOMAD_TMPDIR) $(NOMAD_TMPDIR)/cloud-config-master.yml $(NOMAD_TMPDIR)/cloud-config-agent.yml $(NOMAD_TMPDIR)/cloud-config-bastion.yml

$(NOMAD_TMPDIR):
	mkdir -p $(NOMAD_TMPDIR)

$(NOMAD_TMPDIR)/cloud-config-master.yml:
	sed "s#CONSUL_GOSSIP_ENCRYPTION_SECRET#$(CONSUL_GOSSIP_ENCRYPTION_SECRET)#g" $(CURDIR)/nomad/cloud-config-master.yml > $@
	sed -i "s#NOMAD_GOSSIP_ENCRYPTION_SECRET#$(NOMAD_GOSSIP_ENCRYPTION_SECRET)#g" $@
	sed -i "s#COMMA_SEPARATED_MASTER_IPS#$(subst ${space},${comma},$(MASTER_IPS))#g" $@
	sed -i "s#NOMAD_MASTER_IPS#\"$(subst ${space},\"${comma} \",$(MASTER_IPS))\"#g" $@

$(NOMAD_TMPDIR)/cloud-config-agent.yml:
	sed "s#CONSUL_GOSSIP_ENCRYPTION_SECRET#$(CONSUL_GOSSIP_ENCRYPTION_SECRET)#g" $(CURDIR)/nomad/cloud-config-agent.yml > $@
	sed -i "s#NOMAD_GOSSIP_ENCRYPTION_SECRET#$(NOMAD_GOSSIP_ENCRYPTION_SECRET)#g" $@
	sed -i "s#COMMA_SEPARATED_MASTER_IPS#$(subst ${space},${comma},$(MASTER_IPS))#g" $@
	sed -i "s#NOMAD_MASTER_IPS#\"$(subst ${space},\"${comma} \",$(MASTER_IPS))\"#g" $@

$(NOMAD_TMPDIR)/cloud-config-bastion.yml:
	sed "s#CONSUL_GOSSIP_ENCRYPTION_SECRET#$(CONSUL_GOSSIP_ENCRYPTION_SECRET)#g" $(CURDIR)/nomad/cloud-config-bastion.yml > $@
	sed -i "s#NOMAD_GOSSIP_ENCRYPTION_SECRET#$(NOMAD_GOSSIP_ENCRYPTION_SECRET)#g" $@
	sed -i "s#COMMA_SEPARATED_MASTER_IPS#$(subst ${space},${comma},$(MASTER_IPS))#g" $@
	sed -i "s#NOMAD_MASTER_IPS#\"$(subst ${space},\"${comma} \",$(MASTER_IPS))\"#g" $@

CERTDIR=$(CURDIR)/nomad/certs

DOCKER_CFSSL=docker run --rm -i -v $(CERTDIR):$(CERTDIR) -w $(CERTDIR)
CFSSL_CMD=$(DOCKER_CFSSL) r.j3ss.co/cfssl
CFSSLJSON_CMD=$(DOCKER_CFSSL) --entrypoint cfssljson r.j3ss.co/cfssl

.PHONY: consul-certs
consul-certs:
	# generate a private CA certificate (consul-ca.pem) and key (consul-ca-key.pem)
	$(CFSSL_CMD) gencert -initca $(CERTDIR)/ca-csr.json | $(CFSSLJSON_CMD) -bare consul-ca
	# generate a certificate for all the Consul servers in a specific region (global)
	echo '{"key":{"algo":"rsa","size":2048}}' | $(CFSSL_CMD) gencert \
		-ca=consul-ca.pem -ca-key=consul-ca-key.pem -config=cfssl.json \
		-hostname="server.global.consul,localhost,127.0.0.1,10.0.0.5" - | \
		$(CFSSLJSON_CMD) -bare consul-server
	# generate a certificate for all the Consul clients in a specific region (global)
	echo '{"key":{"algo":"rsa","size":2048}}' | $(CFSSL_CMD) gencert \
		-ca=consul-ca.pem -ca-key=consul-ca-key.pem -config=cfssl.json \
		-hostname="client.global.consul,localhost,127.0.0.1,10.0.0.5" - | \
		$(CFSSLJSON_CMD) -bare consul-client
	# generate a certificate for the cli
	echo '{"key":{"algo":"rsa","size":2048}}' | $(CFSSL_CMD) gencert \
		-ca=consul-ca.pem -ca-key=consul-ca-key.pem -profile=client - | \
		$(CFSSLJSON_CMD) -bare consul-cli

.PHONY: nomad-certs
nomad-certs:
	# generate a private CA certificate (cnomad-ca.pem) and key (nomad-ca-key.pem)
	$(CFSSL_CMD) gencert -initca $(CERTDIR)/ca-csr.json | $(CFSSLJSON_CMD) -bare nomad-ca
	# generate a certificate for all the Nomad servers in a specific region (global)
	echo '{"key":{"algo":"rsa","size":2048}}' | $(CFSSL_CMD) gencert \
		-ca=nomad-ca.pem -ca-key=nomad-ca-key.pem -config=cfssl.json \
		-hostname="server.global.nomad,localhost,127.0.0.1,10.0.0.5" - | \
		$(CFSSLJSON_CMD) -bare nomad-server
	# generate a certificate for all the Nomad clients in a specific region (global)
	echo '{"key":{"algo":"rsa","size":2048}}' | $(CFSSL_CMD) gencert \
		-ca=nomad-ca.pem -ca-key=nomad-ca-key.pem -config=cfssl.json \
		-hostname="client.global.nomad,localhost,127.0.0.1,10.0.0.5" - | \
		$(CFSSLJSON_CMD) -bare nomad-client
	# generate a certificate for the cli
	echo '{"key":{"algo":"rsa","size":2048}}' | $(CFSSL_CMD) gencert \
		-ca=nomad-ca.pem -ca-key=nomad-ca-key.pem -profile=client - | \
		$(CFSSLJSON_CMD) -bare nomad-cli

.PHONY: certs-config
certs-config: consul-certs nomad-certs
	CERTDIR=$(CERTDIR) NOMAD_TMPDIR=$(NOMAD_TMPDIR) ./nomad/certs-config.sh

.PHONY: update
update: update-terraform ## Run all update targets.

TERRAFORM_BINARY:=$(shell which terraform || echo "/usr/local/bin/terraform")
TMP_TERRAFORM_BINARY:=/tmp/terraform
.PHONY: update-terraform
update-terraform: ## Update terraform binary locally from the docker container.
	@echo "Updating terraform binary..."
	$(shell docker run --rm --entrypoint bash r.j3ss.co/terraform -c "cd \$\$$(dirname \$\$$(which terraform)) && tar -Pc terraform" | tar -xvC $(dir $(TMP_TERRAFORM_BINARY)) > /dev/null)
	sudo mv $(TMP_TERRAFORM_BINARY) $(TERRAFORM_BINARY)
	sudo chmod +x $(TERRAFORM_BINARY)
	@echo "Update terraform binary: $(TERRAFORM_BINARY)"
	@terraform version

.PHONY: clean
clean: ## Cleans up any unneeded files.
	$(RM) -r $(TMPDIR)
	sudo $(RM) $(CERTDIR)/*.pem
	sudo $(RM) $(CERTDIR)/*.csr

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
