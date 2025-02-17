# Create IAM role using the latest IRSA module
module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.52.2"

  role_name                          = "karpenter-controller-${var.cluster_name}"
  attach_karpenter_controller_policy = true

  karpenter_controller_cluster_id   = module.eks.cluster_id
  karpenter_controller_cluster_name = var.cluster_name
  karpenter_controller_node_iam_role_arns = [
    module.eks.eks_managed_node_groups["initial"].iam_role_arn
  ]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }
}

data "aws_ecrpublic_authorization_token" "token" {
  
}

resource "kubectl_manifest" "karpenter_crds" {
  for_each = {
    nodepool = <<-YAML
      apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      metadata:
        name: nodepools.karpenter.sh
      spec:
        group: karpenter.sh
        names:
          kind: NodePool
          plural: nodepools
          singular: nodepool
          shortNames: ["np"]
        scope: Cluster
        versions:
          - name: v1beta1
            served: true
            storage: false
            schema:
              openAPIV3Schema:
                type: object
                properties:
                  spec:
                    type: object
          - name: v1
            served: true
            storage: true
            schema:
              openAPIV3Schema:
                type: object
                properties:
                  spec:
                    type: object
    YAML

    nodeclaim = <<-YAML
      apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      metadata:
        name: nodeclaims.karpenter.sh
      spec:
        group: karpenter.sh
        names:
          kind: NodeClaim
          plural: nodeclaims
          singular: nodeclaim
          shortNames: ["nc"]
        scope: Cluster
        versions:
          - name: v1beta1
            served: true
            storage: false
            schema:
              openAPIV3Schema:
                type: object
                properties:
                  spec:
                    type: object
          - name: v1
            served: true
            storage: true
            schema:
              openAPIV3Schema:
                type: object
                properties:
                  spec:
                    type: object
    YAML

    ec2nodeclass = <<-YAML
      apiVersion: apiextensions.k8s.io/v1
      kind: CustomResourceDefinition
      metadata:
        name: ec2nodeclasses.karpenter.k8s.aws
      spec:
        group: karpenter.k8s.aws
        names:
          kind: EC2NodeClass
          plural: ec2nodeclasses
          singular: ec2nodeclass
          shortNames: ["enc"]
        scope: Cluster
        versions:
          - name: v1beta1
            served: true
            storage: false
            schema:
              openAPIV3Schema:
                type: object
                properties:
                  spec:
                    type: object
          - name: v1
            served: true
            storage: true
            schema:
              openAPIV3Schema:
                type: object
                properties:
                  spec:
                    type: object
    YAML
  }
  yaml_body = each.value
  depends_on = [module.eks]
}

# Deploy Karpenter using Helm
resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.2.1"

  # Updated settings format for v1.2.1
  set {
    name  = "controller.env[0].name"
    value = "CLUSTER_NAME"
  }
  set {
    name  = "controller.env[0].value"
    value = var.cluster_name
  }

  set {
    name  = "controller.env[1].name"
    value = "CLUSTER_ENDPOINT"
  }
  set {
    name  = "controller.env[1].value"
    value = module.eks.cluster_endpoint
  }

  set {
    name  = "controller.env[2].name"
    value = "AWS_REGION"
  }
  set {
    name  = "controller.env[2].value"
    value = data.aws_region.current.name
  }

  set {
    name  = "controller.env[3].name"
    value = "CLUSTER_DNS_DOMAIN"
  }
  set {
    name  = "controller.env[3].value"
    value = "cluster.local"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter_irsa.iam_role_arn
  }

  set {
    name  = "settings.aws.defaultInstanceProfile"
    value = module.karpenter_irsa.iam_role_name
  }

  # Add required RBAC rules
  set {
    name  = "rbac.additionalRules[0].apiGroups[0]"
    value = "admissionregistration.k8s.io"
  }
  set {
    name  = "rbac.additionalRules[0].resources[0]"
    value = "mutatingwebhookconfigurations"
  }
  set {
    name  = "rbac.additionalRules[0].resources[1]"
    value = "validatingwebhookconfigurations"
  }
  set {
    name  = "rbac.additionalRules[0].verbs[0]"
    value = "*"
  }

  set {
    name  = "rbac.additionalRules[1].apiGroups[0]"
    value = "karpenter.sh"
  }
  set {
    name  = "rbac.additionalRules[1].resources[0]"
    value = "machines"
  }
  set {
    name  = "rbac.additionalRules[1].verbs[0]"
    value = "*"
  }

  # Enable webhooks
  set {
    name  = "webhook.enabled"
    value = "true"
  }

  # Set replicas to 1 to avoid pending pods
  set {
    name  = "replicas"
    value = "1"
  }

  # Add metrics port configuration
  set {
    name  = "controller.metrics.port"
    value = "8080"
  }

  # Add health probe configuration
  set {
    name  = "controller.healthProbe.port"
    value = "8081"
  }

  depends_on = [
    module.eks,
    kubectl_manifest.karpenter_crds
  ]
}

# Add data source for AWS region
data "aws_region" "current" {}

# Karpenter Provisioner CRD
resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          requirements:
            - key: "karpenter.sh/capacity-type"
              operator: In
              values: ["spot", "on-demand"]
            - key: "kubernetes.io/arch"
              operator: In
              values: ["arm64", "amd64"]
            - key: "node.kubernetes.io/instance-type"
              operator: In
              values: [
                "c7g.large", "c7g.xlarge", "c7g.2xlarge",    # Graviton3 compute optimized
                "m7g.large", "m7g.xlarge", "m7g.2xlarge",    # Graviton3 general purpose
                "r7g.large", "r7g.xlarge", "r7g.2xlarge",    # Graviton3 memory optimized
                "c6g.large", "c6g.xlarge", "c6g.2xlarge",    # Graviton2 compute optimized
                "m6g.large", "m6g.xlarge", "m6g.2xlarge",    # Graviton2 general purpose
                "r6g.large", "r6g.xlarge", "r6g.2xlarge",    # Graviton2 memory optimized
                "c5.large", "c5.xlarge", "c5.2xlarge",       # x86 fallback options
                "m5.large", "m5.xlarge", "m5.2xlarge"        # x86 fallback options
              ]
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
      limits:
        resources:
          cpu: "1000"
          memory: 1000Gi
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 30s
  YAML

  depends_on = [
    helm_release.karpenter,
    kubectl_manifest.karpenter_crds
  ]
}

# Karpenter AWS Node Template CRD
resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiFamily: AL2
      subnetSelector:
        karpenter.sh/discovery: "${var.cluster_name}"
      securityGroupSelector:
        karpenter.sh/discovery: "${var.cluster_name}"
      tags:
        karpenter.sh/discovery: "${var.cluster_name}"
      userData: |
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary="BOUNDARY"

        --BOUNDARY
        Content-Type: text/x-shellscript; charset="us-ascii"

        #!/bin/bash
        /etc/eks/bootstrap.sh ${var.cluster_name} \
          --container-runtime containerd \
          --kubelet-extra-args '--register-with-taints=karpenter.sh/unregistered=:NoExecute'

        --BOUNDARY--
  YAML

  depends_on = [
    helm_release.karpenter,
    kubectl_manifest.karpenter_crds
  ]
}