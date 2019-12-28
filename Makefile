SUDO ?= sudo
all: teardown cluster-latest kuard
.PHONY: all boot bootstrap teardown
boot bootstrap: cluster
%:
	@ansible-playbook $*.yml -e latest=false -e full=false
%-latest:
	@ansible-playbook $*.yml -e latest=true -e full=false
%-latest-full:
	@ansible-playbook $*.yml -e latest=true -e full=true
teardown:
	-@ansible-playbook teardown.yml
%-pod:
	@kubectl create -f manifests/po/$*.yml
%-deploy:
	@kubectl create -f manifests/deploy/$*.yml
clean-%-pod:
	@kubectl delete -f manifests/po/$*.yml
clean-%-deploy:
	@kubectl delete -f manifests/deploy/$*.yml
# http://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/
test test-connectivity:
	@kubectl delete -f https://raw.githubusercontent.com/cilium/cilium/1.6.5/examples/kubernetes/connectivity-check/connectivity-check.yaml
	@kubectl create -f https://raw.githubusercontent.com/cilium/cilium/1.6.5/examples/kubernetes/connectivity-check/connectivity-check.yaml

# Some cleanup targets
.PHONY: clean dist-clean
clean:
	@$(RM) *.bak *.retry .*.sw? **/.*.sw?
dist-clean: clean teardown
	$(SUDO) $(RM) -rf .ansible

# TravisCI targets
.PHONY: ci-ansible
ci-test-%-latest: ci-ping-%
	ansible-playbook -vvv $*.yml \
		-i inventory.yml -c local -e ci=true -e latest=true \
		-e full=false -e gitsite=https://github.com/
ci-ping-%:
	ansible -vvv -m ping -i inventory.yml -c local $*
ci-ansible:
	git clone https://github.com/ansible/ansible .ansible
	cd .ansible \
		&& $(SUDO) pip install -r requirements.txt \
		&& $(SUDO) python setup.py install 2>&1 > /dev/null
