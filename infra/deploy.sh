#!/usr/bin/env bash

# 通常実行（ローカルstateは移行せず、Object Storage準備失敗時はローカルstateを使用）: ./infra/deploy.sh [terraform applyのオプション]
# ローカルstateをS3へ移行して実行: ./infra/deploy.sh --force-state-migration [terraform applyのオプション]
# --force-state-migrationはS3上の既存stateを上書きする可能性があるため、state移行時だけ使用します。

set -euo pipefail

infra_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tfstate_dir="${infra_dir}/tfstate"
terraform_dir="${infra_dir}/terraform"
credentials_file="${terraform_dir}/s3.credentials"
tfvars_file="${terraform_dir}/secret.auto.tfvars"
backend_file="${tfstate_dir}/backend.tf"
disabled_backend_file="${tfstate_dir}/backend.tf.bootstrap"
main_backend_file="${terraform_dir}/backend.tf"
disabled_main_backend_file="${terraform_dir}/backend.tf.local"
bucket_resource="sakura_object_storage_bucket.tfstate"
bucket_import_id="tky01/sakuraevl-terraform-state"
bootstrap_data_dir=""
main_data_dir=""
created_backend=false
bucket_created=false
force_state_migration=false
terraform_apply_args=()
forced_state_migration_args=(-migrate-state -force-copy)

for arg in "$@"; do
  if [[ "${arg}" == "--force-state-migration" ]]; then
    force_state_migration=true
  else
    terraform_apply_args+=("${arg}")
  fi
done

restore_backend() {
  if [[ -f "${disabled_backend_file}" ]]; then
    mv "${disabled_backend_file}" "${backend_file}"
  fi
}

restore_main_backend() {
  if [[ -f "${disabled_main_backend_file}" ]]; then
    mv "${disabled_main_backend_file}" "${main_backend_file}"
  fi
}

cleanup() {
  restore_backend
  restore_main_backend

  if [[ -n "${bootstrap_data_dir}" && -d "${bootstrap_data_dir}" ]]; then
    rm -rf -- "${bootstrap_data_dir}"
  fi

  if [[ -n "${main_data_dir}" && -d "${main_data_dir}" ]]; then
    rm -rf -- "${main_data_dir}"
  fi
}

run_bootstrap_terraform() {
  local data_dir="$1"
  shift

  if [[ -n "${data_dir}" ]]; then
    TF_DATA_DIR="${data_dir}" terraform -chdir="${tfstate_dir}" "$@"
  else
    terraform -chdir="${tfstate_dir}" "$@"
  fi
}

repair_provider_permissions() {
  local data_dir="$1"

  if [[ -d "${data_dir}/providers" ]]; then
    find "${data_dir}/providers" -type f -name 'terraform-provider-*' -exec chmod u+x {} +
  fi
}

import_bucket_if_unmanaged() {
  local data_dir="$1"
  local state_resources

  if ! state_resources="$(run_bootstrap_terraform "${data_dir}" state list 2>&1)"; then
    if grep -Fq "No state file was found" <<<"${state_resources}"; then
      state_resources=""
    else
      echo "${state_resources}" >&2
      echo "Failed to read Terraform state. Refusing to import or create the bucket." >&2
      return 1
    fi
  fi

  if grep -Fxq "${bucket_resource}" <<<"${state_resources}"; then
    return
  fi

  echo "Bucket is not in Terraform state. Trying to import: ${bucket_import_id}"
  if run_bootstrap_terraform "${data_dir}" import \
    -input=false \
    -var-file="${tfvars_file}" \
    "${bucket_resource}" \
    "${bucket_import_id}"; then
    echo "Imported existing bucket into Terraform state."
  else
    echo "Existing bucket was not imported. Terraform will try to create it."
    bucket_created=true
  fi
}

bootstrap_apply() {
  local data_dir="$1"

  import_bucket_if_unmanaged "${data_dir}" || return 1
  run_bootstrap_terraform "${data_dir}" apply -compact-warnings -var-file="${tfvars_file}" || return 1
}

write_credentials() {
  local data_dir="${1:-}"
  local access_key
  local secret_key

  if [[ -n "${data_dir}" ]]; then
    access_key="$(TF_DATA_DIR="${data_dir}" terraform -chdir="${tfstate_dir}" output -raw access_key)" || return 1
    secret_key="$(TF_DATA_DIR="${data_dir}" terraform -chdir="${tfstate_dir}" output -raw secret_key)" || return 1
  else
    access_key="$(terraform -chdir="${tfstate_dir}" output -raw access_key)" || return 1
    secret_key="$(terraform -chdir="${tfstate_dir}" output -raw secret_key)" || return 1
  fi

  umask 077
  printf '[default]\naws_access_key_id = "%s"\naws_secret_access_key = "%s"\n' "${access_key}" "${secret_key}" >"${credentials_file}" || return 1
}

setup_remote_state() {
  if terraform -chdir="${tfstate_dir}" init -reconfigure; then
    bootstrap_apply "" || return 1
    write_credentials || return 1
    return
  fi

  mv "${backend_file}" "${disabled_backend_file}" || return 1
  bootstrap_data_dir="$(mktemp -d)" || return 1

  TF_DATA_DIR="${bootstrap_data_dir}" terraform -chdir="${tfstate_dir}" init || return 1
  bootstrap_apply "${bootstrap_data_dir}" || return 1
  write_credentials "${bootstrap_data_dir}" || return 1
  restore_backend

  if [[ "${bucket_created}" == "true" || "${force_state_migration}" == "true" ]]; then
    TF_DATA_DIR="${bootstrap_data_dir}" terraform -chdir="${tfstate_dir}" init "${forced_state_migration_args[@]}" || return 1
  else
    TF_DATA_DIR="${bootstrap_data_dir}" terraform -chdir="${tfstate_dir}" init -migrate-state || return 1
  fi

  terraform -chdir="${tfstate_dir}" init -reconfigure || return 1
  created_backend=true
}

initialize_remote_main_state() {
  if [[ "${force_state_migration}" == "true" ]]; then
    if [[ "${created_backend}" == "true" ]]; then
      main_data_dir="$(mktemp -d)"
      TF_DATA_DIR="${main_data_dir}" terraform -chdir="${terraform_dir}" init "${forced_state_migration_args[@]}"
      terraform -chdir="${terraform_dir}" init -reconfigure
    else
      terraform -chdir="${terraform_dir}" init "${forced_state_migration_args[@]}"
    fi
  else
    terraform -chdir="${terraform_dir}" init -reconfigure
  fi
}

apply_with_local_state() {
  restore_backend
  restore_main_backend
  mv "${main_backend_file}" "${disabled_main_backend_file}"
  main_data_dir="$(mktemp -d)"

  TF_DATA_DIR="${main_data_dir}" terraform -chdir="${terraform_dir}" init
  TF_DATA_DIR="${main_data_dir}" terraform -chdir="${terraform_dir}" apply "${terraform_apply_args[@]}"
}

restore_backend
trap cleanup EXIT INT TERM

if [[ ! -f "${tfvars_file}" ]]; then
  echo "Missing: ${tfvars_file}" >&2
  echo "Copy secret.auto.tfvars.example and set the Sakura API credentials." >&2
  exit 1
fi

if [[ "${force_state_migration}" == "true" && ! -f "${terraform_dir}/terraform.tfstate" ]]; then
  echo "Missing local state to migrate: ${terraform_dir}/terraform.tfstate" >&2
  exit 1
fi

export AWS_SHARED_CREDENTIALS_FILE="${credentials_file}"
export AWS_EC2_METADATA_DISABLED=true

repair_provider_permissions "${tfstate_dir}/.terraform"
repair_provider_permissions "${terraform_dir}/.terraform"

if setup_remote_state; then
  initialize_remote_main_state
  terraform -chdir="${terraform_dir}" apply "${terraform_apply_args[@]}"
else
  echo "Object Storage setup failed. Continuing with local Terraform state." >&2
  apply_with_local_state
fi
