#!/usr/bin/env bash

#https://argocd-notifications.readthedocs.io/en/stable/services/slack/

kubectl apply -f argocd-notifications-secret.yaml
kubectl apply -f argocd-notifications-cm.yaml
kubectl apply -f demo-application.yaml

