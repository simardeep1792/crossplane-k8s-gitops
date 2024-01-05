project := phx-01had7ny8p
name := gitops-cluster

dockerpw = $(shell cat gcr-credentials.json)

define prompt_for_project
	@CURRENT_PROJECT_ID=$$(gcloud config get-value project 2>/dev/null); \
	CURRENT_PROJECT_NAME=$$(gcloud projects describe $$CURRENT_PROJECT_ID --format='value(name)' 2>/dev/null); \
	echo "Current GCP Project ID: $$CURRENT_PROJECT_ID"; \
	echo "Current GCP Project Name: $$CURRENT_PROJECT_NAME"; \
	echo "Press enter to confirm or type a different project ID: "; \
	read NEW_PROJECT_ID; \
	if [ -z "$$NEW_PROJECT_ID" ]; then \
		export project=$$CURRENT_PROJECT_ID; \
	else \
		export project=$$NEW_PROJECT_ID; \
		echo "Setting $$NEW_PROJECT_ID as the default project"; \
		gcloud config set project $$NEW_PROJECT_ID; \
	fi; \
	echo "Using project: $$project"
endef

.PHONY: service-account
service-account:
		$(call prompt_for_project)
		gcloud iam service-accounts create crossplane-provider --display-name "crossplane-provider"
		gcloud projects add-iam-policy-binding "$(project)" \
				--member "serviceAccount:crossplane-provider@$(project).iam.gserviceaccount.com" \
				--role roles/editor
		gcloud projects add-iam-policy-binding "$(project)" \
				--member "serviceAccount:crossplane-provider@$(project).iam.gserviceaccount.com" \
				--role roles/resourcemanager.projectIamAdmin
		gcloud iam service-accounts keys create gcp-credentials.json \
				--iam-account=crossplane-provider@$(project).iam.gserviceaccount.com

.PHONY: create-dns01-solver-sa
create-dns01-solver-sa:
		$(call prompt_for_project)
		gcloud iam service-accounts create dns01-solver --display-name "DNS01 Solver"
		gcloud projects add-iam-policy-binding "$(project)" \
				--member "serviceAccount:dns01-solver@$(project).iam.gserviceaccount.com" \
				--role roles/dns.admin

.PHONY: gcp-secret
gcp-secret:
		$(call prompt_for_project)
		kubeseal --fetch-cert \
				--controller-name=sealed-secrets-controller \
				--controller-namespace=flux-system > k8s/flux-system/pub-sealed-secrets.pem
		kubectl create secret generic gcp-secret \
				--namespace crossplane-system \
				--from-file=creds=./gcp-credentials.json -o yaml \
				--dry-run > k8s/crossplane-system/gcp-credentials.yaml
		kubeseal --format yaml \
				--cert k8s/flux-system/pub-sealed-secrets.pem < k8s/crossplane-system/gcp-credentials.yaml > k8s/crossplane-system/gcp-credentials-enc.yaml
		rm -f k8s/crossplane-system/gcp-credentials.yaml

# create secrets in flux-system and server namespace for image reconciliation and image pull respectively
.PHONY: account_keys
account_keys:
		$(call prompt_for_project)
		gcloud iam service-accounts keys create gcr-credentials.json --iam-account gcr-credentials-sync@$(project).iam.gserviceaccount.com


.PHONY: registry-secret
registry-secret: account_keys
		kubectl create secret docker-registry gcr-credentials \
					--namespace=server \
                    --dry-run=client \
                    --docker-server=northamerica-northeast1-docker.pkg.dev \
  					--docker-username=_json_key \
  					--docker-password='$(dockerpw)' \
                    -o yaml | kubectl apply -f -
		kubectl create secret docker-registry gcr-credentials \
					--namespace=flux-system \
                    --dry-run=client \
                    --docker-server=northamerica-northeast1-docker.pkg.dev \
  					--docker-username=_json_key \
  					--docker-password='$(dockerpw)' \
                    -o yaml | kubectl apply -f -