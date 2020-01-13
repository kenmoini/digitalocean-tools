#!/bin/bash

## set -x ## uncomment for debugging

export DO_PAT=${DO_PAT:=""}

PARAMS=""
domain=""
returned_record_id=""
ip_addr=""
record_name=""
record_type="A"
force_overwrite='false'

function print_help() {
  echo -e "\n=== Configure and set DNS on DigitalOcean via the API.\n"
  echo -e "=== Usage:\n\nexport DO_PAT=\"<your_digital_ocean_personal_access_token_here>\" # do this once\n"
  echo -e "./config_dns.sh [ -d|--domain 'example.com' ] [ -i|--ip '12.12.12.12' ] [ -r|--record 'k8s' ] [ -t|--type 'A' ] [ -f|--force ]"
  echo -e "\n=== -t defaults to 'A', all other parameters except -f|--force are required.\n"
  exit
}

if [[ "$#" -gt 0 ]]; then
  while (( "$#" )); do
    case "$1" in
      -f|--force)
        force_overwrite="true"
        shift
        ;;
      -d|--domain)
        domain="$2"
        shift 2
        ;;
      -i|--ip)
        ip_addr="$2"
        shift 2
        ;;
      -t|--type)
        record_type="$2"
        shift 2
        ;;
      -r|--record)
        record_name="$2"
        shift 2
        ;;
      -h|--help)
        print_help
        shift
        ;;
      -*|--*=) # unsupported flags
        echo "Error: Unsupported flag $1" >&2
        print_help
        ;;
      *) # preserve positional arguments
        PARAMS="$PARAMS $1"
        shift
        ;;
    esac
  done
else
  echo -e "\n=== MISSING PARAMETERS!!!"
  print_help
fi

# set positional arguments in their proper place
eval set -- "$PARAMS"

if [ -z "$domain" ]; then
  echo "Domain is required!".
  exit 1
else
  echo "Domain - check..."
fi

if [ -z "$ip_addr" ]; then
  echo "IP Address is required!".
  exit 1
else
  echo "IP Address - check..."
fi

if [ -z "$record_name" ]; then
  echo "Record Name is required!".
  exit 1
else
  echo "Record Name - check..."
fi

function checkForProgram() {
    command -v $1
    if [[ $? -eq 0 ]]; then
        printf '%-72s %-7s\n' $1 "PASSED!";
    else
        printf '%-72s %-7s\n' $1 "FAILED!";
        exit 1
    fi
}

echo -e "\nChecking prerequisites...\n"
checkForProgram curl
checkForProgram jq

## check for the DNS zone
function checkDomain() {
  request=$(curl -sS -X GET -H "Content-Type: application/json" -H "Authorization: Bearer ${DO_PAT}" "https://api.digitalocean.com/v2/domains/$domain")
  if [ "$request" != "null" ]; then
    filter=$(echo $request | jq '.domain')
    if [ "$filter" != "null" ]; then
      echo -e "\nDomain [${domain}] DNS Zone exists...\n"
      return 0
    else
      echo "Domain [${domain}] DNS Zone does not exist!"
      return 1
    fi
  else
    echo "Domain [${domain}] DNS Zone does not exist!"
    return 1
  fi
}

## check to see if a record exists
function checkRecord() {
  request=$(curl -sS -X GET -H "Content-Type: application/json" -H "Authorization: Bearer ${DO_PAT}" "https://api.digitalocean.com/v2/domains/${domain}/records")
  filter=$(echo $request | jq '.domain_records[] | select((.name | contains("'"${record_name}"'")) and (.type == "'"${record_type}"'"))')
  FILTER_NO_EXTERNAL_SPACE="$(echo -e "${filter}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d '\n')"
  if [ -z "$FILTER_NO_EXTERNAL_SPACE" ]; then
    echo -e "Record [A - ${record_name}.${domain}.] does not exist!\n"
    return 1
  else
    IP_FILTER="$(echo "${FILTER_NO_EXTERNAL_SPACE}" | jq '.data')"
    returned_record_id="$(echo "${FILTER_NO_EXTERNAL_SPACE}" | jq '.id')"
    echo -e "Record [A - ${record_name}.${domain}.] exists at ${IP_FILTER}...\n"
    return 0
  fi
}

function deleteRecord() {
  request=$(curl -sS -X DELETE -H "Content-Type: application/json" -H "Authorization: Bearer ${DO_PAT}" "https://api.digitalocean.com/v2/domains/${1}/records/${2}")
  echo $request
}

## write a DNS record for the supplied arguments (domain, ip, type, record)
function writeDNS() {
  request=$(curl -sS -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${DO_PAT}" -d '{"type":"'"${record_type}"'","name":"'"${record_name}"'","data":"'"${ip_addr}"'","priority":null,"port":null,"ttl":600,"weight":null,"flags":null,"tag":null}' "https://api.digitalocean.com/v2/domains/${domain}/records")
  echo $request
}

checkDomain $domain

if [ $? -eq 0 ]; then
  checkRecord $domain "@"
  if [ $? -eq 0 ]; then
    if [ "$force_overwrite" == "true" ]; then
      echo -e "Record exists at ID(s):\n ${returned_record_id}\n\nCommand run with -f, overwriting records now...\n"
      for recid in $returned_record_id; do
        deleteRecord $domain $recid
      done
      writeDNS $domain
    else
      echo -e "Record exists at ID(s):\n ${returned_record_id}\n\nRun with -f to overwrite.\n"
      exit 1
    fi
  else
    writeDNS $domain
  fi
else
  echo -e "Domain does not exist in DigitalOcean DNS, exiting...\n"
  exit 1
fi
