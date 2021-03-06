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
clean: clean-hello-go clean-linkerd clean-ingress-nginx clean-metallb
	@-ansible-playbook teardown.yaml
dist-clean: clean
	@$(RM) *.bak *.retry .*.sw? **/.*.sw?
	$(SUDO) $(RM) -rf .ansible
list ls:
	@docker images
	@$(SUDO) virsh net-list
	@$(SUDO) virsh list

# helm based install/uninstall
install-%:
	@helm install $* charts/$*
uninstall-%:
	@helm uninstall $*

# ScyllaDB
.PHONY: scylla clean-scylla
scylla: cert-manager
	@kubectl apply -f ./manifests/op/scylla.yaml
	@kubectl apply -f ./manifests/ns/scylla.yaml
clean-scylla:
	@-kubectl delete -f ./manifests/ns/scylla.yaml
	@-kubectl delete -f ./manifests/op/scylla.yaml

# cert-manager
.PHONY: cert-manager clean-cert-manager
cert-manager:
	@kubectl apply -f ./manifests/yaml/cert-manager.yaml
	@kubectl wait -n cert-manager --for=condition=ready pod -l app=cert-manager --timeout=60s
clean-cert-manager:
	@-kubectl delete -f ./manifests/yaml/cert-manager.yaml

# Tidis TiKV Redis query layer
.PHONY: tidis clean-tidis
tidis: metallb tikv-cluster
	@kubectl apply -f ./manifests/ns/tidis.yaml
	@kubectl apply -f ./manifests/cm/tidis.yaml
	@kubectl apply -f ./manifests/deploy/tidis.yaml
	@kubectl apply -f ./manifests/svc/tidis.yaml
clean-tidis:
	@kubectl delete -f ./manifests/svc/tidis.yaml
	@kubectl delete -f ./manifests/deploy/tidis.yaml
	@kubectl delete -f ./manifests/cm/tidis.yaml
	@kubectl delete -f ./manifests/ns/tidis.yaml

# TiKV cluster
#
# https://tikv.org/docs/4.0/tasks/try/tikv-operator/#step-2-deploy-tikv-operator
.PHONY: tikv-cluster clean-tikv-cluster
tikv-cluster:
	@kubectl apply -f ./manifests/sc/tikv-cluster/
	@kubectl apply -f ./manifests/pv/tikv-cluster/
	@kubectl apply -f ./manifests/ns/tikv-cluster/
	#@kubectl apply -f ./manifests/pvc/tikv-cluster/
	#@kubectl apply -f https://raw.githubusercontent.com/pingcap/tidb-operator/master/manifests/crd.yaml
	@kubectl apply -f https://raw.githubusercontent.com/tikv/tikv-operator/master/manifests/crd.v1beta1.yaml
	@-helm repo add pingcap https://charts.pingcap.org/
	@-helm install -n tikv-operator tikv-operator pingcap/tikv-operator --version v0.1.0
	@kubectl apply -n tikv-cluster -f ./manifests/op/tikv-cluster/

clean-tikv-cluster:
	@-kubectl delete -n tikv-cluster -f ./manifests/op/tikv-cluster/
	#@-kubectl delete -f ./manifests/pvc/tikv-cluster/
	@-kubectl delete -f ./manifests/ns/tikv-cluster/
	@-kubectl delete -f ./manifests/pv/tikv-cluster/
	@-kubectl delete -f ./manifests/sc/tikv-cluster/

# Redis cluster
.PHONY: redis-cluster clean-redis-cluster
redis-cluster:
	@kubectl apply -f ./manifests/pv/redis-cluster/
	@kubectl apply -f ./manifests/ns/redis-cluster/
	@kubectl apply -f ./manifests/cm/redis-cluster/
	@kubectl apply -f ./manifests/pvc/redis-cluster/
	@kubectl apply -f ./manifests/rs/redis-cluster/
	@kubectl apply -f ./manifests/svc/redis-cluster/
clean-redis-cluster:
	@-kubectl delete --all svc -n redis-cluster
	@-kubectl delete --all rs  -n redis-cluster
	@-kubectl delete --all pvc -n redis-cluster
	@-kubectl delete cm -l app=redis -n redis-cluster
	@-kubectl delete ns redis-cluster
	@-kubectl delete pv -l app=redis-cluster

# MySQL
.PHONY: mysql clean-mysql
mysql:
	@kubectl apply -f ./manifests/pv/mysql.yaml
	@kubectl apply -f ./manifests/pvc/mysql.yaml
	@kubectl apply -f ./manifests/rs/mysql.yaml
	@kubectl apply -f ./manifests/svc/mysql.yaml
clean-mysql:
	@-kubectl delete svc/mysql
	@-kubectl delete rs/mysql
	@-kubectl delete pvc/mysql
	@-kubectl delete pv/mysql

# simple hello app
.PHONY: clean-hello-go
hello-%:
	@cd examples/hello && docker build -f Dockerfile.hello-go \
		-t host.local:5000/hello-$*:latest .
push-hello-%: hello-%
	@docker push host.local:5000/hello-$*:latest
clean-hello-go:
	@-docker rmi host.local:5000/hello-go
	@-cd examples/hello && go clean

# prometheus
.PHONY: prom clean-prom
prom: cm/prometheus deploy/prometheus
clean-prom: clean-deploy/prometheus clean-cm/prometheus

# NodePort based ingress-nginx
.PHONY: ingress-nginx clean-ingress-nginx
ingress-nginx:
	@kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/mandatory.yaml
	@kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/provider/baremetal/service-nodeport.yaml
clean-ingress-nginx:
	@-kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/provider/baremetal/service-nodeport.yaml
	@-kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/mandatory.yaml

# linkerd
.PHONY: linkerd clean-linkerd cat-linkerd ls-linkerd test-linkerd
linkerd:
	@curl -sL https://run.linkerd.io/install | sh
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

# metallb software load balancer
.PHONY: metallb clean-metallb
metallb:
	@kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.5/manifests/namespace.yaml
	@kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.5/manifests/metallb.yaml
	@kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
	@kubectl apply -f ./manifests/cm/metallb.yaml
clean-metallb:
	@-kubectl delete ns metallb-system

# kubectl aliases
.PHONY: dashboard
dashboard:
	@kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-rc5/aio/deploy/recommended.yaml
po/%:
	@kubectl create -f manifests/po/$*.yaml
svc/%:
	@kubectl create -f manifests/svc/$*.yaml
deploy/%:
	@kubectl create -f manifests/deploy/$*.yaml
ss/%:
	@kubectl create -f manifests/ss/$*.yaml
ds/%:
	@kubectl create -f manifests/ds/$*.yaml
cm/%:
	@kubectl create -f manifests/cm/$*.yaml
ing/%: ingress-nginx
	@kubectl create -f manifests/ing/$*.yaml
clean-po/%:
	@-kubectl delete -f manifests/po/$*.yaml
clean-svc/%:
	@-kubectl delete -f manifests/svc/$*.yaml
clean-deploy/%:
	@-kubectl delete -f manifests/deploy/$*.yaml
clean-ss/%:
	@-kubectl delete -f manifests/ss/$*.yaml
clean-ds/%:
	@-kubectl delete -f manifests/ds/$*.yaml
clean-cm/%:
	@-kubectl delete -f manifests/cm/$*.yaml
clean-ing/%:
	@-kubectl delete -f manifests/ing/$*.yaml

# CI targets
.PHONY: ansible
ci-%: ci-ping-%
	ansible-playbook -vvv $*.yaml \
		-i inventory.yaml -c local -e ci=true -e build=true \
		-e network=true -e gitsite=https://github.com/
ci-hello-go: hello-go
ci-ping-%:
	ansible -vvv -m ping -i inventory.yaml -c local $*
ansible:
	git clone https://github.com/ansible/ansible .ansible
	cd .ansible \
		&& $(SUDO) pip install -r requirements.txt \
		&& $(SUDO) python setup.py install 2>&1 > /dev/null
