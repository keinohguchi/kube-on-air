# SPDX-License-Identifier: GPL-2.0
SUDO ?= sudo
all: cluster test
# ansible-playbook alias
%:
	@ansible-playbook $*.yaml -e latest=true -e build=true

# http://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/
.PHONY: test clean-test
test:
	@kubectl create -f https://raw.githubusercontent.com/cilium/cilium/1.6.6/examples/kubernetes/connectivity-check/connectivity-check.yaml
clean-test:
	@-kubectl delete -f https://raw.githubusercontent.com/cilium/cilium/1.6.6/examples/kubernetes/connectivity-check/connectivity-check.yaml

.PHONY: clean dist-clean list ls
clean:
	@-ansible-playbook teardown.yaml
dist-clean: clean
	@$(RM) *.bak *.retry .*.sw? **/.*.sw?
	$(SUDO) $(RM) -rf .ansible
list ls:
	@$(SUDO) virsh net-list
	@$(SUDO) virsh list

# kubectl aliases
.PHONY: dashboard
dashboard:
	@kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-rc5/aio/deploy/recommended.yaml
po/%:
	@kubectl create -f manifests/po/$*.yml
svc/%:
	@kubectl create -f manifests/svc/$*.yml
deploy/%:
	@kubectl create -f manifests/deploy/$*.yml
ss/%:
	@kubectl create -f manifests/ss/$*.yml
ds/%:
	@kubectl create -f manifests/ds/$*.yml
clean-po/%:
	@kubectl delete -f manifests/po/$*.yml
clean-svc/%:
	@kubectl delete -f manifests/svc/$*.yml
clean-deploy/%:
	@kubectl delete -f manifests/deploy/$*.yml
clean-ss/%:
	@kubectl delete -f manifests/ss/$*.yml
clean-ds/%:
	@kubectl delete -f manifests/ds/$*.yml

# linkerd
.PHONY: linkerd clean-linkerd cat-linkerd ls-linkerd test-linkerd
linkerd:
	@linkerd install | kubectl apply -f -
clean-linkerd:
	@-curl -sL https://run.linkerd.io/emojivoto.yml| kubectl delete -f -
	@-linkerd install --ignore-cluster | kubectl delete -f -
cat-linkerd:
	@linkerd install --ignore-cluster | less
ls-linkerd:
	@kubectl get -o wide -n linkerd po
test-linkerd:
	@curl -sL https://run.linkerd.io/emojivoto.yml | kubectl apply -f -
linkerd-%:
	@linkerd $*

# CI targets
.PHONY: ansible
ci-test-%: ci-ping-%
	ansible-playbook -vvv $*.yaml \
		-i inventory.yaml -c local -e ci=true -e build=true \
		-e network=true -e gitsite=https://github.com/
ci-ping-%:
	ansible -vvv -m ping -i inventory.yaml -c local $*
ansible:
	git clone https://github.com/ansible/ansible .ansible
	cd .ansible \
		&& $(SUDO) pip install -r requirements.txt \
		&& $(SUDO) python setup.py install 2>&1 > /dev/null
