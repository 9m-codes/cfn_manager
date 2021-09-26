#!/bin/bash

SCRIPT_FULL_PATH=$(realpath "${0}")
SCRIPT_DIR=$(dirname "${SCRIPT_FULL_PATH}")
cd "${SCRIPT_DIR}" || exit

ENVIRONMENT_INPUT="dev"
SERVICE_INPUT="kms"
ENVIRONMENT_LOWER="$(echo ${ENVIRONMENT_INPUT} | tr '[:upper:]' '[:lower:]')"

declare -A ALLOWED_ENVS
ALLOWED_ENVS=([shared]="shared" [common]="common" [dev]="dev" [uat]="uat" [sit]="sit" [staging]="staging" [prod]="prod")

IS_ALLOWED() {
  if ! [[ "${CHECK_ENV}" == "${ALLOWED_ENVS[${CHECK_ENV}]}" ]]; then
    echo ""
    echo "Environment name ${CHECK_ENV} is not allowed. Allowed environments are:"
    echo "[ shared | common | dev | uat | sit | staging | prod ]"
    echo ""
    exit
  fi
}

CHECK_ENV="${ENVIRONMENT_LOWER}"; IS_ALLOWED
ENVIRONMENT_UPPER="$(echo ${ENVIRONMENT_INPUT} | tr '[:lower:]' '[:upper:]')"
ENVIRONMENT="$(echo ${ENVIRONMENT_INPUT} | tr '[:upper:]' '[:lower:]')"

TEMPLATES_PATH="templates/${ENVIRONMENT}/${SERVICE_INPUT}"
TAGS_PROPERTIES_PATH="tags/${ENVIRONMENT}/${SERVICE_INPUT}"
PARAMETERS_PATH="parameters/${ENVIRONMENT}/${SERVICE_INPUT}"
SCRIPTS_PATH="scripts/${ENVIRONMENT}/${SERVICE_INPUT}"
STACK_NAME_INPUT="${ENVIRONMENT}-${SERVICE_INPUT}-stack"

#---------------------------------------------------------------------------------------------------------------------
# TAGS & PARAMETERS VARIABLES
#---------------------------------------------------------------------------------------------------------------------
TAG_ENVIRONMENT_KEY="Environment"
TAG_ENVIRONMENT_VALUE="${ENVIRONMENT_UPPER}"

TAG_MANAGED_BY_KEY="ManagedBy"
TAG_MANAGED_BY_VALUE="DevOps"

TAG_STACK_NAME_KEY="StackName"
TAG_STACK_NAME_VALUE="${STACK_NAME_INPUT}"

#---------------------------------------------------------------------------------------------------------------------
# TAGS - FOR INITIAL DEPLOY
#---------------------------------------------------------------------------------------------------------------------
TAGS_COMMON_DEPLOY="$(cat << _TEXTBLOCK_
${TAG_ENVIRONMENT_KEY}=${TAG_ENVIRONMENT_VALUE}
${TAG_MANAGED_BY_KEY}=${TAG_MANAGED_BY_VALUE}
_TEXTBLOCK_
)"

TAGS_KMS_DEPLOY="$(cat << _TEXTBLOCK_
${TAG_STACK_NAME_KEY}=${TAG_STACK_NAME_VALUE}
_TEXTBLOCK_
)"

TAGS_PROPERTIES_FILE="${TAGS_PROPERTIES_PATH}/${STACK_NAME_INPUT}_tags.properties"

create_tags_template_file() {
  if ! [ -d ${TAGS_PROPERTIES_PATH} ]; then
    mkdir -p ${TAGS_PROPERTIES_PATH}
  fi

  echo "${TAGS_COMMON_DEPLOY}" > ${TAGS_PROPERTIES_FILE}
  echo "${TAGS_KMS_DEPLOY}" >> ${TAGS_PROPERTIES_FILE}
}

create_tags_template_file

#---------------------------------------------------------------------------------------------------------------------
# TAGS - FOR STACK UPDATES & CHANGESETS
#---------------------------------------------------------------------------------------------------------------------
TAGS_COMMON_UPDATES="$(cat << _TEXTBLOCK_
Key="${TAG_ENVIRONMENT_KEY}",Value="${TAG_ENVIRONMENT_VALUE}"
Key="${TAG_MANAGED_BY_KEY}",Value="${TAG_MANAGED_BY_VALUE}"
_TEXTBLOCK_
)"

TAGS_KMS_UPDATES="$(cat << _TEXTBLOCK_
Key="${TAG_STACK_NAME_KEY}",Value="${TAG_STACK_NAME_VALUE}"
_TEXTBLOCK_
)"

TAGS_PROPERTIES_FILE_UPDATES="${TAGS_PROPERTIES_PATH}/${STACK_NAME_INPUT}_tags_updates.properties"

updates_tags_template_file() {
  if ! [ -d ${TAGS_PROPERTIES_PATH} ]; then
    mkdir -p ${TAGS_PROPERTIES_PATH}
  fi

  echo -e "${TAGS_COMMON_UPDATES}" > ${TAGS_PROPERTIES_FILE_UPDATES}
  echo -e "${TAGS_KMS_UPDATES}" >> ${TAGS_PROPERTIES_FILE_UPDATES}
}

updates_tags_template_file

#---------------------------------------------------------------------------------------------------------------------
# PARAMETERS VARIABLES - SHARED KMS KEY
#---------------------------------------------------------------------------------------------------------------------

SHARED_KMS_KEY_NAME_PARAMETER_KEY="SharedKmsKeyName"
SHARED_KMS_KEY_NAME_PARAMETER_VALUE="${ENVIRONMENT}-main-kms-key"

SHARED_KMS_KEY_ALIAS_PARAMETER_KEY="SharedKmsKeyAliasName"
SHARED_KMS_KEY_ALIAS_PARAMETER_VALUE="${ENVIRONMENT}-main-kms-key"

EBS_KMS_KEY_ALIAS_PARAMETER_KEY="EbsKmsKeyAliasName"
EBS_KMS_KEY_ALIAS_PARAMETER_VALUE="${ENVIRONMENT}-ebs-kms-key"

S3_KMS_KEY_ALIAS_PARAMETER_KEY="S3KmsKeyAliasName"
S3_KMS_KEY_ALIAS_PARAMETER_VALUE="${ENVIRONMENT}-s3-kms-key"

SHARED_KMS_KEY_ADMIN_ARN_PARAMETER_KEY="SharedKmsKeyAdminArn"
SHARED_KMS_KEY_ADMIN_ARN_PARAMETER_VALUE="arn:aws:iam::888888888888:role/FullAccessRole"

SHARED_KMS_KEY_USERS_ARN_PARAMETER_KEY="SharedKmsKeyUsersArn"
SHARED_KMS_KEY_USERS_ARN_PARAMETER_VALUE="arn:aws:iam::888888888888:role/ReadOnlyAccessRole"


KMS_KEYS_PARAMETERS="$(cat << _TEXTBLOCK_
[
    {
        "ParameterKey": "${TAG_ENVIRONMENT_KEY}",
        "ParameterValue": "${TAG_ENVIRONMENT_VALUE}"
    },
    {
        "ParameterKey": "${TAG_MANAGED_BY_KEY}",
        "ParameterValue": "${TAG_MANAGED_BY_VALUE}"
    },
    {
        "ParameterKey": "${SHARED_KMS_KEY_NAME_PARAMETER_KEY}",
        "ParameterValue": "${SHARED_KMS_KEY_NAME_PARAMETER_VALUE}"
    },
    {
        "ParameterKey": "${SHARED_KMS_KEY_ALIAS_PARAMETER_KEY}",
        "ParameterValue": "${SHARED_KMS_KEY_ALIAS_PARAMETER_VALUE}"
    },
    {
        "ParameterKey": "${EBS_KMS_KEY_ALIAS_PARAMETER_KEY}",
        "ParameterValue": "${EBS_KMS_KEY_ALIAS_PARAMETER_VALUE}"
    },
    {
        "ParameterKey": "${S3_KMS_KEY_ALIAS_PARAMETER_KEY}",
        "ParameterValue": "${S3_KMS_KEY_ALIAS_PARAMETER_VALUE}"
    },
    {
        "ParameterKey": "${SHARED_KMS_KEY_ADMIN_ARN_PARAMETER_KEY}",
        "ParameterValue": "${SHARED_KMS_KEY_ADMIN_ARN_PARAMETER_VALUE}"
    },
    {
        "ParameterKey": "${SHARED_KMS_KEY_USERS_ARN_PARAMETER_KEY}",
        "ParameterValue": "${SHARED_KMS_KEY_USERS_ARN_PARAMETER_VALUE}"
    }
]
_TEXTBLOCK_
)"

PARAMETERS_FILE="${PARAMETERS_PATH}/${STACK_NAME_INPUT}_parameters.json"

create_parameters_file() {
  if ! [ -d ${PARAMETERS_PATH} ]; then
    mkdir -p ${PARAMETERS_PATH}
  fi

  echo "${KMS_KEYS_PARAMETERS}" > ${PARAMETERS_FILE}
}

create_parameters_file

#---------------------------------------------------------------------------------------------------------------------
# TOOLS & VALIDATION
#---------------------------------------------------------------------------------------------------------------------

DEFAULT_REGION="ap-southeast-2"

AWS_CLI=/usr/local/bin/aws
alias cfn="AWS_REGION=${DEFAULT_REGION} ${AWS_CLI} cloudformation"
alias list_stack="cfn list-stacks --stack-status-filter \
  CREATE_IN_PROGRESS \
  CREATE_COMPLETE \
  ROLLBACK_IN_PROGRESS  \
  ROLLBACK_FAILED  \
  ROLLBACK_COMPLETE  \
  DELETE_IN_PROGRESS  \
  DELETE_FAILED  \
  UPDATE_IN_PROGRESS  \
  UPDATE_COMPLETE_CLEANUP_IN_PROGRESS \
  UPDATE_COMPLETE \
  UPDATE_FAILED \
  UPDATE_ROLLBACK_IN_PROGRESS \
  UPDATE_ROLLBACK_FAILED \
  UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS \
  UPDATE_ROLLBACK_COMPLETE \
  REVIEW_IN_PROGRESS \
  IMPORT_IN_PROGRESS \
  IMPORT_COMPLETE \
  IMPORT_ROLLBACK_IN_PROGRESS \
  IMPORT_ROLLBACK_FAILED \
  IMPORT_ROLLBACK_COMPLETE \
  --query 'StackSummaries[*].StackName' --output text"

usage() {
  echo
  echo "USAGE:"
  echo "  ${0} {stack_name}"
  echo
}

if [ "${STACK_NAME_INPUT}" != "" ]; then
  STACK_EXIST_CHECK=$(list_stack | tr '\t' '\n' | grep -E "^${STACK_NAME_INPUT}$")
  if [ "${STACK_EXIST_CHECK}" == "${STACK_NAME_INPUT}" ]; then
    echo "Stack ${STACK_EXIST_CHECK} exists."
  else
    echo "Generating ${STACK_NAME_INPUT} files."
  fi
else
  echo "Stack name is empty."
  usage
  exit
fi

#---------------------------------------------------------------------------------------------------------------------
# STACK - CREATE EMPTY STACK
#---------------------------------------------------------------------------------------------------------------------

EMPTY_STACK="$(cat << _TEXTBLOCK_
---
AWSTemplateFormatVersion: "2010-09-09"

Conditions:
  HasNot:
    Fn::Equals: [ '${TAG_STACK_NAME_KEY}', '${TAG_STACK_NAME_VALUE}' ]

Resources:
  NullResource:
    Type: 'Custom::NullResource'
    Condition: HasNot
_TEXTBLOCK_
)"

EMPTY_STACK_FILE_YAML="${TEMPLATES_PATH}/${STACK_NAME_INPUT}_empty_stack.yaml"

create_empty_stack_file() {
  if ! [ -d ${TEMPLATES_PATH} ]; then
    mkdir -p ${TEMPLATES_PATH}
  fi

  echo "${EMPTY_STACK}" > ${EMPTY_STACK_FILE_YAML}
}

create_empty_stack_file

#---------------------------------------------------------------------------------------------------------------------
# STACK - KMS STACK TEMPLATE
#---------------------------------------------------------------------------------------------------------------------

KMS_STACK_TEMPLATE="$(cat << '_TEXTBLOCK_'
---
AWSTemplateFormatVersion: "2010-09-09"
Description: >-
  KMS Stack to deploy KMS shared keys

Parameters:
  Environment:
    Type: String
    AllowedValues:
      - shared
      - common
      - dev
      - uat
      - sit
      - staging
      - prod
      - SHARED
      - COMMON
      - DEV
      - UAT
      - SIT
      - STAGING
      - PROD
    Description: Environment variables
  ManagedBy:
    Type: String
    AllowedPattern: '^[a-zA-Z0-9/_-]+$'
    Description: Project manager
  SharedKmsKeyName:
    Type: String
    AllowedPattern: '^[a-zA-Z0-9/_-]+$'
    Description: SHARED KMS Key
  SharedKmsKeyAliasName:
    Type: String
    AllowedPattern: '^[a-zA-Z0-9/_-]+$'
    Description: SHARED KMS Key Alias
  EbsKmsKeyAliasName:
    Type: String
    AllowedPattern: '^[a-zA-Z0-9/_-]+$'
    Description: SHARED EBS KMS Key Alias
  S3KmsKeyAliasName:
    Type: String
    AllowedPattern: '^[a-zA-Z0-9/_-]+$'
    Description: SHARED S3 KMS Key Alias
  SharedKmsKeyAdminArn:
    Type: String
    AllowedPattern: '^[a-zA-Z0-9/:_-]+$'
    Description: SHARED KMS Key Admin ARN
  SharedKmsKeyUsersArn:
    Type: String
    AllowedPattern: '^[a-zA-Z0-9/:_-]+$'
    Description: SHARED KMS Key Users ARN

Resources:
  sharedKmsKey:
    Type: AWS::KMS::Key
    DeletionPolicy: Delete
    UpdateReplacePolicy: Retain
    Properties:
      Description: SHARED KMS key
      EnableKeyRotation: true
      PendingWindowInDays: 7
      KeyPolicy:
        Version: '2012-10-17'
        Id: shared-kms-key-id
        Statement:
        - Sid: Enable IAM User Permissions
          Effect: Allow
          Principal:
            AWS: !Sub 'arn:aws:iam::${AWS::AccountId}:root'
          Action: kms:*
          Resource: '*'
        - Sid: Allow administration of the key
          Effect: Allow
          Principal:
            AWS: !Sub '${SharedKmsKeyAdminArn}'
          Action:
          - kms:Create*
          - kms:Describe*
          - kms:Enable*
          - kms:List*
          - kms:Put*
          - kms:Update*
          - kms:Revoke*
          - kms:Disable*
          - kms:Get*
          - kms:Delete*
          - kms:ScheduleKeyDeletion
          - kms:CancelKeyDeletion
          Resource: '*'
        - Sid: Allow use of the key
          Effect: Allow
          Principal:
            AWS: !Sub '${SharedKmsKeyUsersArn}'
          Action:
          - kms:DescribeKey
          - kms:Encrypt
          - kms:Decrypt
          - kms:ReEncrypt*
          - kms:GenerateDataKey
          - kms:GenerateDataKeyWithoutPlaintext
          Resource: '*'
      Tags:
        - Key: "Environment"
          Value: !Sub "${Environment}"
        - Key: "ManagedBy"
          Value: !Sub "${ManagedBy}"
        - Key: "StackName"
          Value: !Sub "${AWS::StackName}"

  sharedKmsKeyAlias:
    DeletionPolicy: Delete
    UpdateReplacePolicy: Retain
    Type: 'AWS::KMS::Alias'
    Properties:
      AliasName: !Sub 'alias/${SharedKmsKeyAliasName}'
      TargetKeyId: !Ref sharedKmsKey
  ebsKmsKeyAlias:
    DeletionPolicy: Delete
    UpdateReplacePolicy: Retain
    Type: 'AWS::KMS::Alias'
    Properties:
      AliasName: !Sub 'alias/${EbsKmsKeyAliasName}'
      TargetKeyId: !Ref sharedKmsKey
  s3KmsKeyAlias:
    DeletionPolicy: Delete
    UpdateReplacePolicy: Retain
    Type: 'AWS::KMS::Alias'
    Properties:
      AliasName: !Sub 'alias/${S3KmsKeyAliasName}'
      TargetKeyId: !Ref sharedKmsKey

Outputs:
  StackName:
    Description: 'Bootrap KMS Key stack name'
    Value: !Sub '${AWS::StackName}'
  sharedKmsKeyId:
    Description: 'SHARED KMS Key id'
    Value: !Ref sharedKmsKey
    Export:
      Name: !Sub '${AWS::StackName}-SharedKeyId'
  sharedKmsKeyArn:
    Description: 'SHARED KMS Key ARN'
    Value: !GetAtt 'sharedKmsKey.Arn'
    Export:
      Name: !Sub '${AWS::StackName}-SharedArn'
  ebsKmsKeyArn:
    Description: 'EBS KMS Key ARN'
    Value: !GetAtt 'sharedKmsKey.Arn'
    Export:
      Name: !Sub '${AWS::StackName}-EbsKeyArn'
  s3KmsKeyArn:
    Description: 'S3 KMS Key ARN'
    Value: !GetAtt 'sharedKmsKey.Arn'
    Export:
      Name: !Sub '${AWS::StackName}-S3KeyArn'
_TEXTBLOCK_
)"

KMS_TEMPLATES_FILE="${TEMPLATES_PATH}/${STACK_NAME_INPUT}.yaml"

create_templates_file() {
  if ! [ -d ${TEMPLATES_PATH} ]; then
    mkdir -p ${TEMPLATES_PATH}
  fi

  echo "${KMS_STACK_TEMPLATE}" > ${KMS_TEMPLATES_FILE}
}

create_templates_file


#---------------------------------------------------------------------------------------------------------------------
# STACK - CHANGESET CREATION SCRIPT
#---------------------------------------------------------------------------------------------------------------------
CHANGESET_PREFIX=${STACK_NAME_INPUT}-changeset

CHANGESET_CREATE_SCRIPT="${SCRIPTS_PATH}/${STACK_NAME_INPUT}_changeset_create.sh"
CHANGESET_SHOW_CHANGES_SCRIPT="${SCRIPTS_PATH}/${STACK_NAME_INPUT}_changeset_show_changes.sh"

STACK_CREATE_CHANGESET="$(cat << _TEXTBLOCK_ | sed 's/|BACKSLASH|/\\/g'
#!/bin/bash

DATETIME="\$(date +%Y%m%d%H%M%S)"
CHANGESET_NAME="${CHANGESET_PREFIX}-\${DATETIME}"

AWS_REGION=${DEFAULT_REGION} aws cloudformation create-change-set |BACKSLASH|
  --stack-name ${STACK_NAME_INPUT} |BACKSLASH|
  --template-body file://${KMS_TEMPLATES_FILE} |BACKSLASH|
  --parameters file://${PARAMETERS_FILE} |BACKSLASH|
  --change-set-name \${CHANGESET_NAME} |BACKSLASH|
  --tags \$(cat ${TAGS_PROPERTIES_FILE_UPDATES})

_TEXTBLOCK_
)"

#---------------------------------------------------------------------------------------------------------------------
# STACK - CHANGESET SHOW CHANGES SCRIPT
#--------------------------------------------------------------------------------------------------------------------

CHANGESET_SHOW_CHANGES="$(cat << _TEXTBLOCK_ | sed 's/|BACKSLASH|/\\/g'
#!/bin/bash

CHANGESETS="\$(AWS_REGION=ap-southeast-2 aws cloudformation list-change-sets --stack-name ${STACK_NAME_INPUT} --query 'Summaries[?Status==\`CREATE_COMPLETE\`].ChangeSetName' --output text)"
LATEST_CHANGESET="\$(echo \${CHANGESETS} | tr ' ' '\n' | sort -Vr | head -1)"

if [ "\${LATEST_CHANGESET}" != "" ]; then
  SHOW_CHANGES=\$(AWS_REGION=ap-southeast-2 aws cloudformation describe-change-set --stack-name ${STACK_NAME_INPUT} --change-set-name \${LATEST_CHANGESET})
  echo "\${SHOW_CHANGES}" | jq '.'
fi

_TEXTBLOCK_
)"


create_changeset_create_file() {
  if ! [ -d ${SCRIPTS_PATH} ]; then
    mkdir -p ${SCRIPTS_PATH}
  fi

  echo "${STACK_CREATE_CHANGESET}" > ${CHANGESET_CREATE_SCRIPT}
  echo "${CHANGESET_SHOW_CHANGES}" > ${CHANGESET_SHOW_CHANGES_SCRIPT}
}

create_changeset_create_file

#---------------------------------------------------------------------------------------------------------------------
# STACK - CHANGESET FAILED CLEAN UP SCRIPT
#--------------------------------------------------------------------------------------------------------------------

STACK_CHANGESET_CLEANUP="$(cat << _TEXTBLOCK_ | sed 's/|BACKSLASH|/\\/g'
#!/bin/bash

FAILED_CHANGESETS="\$(AWS_REGION=${DEFAULT_REGION} aws cloudformation list-change-sets --stack-name ${STACK_NAME_INPUT} --query 'Summaries[?Status==\`FAILED\`].ChangeSetName' --output text)"

if [ "\${FAILED_CHANGESETS}" != "" ]; then
  for fcs in \${FAILED_CHANGESETS}; do
    echo "Removing: \${fcs}"
    AWS_REGION=${DEFAULT_REGION} aws cloudformation delete-change-set --change-set-name \${fcs} --stack-name ${STACK_NAME_INPUT}
  done
else
  echo "No FAILED change set found."
fi
_TEXTBLOCK_
)"

CHANGESET_CLEAN_UP_SCRIPT="${SCRIPTS_PATH}/${STACK_NAME_INPUT}_changeset_clean_up.sh"

create_changeset_cleanup_script_file() {
  if ! [ -d ${SCRIPTS_PATH} ]; then
    mkdir -p ${SCRIPTS_PATH}
  fi

  echo -E "${STACK_CHANGESET_CLEANUP}" > ${CHANGESET_CLEAN_UP_SCRIPT}
}

create_changeset_cleanup_script_file

#---------------------------------------------------------------------------------------------------------------------
# STACK - DEPLOY EMPTY STACK SCRIPT
#--------------------------------------------------------------------------------------------------------------------

DEPLOY_EMPTY_STACK_SCRIPT="$(cat << _TEXTBLOCK_ | sed 's/|BACKSLASH|/\\/g'
#!/bin/bash

STACK_NAME="${STACK_NAME_INPUT}"
EMPTY_STACK_FILE="${EMPTY_STACK_FILE_YAML}"
TAGS_PROPERTIES="${TAGS_PROPERTIES_FILE}"

DEFAULT_REGION=ap-southeast-2
AWS_CLI=/usr/local/bin/aws
alias cfn="AWS_REGION=\${DEFAULT_REGION} \${AWS_CLI} cloudformation"
alias list_stack="cfn list-stacks --stack-status-filter |BACKSLASH|
  CREATE_IN_PROGRESS |BACKSLASH|
  CREATE_COMPLETE |BACKSLASH|
  ROLLBACK_IN_PROGRESS  |BACKSLASH|
  ROLLBACK_FAILED  |BACKSLASH|
  ROLLBACK_COMPLETE  |BACKSLASH|
  DELETE_IN_PROGRESS  |BACKSLASH|
  DELETE_FAILED  |BACKSLASH|
  UPDATE_IN_PROGRESS  |BACKSLASH|
  UPDATE_COMPLETE_CLEANUP_IN_PROGRESS |BACKSLASH|
  UPDATE_COMPLETE |BACKSLASH|
  UPDATE_FAILED |BACKSLASH|
  UPDATE_ROLLBACK_IN_PROGRESS |BACKSLASH|
  UPDATE_ROLLBACK_FAILED |BACKSLASH|
  UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS |BACKSLASH|
  UPDATE_ROLLBACK_COMPLETE |BACKSLASH|
  REVIEW_IN_PROGRESS |BACKSLASH|
  IMPORT_IN_PROGRESS |BACKSLASH|
  IMPORT_COMPLETE |BACKSLASH|
  IMPORT_ROLLBACK_IN_PROGRESS |BACKSLASH|
  IMPORT_ROLLBACK_FAILED |BACKSLASH|
  IMPORT_ROLLBACK_COMPLETE |BACKSLASH|
  --query 'StackSummaries[*].StackName' --output text"

if [ "\${STACK_NAME}" != "" ]; then
  STACK_EXIST_CHECK=\$(list_stack | tr '\t' '\n' | grep -E "^\${STACK_NAME}\$")
else
  echo "Stack name is empty."
  exit
fi


if [ "\${STACK_EXIST_CHECK}" != "\${STACK_NAME}" ]; then
  AWS_REGION=\${DEFAULT_REGION} aws cloudformation deploy --stack-name "\${STACK_NAME}" --template-file \${EMPTY_STACK_FILE} --tags \$(cat \${TAGS_PROPERTIES})
else
  echo "\${STACK_NAME} already exists."
  exit
fi
_TEXTBLOCK_
)"


DEPLOY_EMPTY_STACK_FILE="${SCRIPTS_PATH}/${STACK_NAME_INPUT}_empty_stack_deploy.sh"

create_empty_stack_deploy_script_file() {
  if ! [ -d ${SCRIPTS_PATH} ]; then
    mkdir -p ${SCRIPTS_PATH}
  fi

  echo "${DEPLOY_EMPTY_STACK_SCRIPT}" > ${DEPLOY_EMPTY_STACK_FILE}
}

create_empty_stack_deploy_script_file

#---------------------------------------------------------------------------------------------------------------------
# STACK - CHANGESET DEPLOY SCRIPT
#--------------------------------------------------------------------------------------------------------------------

DEPLOY_CHANGESET_SCRIPT="$(cat << _TEXTBLOCK_ | sed 's/|BACKSLASH|/\\/g'
#!/bin/bash

STACK_NAME="${STACK_NAME_INPUT}"
DEFAULT_REGION="ap-southeast-2"

CHANGESETS="\$(AWS_REGION=\${DEFAULT_REGION} aws cloudformation list-change-sets --stack-name \${STACK_NAME} --query 'Summaries[?Status==\`CREATE_COMPLETE\`].ChangeSetName' --output text)"
LATEST_CHANGESET="\$(echo \${CHANGESETS} | tr ' ' '\n' | sort -Vr | head -1)"

if [ "\${LATEST_CHANGESET}" != "" ]; then
  AWS_REGION=\${DEFAULT_REGION} aws cloudformation execute-change-set --change-set-name \${LATEST_CHANGESET} --stack-name \${STACK_NAME}
else
  echo "No change set found."
fi
_TEXTBLOCK_
)"

DEPLOY_CHANGESET_SCRIPT_FILE="${SCRIPTS_PATH}/${STACK_NAME_INPUT}_changeset_deploy.sh"

create_changeset_deploy_script_file() {
  if ! [ -d ${SCRIPTS_PATH} ]; then
    mkdir -p ${SCRIPTS_PATH}
  fi

  echo "${DEPLOY_CHANGESET_SCRIPT}" > ${DEPLOY_CHANGESET_SCRIPT_FILE}
}

create_changeset_deploy_script_file