#!/usr/bin/env bash

# 通常実行（バケット名と新規作成・既存再利用を対話選択）: ./infra/deploy.sh [terraform applyのオプション]
# バケット名をオプション指定: ./infra/deploy.sh --tfstate-bucket-name 一意なバケット名
# 既存バケットを明示的にimport: ./infra/deploy.sh --tfstate-bucket-name 一意なバケット名 --import-existing-state-bucket
# ローカルstateをS3へ移行: ./infra/deploy.sh --tfstate-bucket-name 一意なバケット名 --force-state-migration
# --force-state-migrationはS3上の既存stateを上書きする可能性があるため、state移行時だけ使用します。
# Object Storage準備失敗時はローカルstateを使用します。

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
object_storage_site="tky01"
tfstate_bucket_name="${TFSTATE_BUCKET_NAME:-}"
bucket_name_was_prompted=false
ssh_private_key_path="${SSH_PRIVATE_KEY_PATH:-${HOME}/.ssh/sakuravel_ed25519}"
ssh_public_key_path="${ssh_private_key_path}.pub"
terraform_main_var_args=("-var=server_ssh_public_key_path=${ssh_public_key_path}")
bucket_resource="sakura_object_storage_bucket.tfstate"
bucket_import_id=""
bootstrap_data_dir=""
main_data_dir=""
created_backend=false
bucket_created=false
force_state_migration=false
import_existing_state_bucket=false
terraform_apply_args=()
forced_state_migration_args=(-migrate-state -force-copy)

while (($# > 0)); do
  case "$1" in
    --tfstate-bucket-name)
      if (($# < 2)) || [[ -z "$2" ]]; then
        echo "--tfstate-bucket-name requires a bucket name." >&2
        exit 1
      fi
      tfstate_bucket_name="$2"
      shift 2
      ;;
    --tfstate-bucket-name=*)
      tfstate_bucket_name="${1#*=}"
      if [[ -z "${tfstate_bucket_name}" ]]; then
        echo "--tfstate-bucket-name requires a bucket name." >&2
        exit 1
      fi
      shift
      ;;
    --force-state-migration)
      force_state_migration=true
      shift
      ;;
    --import-existing-state-bucket)
      import_existing_state_bucket=true
      shift
      ;;
    --)
      shift
      terraform_apply_args+=("$@")
      break
      ;;
    *)
      terraform_apply_args+=("$1")
      shift
      ;;
  esac
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

prepare_ssh_key() {
  local key_dir

  if [[ -f "${ssh_private_key_path}" && -f "${ssh_public_key_path}" ]]; then
    return
  fi

  if [[ -e "${ssh_private_key_path}" || -e "${ssh_public_key_path}" ]]; then
    echo "Incomplete SSH key pair." >&2
    echo "Both files must exist or both must be absent:" >&2
    echo "  ${ssh_private_key_path}" >&2
    echo "  ${ssh_public_key_path}" >&2
    return 1
  fi

  if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "ssh-keygen is required to create the SSH key pair." >&2
    return 1
  fi

  key_dir="$(dirname "${ssh_private_key_path}")"
  mkdir -p "${key_dir}"
  chmod 700 "${key_dir}"

  echo "Generating SSH key pair: ${ssh_private_key_path}"
  ssh-keygen -q -t ed25519 -N "" -f "${ssh_private_key_path}"
  chmod 600 "${ssh_private_key_path}"
  chmod 644 "${ssh_public_key_path}"
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

run_backend_init() {
  local root_dir="$1"
  local data_dir="$2"
  shift 2

  if [[ -n "${data_dir}" ]]; then
    TF_DATA_DIR="${data_dir}" terraform -chdir="${root_dir}" init "$@" \
      -backend-config="bucket=${tfstate_bucket_name}"
  else
    terraform -chdir="${root_dir}" init "$@" \
      -backend-config="bucket=${tfstate_bucket_name}"
  fi
}

repair_provider_permissions() {
  local data_dir="$1"

  if [[ -d "${data_dir}/providers" ]]; then
    find "${data_dir}/providers" -type f -name 'terraform-provider-*' -exec chmod u+x {} +
  fi
}

prepare_bucket_state() {
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

  if [[ "${import_existing_state_bucket}" != "true" ]]; then
    echo "Bucket is not in Terraform state. Terraform will create: ${tfstate_bucket_name}"
    bucket_created=true
    return
  fi

  echo "Importing the explicitly selected existing bucket: ${bucket_import_id}"
  if run_bootstrap_terraform "${data_dir}" import \
    -input=false \
    -var-file="${tfvars_file}" \
    "${bucket_resource}" \
    "${bucket_import_id}"; then
    echo "Imported existing bucket into Terraform state."
    return
  fi

  echo "Failed to import the existing bucket. Refusing to create a replacement implicitly." >&2
  return 1
}

bootstrap_apply() {
  local data_dir="$1"

  prepare_bucket_state "${data_dir}" || return 1
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
  printf '[default]\naws_access_key_id = %s\naws_secret_access_key = %s\n' "${access_key}" "${secret_key}" >"${credentials_file}" || return 1
}

setup_remote_state() {
  if run_backend_init "${tfstate_dir}" "" -reconfigure; then
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
    run_backend_init "${tfstate_dir}" "${bootstrap_data_dir}" "${forced_state_migration_args[@]}" || return 1
  else
    run_backend_init "${tfstate_dir}" "${bootstrap_data_dir}" -migrate-state || return 1
  fi

  run_backend_init "${tfstate_dir}" "" -reconfigure || return 1
  created_backend=true
}

initialize_remote_main_state() {
  if [[ "${force_state_migration}" == "true" ]]; then
    if [[ "${created_backend}" == "true" ]]; then
      main_data_dir="$(mktemp -d)"
      run_backend_init "${terraform_dir}" "${main_data_dir}" "${forced_state_migration_args[@]}"
      run_backend_init "${terraform_dir}" "" -reconfigure
    else
      run_backend_init "${terraform_dir}" "" "${forced_state_migration_args[@]}"
    fi
  else
    run_backend_init "${terraform_dir}" "" -reconfigure
  fi
}

apply_with_local_state() {
  restore_backend
  restore_main_backend
  mv "${main_backend_file}" "${disabled_main_backend_file}"
  main_data_dir="$(mktemp -d)"

  TF_DATA_DIR="${main_data_dir}" terraform -chdir="${terraform_dir}" init
  TF_DATA_DIR="${main_data_dir}" terraform -chdir="${terraform_dir}" apply \
    "${terraform_main_var_args[@]}" "${terraform_apply_args[@]}"
}

restore_backend
trap cleanup EXIT INT TERM

if [[ -z "${tfstate_bucket_name}" ]]; then
  if [[ -t 0 ]]; then
    printf 'Terraform state bucket name: '
    if ! IFS= read -r tfstate_bucket_name; then
      echo "Failed to read Terraform state bucket name." >&2
      exit 1
    fi
    bucket_name_was_prompted=true
  else
    echo "Missing Terraform state bucket name." >&2
    echo "Use --tfstate-bucket-name NAME or set TFSTATE_BUCKET_NAME." >&2
    exit 1
  fi
fi

if [[ -z "${tfstate_bucket_name}" ]]; then
  echo "Terraform state bucket name must not be empty." >&2
  exit 1
fi

if [[ ${#tfstate_bucket_name} -lt 3 || ${#tfstate_bucket_name} -gt 63 ||
      ! "${tfstate_bucket_name}" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ||
      "${tfstate_bucket_name}" == *".."* || "${tfstate_bucket_name}" == *".-"* ||
      "${tfstate_bucket_name}" == *"-."* ]]; then
  echo "Invalid Terraform state bucket name: use 3-63 lowercase letters, digits, dots, or hyphens." >&2
  exit 1
fi

if [[ "${bucket_name_was_prompted}" == "true" &&
      "${import_existing_state_bucket}" != "true" ]]; then
  printf '%s\n' 'Bucket handling:'
  printf '%s\n' '  1) Create a new bucket'
  printf '%s\n' '  2) Import and reuse an existing bucket'
  printf 'Select [1/2]: '
  if ! IFS= read -r bucket_handling_choice; then
    echo "Failed to read bucket handling choice." >&2
    exit 1
  fi

  case "${bucket_handling_choice}" in
    1)
      ;;
    2)
      import_existing_state_bucket=true
      ;;
    *)
      echo "Invalid choice: enter 1 or 2." >&2
      exit 1
      ;;
  esac
fi

bucket_import_id="${object_storage_site}/${tfstate_bucket_name}"
export TF_VAR_tfstate_bucket_name="${tfstate_bucket_name}"

if [[ ! -f "${tfvars_file}" ]]; then
  echo "Missing: ${tfvars_file}" >&2
  echo "Copy secret.auto.tfvars.example and set the Sakura API credentials." >&2
  exit 1
fi

prepare_ssh_key

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
  terraform -chdir="${terraform_dir}" apply \
    "${terraform_main_var_args[@]}" "${terraform_apply_args[@]}"
else
  if [[ "${import_existing_state_bucket}" == "true" ]]; then
    echo "Existing state bucket setup failed. Refusing to use local Terraform state." >&2
    exit 1
  fi

  echo "Object Storage setup failed. Continuing with local Terraform state." >&2
  apply_with_local_state
fi
