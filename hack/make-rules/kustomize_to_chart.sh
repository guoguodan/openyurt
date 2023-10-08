#!/usr/bin/env bash

# Copyright 2023 The OpenYurt Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# exit immediately when a command fails
#set -e
# only exit with zero if all commands of the pipeline exit successfully
#set -o pipefail
# error on unset variables
#set -u

#set -x

function usage(){
    echo "$0 [Options]"
    echo -e "Options:"
    echo -e "\t-c, --crd\t crd manifest path,Only relative directories are needed."
    echo -e "\t-w, --webhook\t webhook manifest path, Only relative directories are needed."
    echo -e "\t-r, --rbac\t rbac manifest path, Only relative directories are needed."
    echo -e "\t-o, --output\t output kustomize path, Only relative directories are needed."
    echo -e "\t-t, --chartDir\t output helm chart template path, Only relative directories are needed."
    echo -e "\t-h, --help\tHelp information"
    exit 1
}

YURT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

SUFFIX="auto_generated"

Conversion_Files=("apps.openyurt.io_nodepools.yaml" "raven.openyurt.io_gateways.yaml")

while [ $# -gt 0 ];do
    case $1 in
    --crd|-c)
      shift
      CRD=$1
      shift
      ;;
    --webhook|-w)
      shift
      WEBHOOK=$1
      shift
      ;;
    --rbac|-r)
      shift
      RBAC=$1
      shift
      ;;
    --output|-o)
      shift
      OUTPUT=$1
      shift
      ;;
    --chartDir|-t)
      shift
      CHARTDIR=$1
      shift
      ;;

    --help|-h)
      shift
      usage
      ;;
    *)
      usage
      ;;
    esac
done

if [ -z $CRD ] || [ -z $WEBHOOK ] || [ -z $RBAC ] || [ -z $OUTPUT ] || [ -z $CHARTDIR ] ; then
    usage	
fi

function append_note() {
    local file=$1
    cat > ${file} << EOF
# ---------------------------------------------------
#
# Manifest generated by controller-gen. DO NOT EDIT !!!
# You can view the "make manifests" command in Makefile
#
# ---------------------------------------------------

---
EOF
}

function create_manifest() {

    local output_dir="${YURT_ROOT}/${OUTPUT}"
    local template_dir="${YURT_ROOT}/${CHARTDIR}/templates"
    local crd_dir="${YURT_ROOT}/${CHARTDIR}/crds"
    local yurt_manager_templatefile="${template_dir}/yurt-manager-auto-generated.yaml"

    if [ ! -d ${template_dir} ]; then
        echo "Template output dir ${template_dir} not exit"
        exit 1
    fi

	rm -rf $output_dir
    mkdir -p $output_dir

    local output_default_dir=$output_dir/default
    local output_crd_dir=$output_dir/crd
    local output_rbac_dir=$output_dir/rbac
    local output_webhook_dir=$output_dir/webhook

    mkdir -p ${output_default_dir} ${output_crd_dir} ${output_rbac_dir} ${output_webhook_dir} 

    # default dir
    cat > ${output_default_dir}/kustomization.yaml << EOF
# Adds namespace to all resources.
namespace: kube-system

# Value of this field is prepended to the
# names of all resources, e.g. a deployment named
# "wordpress" becomes "alices-wordpress".
# Note that it should also match with the prefix (text before '-') of the namespace
# field above.
namePrefix: yurt-manager-

# Labels to add to all resources and selectors.
#commonLabels:
#  someName: someValue

bases:
- ../rbac
- ../webhook
EOF

    # crd copy to chart crds dir
    local crd_kustomization_resources=""
    for file in ${YURT_ROOT}/${CRD}/*
    do
        if [ -f ${file} ] && [ "${file##*.}" = "yaml" ]; then 
            local f=$(basename $file)
            local newfile=${output_crd_dir}/${f}
            echo "[crd] ${f} is a yaml file, need to copy to kustomize dir"
            crd_kustomization_resources=$(echo -e "${crd_kustomization_resources}\n- ${f}")
            cp -f ${file} ${newfile}
        fi
    done

    cat > ${output_crd_dir}/kustomization.yaml << EOF
# This kustomization.yaml is not intended to be run by itself,
# since it depends on service name and namespace that are out of this kustomize package.
# It should be run by default
resources:
${crd_kustomization_resources}
# the following config is for teaching kustomize how to do kustomization for CRDs.
configurations:
- kustomizeconfig.yaml
EOF


    cat > ${output_crd_dir}/kustomizeconfig.yaml << EOF
# This file is for teaching kustomize how to substitute name and namespace reference in CRD
nameReference:
- kind: Service
  version: v1
  fieldSpecs:
  - kind: CustomResourceDefinition
    version: v1
    group: apiextensions.k8s.io
    path: spec/conversion/webhook/clientConfig/service/name

namespace:
- kind: CustomResourceDefinition
  version: v1
  group: apiextensions.k8s.io
  path: spec/conversion/webhook/clientConfig/service/namespace
  create: false

varReference:
- path: metadata/annotations
EOF

   ${YURT_ROOT}/bin/kustomize build ${output_crd_dir} -o ${crd_dir}
   # TODO currently kustomize may not support custom generate names, find more elegant way generate crds
   mv ${crd_dir}/apiextensions.k8s.io_v1_customresourcedefinition_nodepools.apps.openyurt.io.yaml ${crd_dir}/apps.openyurt.io_nodepools.yaml
   mv ${crd_dir}/apiextensions.k8s.io_v1_customresourcedefinition_yurtstaticsets.apps.openyurt.io.yaml ${crd_dir}/apps.openyurt.io_yurtstaticsets.yaml
   mv ${crd_dir}/apiextensions.k8s.io_v1_customresourcedefinition_yurtappdaemons.apps.openyurt.io.yaml ${crd_dir}/apps.openyurt.io_yurtappdaemons.yaml
   mv ${crd_dir}/apiextensions.k8s.io_v1_customresourcedefinition_yurtappsets.apps.openyurt.io.yaml ${crd_dir}/apps.openyurt.io_yurtappsets.yaml
   mv ${crd_dir}/apiextensions.k8s.io_v1_customresourcedefinition_yurtappoverriders.apps.openyurt.io.yaml ${crd_dir}/apps.openyurt.io_yurtappoverriders.yaml
   mv ${crd_dir}/apiextensions.k8s.io_v1_customresourcedefinition_gateways.raven.openyurt.io.yaml ${crd_dir}/raven.openyurt.io_gateways.yaml
   mv ${crd_dir}/apiextensions.k8s.io_v1_customresourcedefinition_platformadmins.iot.openyurt.io.yaml ${crd_dir}/iot.openyurt.io_platformadmins.yaml
   # TODO: In the future, the crd generation process of yurt-manager and yurt-iot-dock will be split. For now, manually remove it from the yurt-manager script
   # mv ${crd_dir}/apiextensions.k8s.io_v1_customresourcedefinition_devices.iot.openyurt.io.yaml ${crd_dir}/iot.openyurt.io_devices.yaml
   # mv ${crd_dir}/apiextensions.k8s.io_v1_customresourcedefinition_deviceservices.iot.openyurt.io.yaml ${crd_dir}/iot.openyurt.io_deviceservices.yaml
   # mv ${crd_dir}/apiextensions.k8s.io_v1_customresourcedefinition_deviceprofiles.iot.openyurt.io.yaml ${crd_dir}/iot.openyurt.io_deviceprofiles.yaml
   rm -f ${crd_dir}/apiextensions.k8s.io_v1_customresourcedefinition_devices.iot.openyurt.io.yaml
   rm -f ${crd_dir}/apiextensions.k8s.io_v1_customresourcedefinition_deviceservices.iot.openyurt.io.yaml
   rm -f ${crd_dir}/apiextensions.k8s.io_v1_customresourcedefinition_deviceprofiles.iot.openyurt.io.yaml

   # add conversion for crds
   for file in "${Conversion_Files[@]}"
   do
       ${YURT_ROOT}/bin/yq eval -i ".spec.conversion = {\"strategy\": \"Webhook\", \"webhook\": {\"conversionReviewVersions\": [\"v1beta1\", \"v1alpha1\"], \"clientConfig\": {\"service\": {\"namespace\": \"kube-system\", \"name\": \"yurt-manager-webhook-service\", \"path\": \"/convert\"}}}}" ${crd_dir}/$file
   done

    # rbac dir
    local rbac_kustomization_resources=""
    for file in ${YURT_ROOT}/${RBAC}/*
    do
        if [ -f ${file} ] && [ "${file##*.}" = "yaml" ]; then 
            local f=$(basename $file)
            local newfile=${output_rbac_dir}/${f}
            echo "[rbac] ${f} is a yaml file, need to copy to kustomize dir"
            rbac_kustomization_resources=$(echo -e "${rbac_kustomization_resources}\n- ${f}")
            cp -f ${file} ${newfile}
        fi
    done

    cat > ${output_rbac_dir}/kustomization.yaml << EOF
# This kustomization.yaml is not intended to be run by itself,
# since it depends on service name and namespace that are out of this kustomize package.
# It should be run by default
resources:
${rbac_kustomization_resources}
EOF


    #webhook
    local webhook_kustomization_resources=$""
    for file in ${YURT_ROOT}/${WEBHOOK}/*
    do
        if [ -f ${file} ] && [ "${file##*.}" = "yaml" ]; then 
            local f=$(basename $file)
            local newfile=${output_webhook_dir}/${f}
            echo "[rbac] ${f} is a yaml file, need to copy to kustomize dir"
            webhook_kustomization_resources=$(echo -e "${webhook_kustomization_resources}\n- ${f}")
            cp -f ${file} ${newfile}
        fi
    done

    cat > ${output_webhook_dir}/kustomization.yaml << EOF
# This kustomization.yaml is not intended to be run by itself,
# since it depends on service name and namespace that are out of this kustomize package.
# It should be run by default

resources:
${webhook_kustomization_resources}

configurations:
- kustomizeconfig.yaml
EOF

    cat > ${output_webhook_dir}/kustomizeconfig.yaml << EOF
# the following config is for teaching kustomize where to look at when substituting vars.
# It requires kustomize v2.1.0 or newer to work properly.
nameReference:
- kind: Service
  version: v1
  fieldSpecs:
  - kind: MutatingWebhookConfiguration
    group: admissionregistration.k8s.io
    path: webhooks/clientConfig/service/name
  - kind: ValidatingWebhookConfiguration
    group: admissionregistration.k8s.io
    path: webhooks/clientConfig/service/name

namespace:
- kind: MutatingWebhookConfiguration
  group: admissionregistration.k8s.io
  path: webhooks/clientConfig/service/namespace
  create: true
- kind: ValidatingWebhookConfiguration
  group: admissionregistration.k8s.io
  path: webhooks/clientConfig/service/namespace
  create: true

EOF

    append_note $yurt_manager_templatefile

    ${YURT_ROOT}/bin/kubectl kustomize ${output_default_dir} >> $yurt_manager_templatefile

    # replace webhook-service to yurt-manager-webhook-service because webhooks can not installed when service doesn't exist
    # replace kube-system in webhook to {{ include "openyurt.namespace" . }} in webhooks
    case `$echo uname` in
    "Darwin")
             sed -i '' 's/webhook-service/yurt-manager-webhook-service/g' $yurt_manager_templatefile
             sed -i '' 's/kube-system/\{\{ \.Release.Namespace \}\}/g' $yurt_manager_templatefile
             ;;
    "Linux")
             sed -i 's/webhook-service/yurt-manager-webhook-service/g' $yurt_manager_templatefile
             sed -i 's/kube-system/\{\{ \.Release.Namespace \}\}/g' $yurt_manager_templatefile
             ;;
    esac
}



create_manifest


