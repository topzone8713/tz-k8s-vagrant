#!/usr/bin/env bash

#set -x
## https://docs.k8s.amazon.com/ko_kr/eks/latest/userguide/add-user-role.html

source /root/.bashrc
function prop { key="${2}=" file="/root/.k8s/${1}" rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); [[ -z "$rslt" ]] && key="${2} = " && rslt=$(grep "${3:-}" "$file" -A 10 | grep "$key" | head -n 1 | cut -d '=' -f2 | sed 's/ //g'); rslt=$(echo "$rslt" | tr -d '\n' | tr -d '\r'); echo "$rslt"; }
#bash /vagrant/tz-local/resource/makeuser/eks-users.sh
cd /vagrant/tz-local/resource/makeuser

k8s_project=$(prop 'project' 'project')
k8s_domain=$(prop 'project' 'domain')

aws_account_id=$(aws sts get-caller-identity --query Account --output text)

export AWS_DEFAULT_PROFILE="default"
aws sts get-caller-identity
kubectl -n kube-system get configmap aws-auth -o yaml
#kubectl get node

#PROJECTS=(default)
PROJECTS=(devops devops-dev default argocd consul monitoring vault)
for item in "${PROJECTS[@]}"; do
  if [[ "${item}" != "NAME" ]]; then
    kubectl create ns ${item}

    staging="dev"
    if [[ "${item/*-dev/}" != "" ]]; then
      staging="prod"
    fi
cat <<EOF > sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${item}-svcaccount
  namespace: ${item}
EOF
    kubectl -n ${item} apply -f sa.yaml

    if [ "${staging}" == "prod" ]; then
cat <<EOF > sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${item}-stg-svcaccount
  namespace: ${item}
EOF
      kubectl -n ${item} apply -f sa.yaml
    fi
  fi
done
rm -Rf sa.yaml

#k8s_role=$(aws iam list-roles --out=text | grep "${k8s_project}2" | grep "0000000" | head -n 1 | awk '{print $7}')
pushd `pwd`
cd /vagrant/terraform-aws-eks/workspace/base
k8s_role=$(terraform output | grep cluster_iam_role_arn | awk '{print $3}' | tr "/" "\n" | tail -n 1 | sed 's/"//g')
popd
echo k8s_role: ${k8s_role}

# add a eks-users
#kubectl delete -f eks-roles.yaml
#kubectl delete -f eks-rolebindings.yaml
kubectl apply -f eks-roles.yaml
kubectl apply -f eks-rolebindings.yaml
kubectl apply -f eks-rolebindings-developer.yaml

eksctl get iamidentitymapping --cluster ${k8s_project}
kubectl auth can-i --list
kubectl auth can-i --list --as=[${k8s_project}-k8sDev]
kubectl auth can-i --list --as=${k8s_project}-k8sDev

exit 0

# for ${k8s_project}-k8sDev
1) Role: devops-developer
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: devops
  name: devops-developer
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["get", "watch", "list"]

2) role Group: ${k8s_project}-k8sDev
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: ${k8s_project}-k8sDev
subjects:
- kind: Group
  name: ${k8s_project}-k8sDev
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: devops-developer
  apiGroup: rbac.authorization.k8s.io

3) terraform locals.tf
  aws_auth_roles = [
    {
      rolearn  = "arn:aws:iam::${var.account_id}:role/${local.cluster_name}-k8sDev"
      username = "${local.cluster_name}-k8sDev"
      groups   = ["${k8s_project}-k8sDev"]
    },

# for ${k8s_project}-k8sAdmin
1) Role: devops-developer
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: devops-admin
rules:
- apiGroups: ["", "metrics.k8s.io", "extensions", "apps", "batch"]
  resources: ["*"]
  verbs: ["*"]

2) role Group: ${k8s_project}-k8sAdmin
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${k8s_project}-k8sAdmin
subjects:
- kind: Group
  name: ${k8s_project}-k8sAdmin
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: devops-admin
  apiGroup: rbac.authorization.k8s.io

3) terraform locals.tf
  aws_auth_roles = [
    {
      rolearn  = "arn:aws:iam::${var.account_id}:role/${local.cluster_name}-k8sAdmin"
      username = "${local.cluster_name}-k8sAdmin"
      groups   = ["${k8s_project}-k8sAdmin"]
    },
